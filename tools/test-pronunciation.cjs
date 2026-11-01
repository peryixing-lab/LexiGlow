/* Exercise actual ArkTS speech with Core Speech Kit events; audible quality requires a real device. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { createNativeAudio, createVoiceResources, createClock, settle, voice, nativeError, deferred } = require('./native-audio-test-harness.cjs');
const deveco = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || path.join(deveco, 'plugins/openharmony/ace-server/node_modules/typescript'));
const servicePath = path.resolve(__dirname, '../entry/src/main/ets/service/AudioService.ets');
const originalLoad = Module._load, originalEtsLoader = require.extensions['.ets'];
let kits;
Module._load = function(name, parent, isMain) {
  if (kits && Object.prototype.hasOwnProperty.call(kits, name)) { return kits[name]; }
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = function(module, filename) {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: filename
  });
  module._compile(result.outputText, filename);
};
const observe = promise => promise.then(value => ({ value }), error => ({ error }));
async function withHarness(run, voices) {
  delete require.cache[servicePath];
  delete require.cache[path.resolve(__dirname, '../entry/src/main/ets/service/OfflineVoiceResources.ets')];
  const clock = createClock(), resources = createVoiceResources(), native = createNativeAudio({ voices });
  kits = { '@kit.CoreSpeechKit': { textToSpeech: native.tts }, '@kit.BasicServicesKit': {}, '@kit.AbilityKit': {},
    '@kit.CoreFileKit': { fileIo: resources.fileIo }, '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } } };
  const { AudioService } = require(servicePath), audio = AudioService.getInstance();
  audio.initialize(resources.context);
  const h = { ...native, audio, resources, clock, complete: (request, type) => native.complete(clock, request, type) };
  try { await run(h); }
  finally {
    audio.destroy(); await settle();
    try {
      assert.equal(clock.timers.size, 0, 'teardown clears playback and download timers');
      assert.ok(native.engines.every(engine => engine.shutdowns === 1), 'all created engines shut down exactly once');
      assert.ok(native.downloads.every(download => download.callbacks.size === 0), 'all download listeners detached');
    } finally { clock.restore(); }
  }
}
const tests = [
  ['startup performs cache migration without playing or downloading speech', () => withHarness(async h => {
    await settle(); assert.equal(h.spoken.length, 0); assert.equal(h.downloads.length, 0); assert.equal(h.queries.length, 0);
  })],
  ['English uses the installed Laura Core Speech voice and media volume', () => withHarness(async h => {
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'installed');
    const playback = h.audio.speak(' glow '); await settle();
    const request = h.spoken.at(-1); assert.equal(request.text, 'glow');
    assert.equal(request.engine.params.person, 8); assert.equal(request.engine.params.language, 'en-US');
    assert.equal(request.engine.params.online, 1); assert.equal(request.options.extraParams.playType, 1);
    assert.equal(request.options.extraParams.soundChannel, 12); assert.equal(h.downloads.length, 0);
    await h.complete(); await playback;
  })],
  ['prefer installed English over downloadable voices and normalize underscore language', () => withHarness(async h => {
    const playback = h.audio.speak('state'); await settle();
    assert.equal(h.engines[0].params.person, 9); await h.complete(); await playback;
  }, [voice('en-US', 8, 'GA'), voice('en_US', 9)])],
  ['Laura is preferred when multiple installed English voices are reported', () => withHarness(async h => {
    const playback = h.audio.speak('state'); await settle();
    assert.equal(h.engines[0].params.person, 8); await h.complete(); await playback;
  }, [voice('en-US', 9), voice('en-US', 8)])],
  ['explicit download prefers reported Laura when multiple downloadable voices exist', () => withHarness(async h => {
    const download = h.audio.installEnglishVoice(); await settle();
    assert.equal(h.downloads[0].params.person, 8); h.downloads[0].emit('complete'); await download;
    assert.equal(h.engines[0].params.person, 8); assert.equal(h.spoken.length, 0);
  }, [voice('en-US', 9, 'GA'), voice('en-US', 8, 'GA')])],
  ['status-less system voice can initialize without assuming a model download', () => withHarness(async h => {
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'installed'); assert.equal(h.downloads.length, 0);
  }, [{ ...voice(), status: undefined }])],
  ['downloadable English falls back to installed Huawei bilingual speech without downloading', () => withHarness(async h => {
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'compatible');
    const playback = h.audio.speak('business'); await settle();
    assert.equal(h.spoken.at(-1).language, 'zh-CN'); assert.equal(h.spoken.at(-1).options.extraParams.languageContext, 'en-US');
    assert.equal(h.downloads.length, 0); await h.complete(); await playback;
  }, [voice('en-US', 8, 'GA'), voice('zh-CN')])],
  ['missing English and bilingual voices report downloadable status and actionable setup error', () => withHarness(async h => {
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'downloadable');
    await assert.rejects(h.audio.speak('state'), /我的 → 单词朗读/); assert.equal(h.downloads.length, 0);
  }, [voice('en-US', 8, 'GA')])],
  ['EOM and unsupported voices never initialize or download', () => withHarness(async h => {
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'unavailable');
    await assert.rejects(h.audio.speak('state'), /未提供英语/);
    await assert.rejects(h.audio.installEnglishVoice(), /未提供可下载/); assert.equal(h.engines.length, 0);
  }, [voice('en-US', 8, 'EOM'), voice('fr-FR', 8)])],
  ['synthesis completion does not end speech before audible completion', () => withHarness(async h => {
    let ended = false, starts = 0;
    const playback = h.audio.speak('pronunciation', 'en-US', false, () => starts++).then(() => { ended = true; });
    await settle(); assert.equal(starts, 1); await h.complete(undefined, 0); assert.equal(ended, false);
    await h.complete(); await playback; assert.equal(ended, true);
  })],
  ['English engines stay cached between words', () => withHarness(async h => {
    for (const word of ['state', 'business', 'pronunciation']) {
      const playback = h.audio.speak(word); await settle(); await h.complete(); await playback;
    }
    assert.equal(h.engines.length, 1); assert.equal(h.queries.length, 1);
  })],
  ['new speech cancels the old request and stale completion cannot finish replacement', () => withHarness(async h => {
    const first = h.audio.speak('state'); await settle(); const old = h.spoken.at(-1);
    let ended = false; const second = h.audio.speak('business').then(() => { ended = true; }); await settle(); await first;
    await h.complete(old); assert.equal(ended, false); await h.complete(); await second;
    assert.notEqual(old.options.requestId, h.spoken.at(-1).options.requestId);
  })],
  ['stopForeground preserves background speech and foreground requests interrupt Audio Flow', () => withHarness(async h => {
    let interruptions = 0; h.audio.setForegroundInterruption(() => interruptions++);
    const flow = h.audio.speak('word', 'en-US', true); await settle(); h.audio.stopForeground();
    assert.equal(h.spoken.at(-1).engine.active, true); assert.equal(h.spoken.at(-1).options.extraParams.soundChannel, 3);
    const foreground = h.audio.speak('next'); await settle(); await flow; assert.equal(interruptions, 1);
    h.audio.stopForeground(); await foreground; assert.equal(h.spoken.at(-1).engine.active, false);
  })],
  ['release during engine initialization shuts down the late engine without speaking', () => withHarness(async h => {
    const gate = deferred(); h.controls.engineGate = gate.promise;
    const playback = h.audio.speak('word'); await settle(); h.audio.release(); gate.resolve(); await playback;
    assert.equal(h.spoken.length, 0); assert.equal(h.engines[0].shutdowns, 1);
  })],
  ['concurrent initialization coalesces and canceled speech cannot start late', () => withHarness(async h => {
    const gate = deferred(); h.controls.engineGate = gate.promise;
    const first = h.audio.speak('state'); const second = h.audio.speak('business'); await settle();
    assert.equal(h.engines.length, 1); gate.resolve(); await settle(); await first;
    assert.equal(h.spoken.length, 1); assert.equal(h.spoken[0].text, 'business'); await h.complete(); await second;
  })],
  ['native playback failures include the real error and invalidate the failed engine', () => withHarness(async h => {
    const result = observe(h.audio.speak('word')); await settle(); const request = h.spoken.at(-1);
    request.engine.listener.onError(request.options.requestId, 1002300005, 'engine unavailable');
    assert.match((await result).error.message, /1002300005/); assert.equal(request.engine.shutdowns, 1);
    const next = h.audio.speak('again'); await settle(); assert.equal(h.engines.length, 2); await h.complete(); await next;
  })],
  ['device voice query errors remain actionable and do not trigger downloads', () => withHarness(async h => {
    h.controls.queryError = nativeError(1002300005, 'System service unavailable');
    await assert.rejects(h.audio.getEnglishVoiceStatus(), /1002300005/);
    await assert.rejects(h.audio.speak('state'), /System service unavailable/);
    assert.equal(h.engines.length, 0); assert.equal(h.downloads.length, 0);
  })],
  ['listener registration failure shuts down both attempted engines without playback', () => withHarness(async h => {
    h.controls.listenerError = nativeError(1002300005, 'Listener unavailable');
    await assert.rejects(h.audio.speak('state'), /无法监听/);
    assert.equal(h.engines.length, 2); assert.equal(h.spoken.length, 0);
    assert.ok(h.engines.every(engine => engine.shutdowns === 1));
  })],
  ['synchronous speak errors reject and release the failed engine', () => withHarness(async h => {
    h.controls.speakError = nativeError(1002300005, 'native failure');
    await assert.rejects(h.audio.speak('word'), /native failure/); assert.equal(h.engines[0].shutdowns, 1);
  })],
  ['native stop is an interruption instead of successful playback', () => withHarness(async h => {
    const result = observe(h.audio.speak('word')); await settle(); const request = h.spoken.at(-1);
    request.engine.listener.onStop(request.options.requestId, { type: 1 }); assert.match((await result).error.message, /被中断/);
  })],
  ['watchdog rejects an absent playback completion and clears resources', () => withHarness(async h => {
    const result = observe(h.audio.speak('word')); await settle(); await h.clock.advance(30000);
    assert.match((await result).error.message, /未能完成/); assert.equal(h.engines[0].shutdowns, 1);
  })],
  ['explicit download uses reported VoiceInfo then enables installed English', () => withHarness(async h => {
    const first = h.audio.installEnglishVoice(); const second = h.audio.installEnglishVoice(); await settle();
    assert.equal(h.downloads.length, 1); const download = h.downloads[0];
    assert.equal(download.params.language, 'en_US'); assert.equal(download.params.person, 8);
    assert.equal(download.params.style, 'interaction-broadcast'); download.emit('complete'); await Promise.all([first, second]);
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'installed');
    assert.equal(h.downloads[0].callbacks.size, 0); assert.equal(h.spoken.length, 0, 'download must not play a test word');
  }, [voice('en_US', 8, 'GA')])],
  ['already installed voice never invokes downloadVoice', () => withHarness(async h => {
    await h.audio.installEnglishVoice(); assert.equal(h.downloads.length, 0);
  })],
  ['canceling system download rejects with retry guidance and detaches every event', () => withHarness(async h => {
    const result = observe(h.audio.installEnglishVoice()); await settle(); h.downloads[0].emit('cancel');
    assert.match((await result).error.message, /已取消/); assert.equal(h.downloads[0].callbacks.size, 0);
  }, [voice('en-US', 8, 'GA')])],
  ['download native error is visible, retry can complete successfully', () => withHarness(async h => {
    const result = observe(h.audio.installEnglishVoice()); await settle(); h.downloads[0].emit('error', nativeError(1002300008, 'network unavailable'));
    assert.match((await result).error.message, /1002300008/);
    const retry = h.audio.installEnglishVoice(); await settle(); h.downloads[1].emit('complete'); await retry;
    assert.equal(await h.audio.getEnglishVoiceStatus(), 'installed');
  }, [voice('en-US', 8, 'GA')])],
  ['unanswered download dialog times out without leaving a blocked UI request', () => withHarness(async h => {
    const result = observe(h.audio.installEnglishVoice()); await settle(); await h.clock.advance(120000);
    assert.match((await result).error.message, /未收到/); assert.equal(h.downloads[0].callbacks.size, 0);
  }, [voice('en-US', 8, 'GA')])],
  ['release during download detaches events and rejects wait; late callbacks are harmless', () => withHarness(async h => {
    const result = observe(h.audio.installEnglishVoice()); await settle(); h.audio.release();
    assert.match((await result).error.message, /已取消/); h.downloads[0].emit('complete'); assert.equal(h.engines.length, 0);
  }, [voice('en-US', 8, 'GA')])],
  ['release before the download callback arrives cannot attach late listeners or start an engine', () => withHarness(async h => {
    const gate = deferred(); h.controls.downloadGate = gate.promise;
    const result = observe(h.audio.installEnglishVoice()); await settle(); h.audio.release();
    assert.match((await result).error.message, /已取消/); gate.resolve(); await settle();
    assert.equal(h.downloads[0].callbacks.size, 0); assert.equal(h.engines.length, 0);
  }, [voice('en-US', 8, 'GA')])],
  ['invalid text and language cannot start engines or downloads', () => withHarness(async h => {
    for (const text of ['', '  ', 'a'.repeat(501)]) { await assert.rejects(h.audio.speak(text), /为空或过长/); }
    await assert.rejects(h.audio.speak('bonjour', 'fr-FR'), /仅支持/);
    assert.equal(h.engines.length, 0); assert.equal(h.downloads.length, 0);
  })],
  ['upgrade deletes only retired model and frontend cache files, preserving user data', () => withHarness(async h => {
    const folder = h.resources.context.cacheDir + '/offline-speech-melo-en-f16storage-old';
    h.resources.directories.add(folder);
    for (const name of ['model.onnx', 'tokens.txt', 'lexicon.txt', 'model.onnx.preparing', 'tokens.txt.preparing', 'lexicon.txt.preparing', 'my-study.json']) {
      h.resources.files.set(folder + '/' + name, new Uint8Array([1]));
    }
    const unrelated = h.resources.context.cacheDir + '/other-model/model.onnx'; h.resources.files.set(unrelated, new Uint8Array([2]));
    h.audio.initialize(h.resources.context); await settle();
    assert.deepEqual([...h.resources.files.keys()].sort(), [folder + '/my-study.json', unrelated].sort());
  })]
];
(async () => {
  let failures = 0;
  for (const [name, test] of tests) {
    try { await test(); console.log('PASS ' + name); }
    catch (error) { failures++; console.error('FAIL ' + name + '\n' + error.stack); }
  }
  Module._load = originalLoad;
  if (originalEtsLoader) { require.extensions['.ets'] = originalEtsLoader; } else { delete require.extensions['.ets']; }
  if (failures) { process.exitCode = 1; } else { console.log(`Pronunciation: ${tests.length} Core Speech lifecycle and download checks passed.`); }
})();
