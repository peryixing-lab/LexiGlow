/* Exercise the real ArkTS AudioFlowService and AudioService with event-driven native mocks.
 * Audible quality and real Bluetooth routing remain separate device checks. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { createNativeAudio, createVoiceResources, createClock } = require('./native-audio-test-harness.cjs');
const deveco = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  path.join(deveco, 'plugins/openharmony/ace-server/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const sources = path.join(root, 'entry/src/main/ets');
const originalLoad = Module._load;
const originalEtsLoader = require.extensions['.ets'];
const originalTimeout = global.setTimeout;
const originalClearTimeout = global.clearTimeout;
const originalNow = Date.now;
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

const drain = async () => { for (let i = 0; i < 10; i++) { await new Promise(resolve => setImmediate(resolve)); } };

function createHarness({ requirePlayingStream = false, delaySessionCreation = false, voices } = {}) {
  for (const filename of Object.keys(require.cache)) {
    if (filename.startsWith(sources + path.sep)) { delete require.cache[filename]; }
  }
  let activated = false, background = 0;
  const clock = createClock();
  const timers = clock.timers, sessions = [], events = [], audioEvents = new Map();
  const resources = createVoiceResources();
  const native = createNativeAudio({ voices,
    onSpeech: request => events.push(['speech', request.text, request.language]) });
  const { engines, spoken } = native;
  const taskEvents = new Map(), warnings = [];
  let sessionGateResolve;
  const sessionGate = delaySessionCreation ? new Promise(resolve => { sessionGateResolve = resolve; }) : Promise.resolve();
  const audioSession = {
    setAudioSessionScene(scene) { events.push(['scene', scene]); },
    on(name, callback) { audioEvents.set(name, callback); },
    off(name, callback) { if (audioEvents.get(name) === callback) { audioEvents.delete(name); } },
    async activateAudioSession() { activated = true; events.push(['audio-activate']); },
    async deactivateAudioSession() { activated = false; events.push(['audio-deactivate']); },
    isAudioSessionActivated() { return activated; }
  };
  kits = {
    '@kit.AbilityKit': { wantAgent: {
      OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
      async getWantAgent(info) { return { info }; }
    } },
    '@kit.CoreFileKit': { fileIo: resources.fileIo },
    '@kit.CoreSpeechKit': { textToSpeech: native.tts },
    '@kit.PerformanceAnalysisKit': { hilog: { warn(...args) { warnings.push(args); }, info() {} } },
    '@kit.AVSessionKit': { avSession: {
      PlaybackState: { PLAYBACK_STATE_PLAY: 1, PLAYBACK_STATE_PAUSE: 2 },
      async createAVSession(_context, name, type) {
        await sessionGate;
        assert.equal(type, 'audio');
        const callbacks = new Map();
        const session = {
          name, callbacks, metadata: [], playback: [], activated: false, destroyed: false,
          on(event, callback) { callbacks.set(event, callback); },
          async setLaunchAbility(agent) { this.agent = agent; },
          async setAVMetadata(value) { assert.equal(this.destroyed, false); this.metadata.push(value); },
          async setAVPlaybackState(value) { assert.equal(this.destroyed, false); this.playback.push(value); },
          async activate() { this.activated = true; },
          async deactivate() { this.activated = false; },
          async destroy() { this.destroyed = true; this.callbacks.clear(); }
        };
        sessions.push(session); return session;
      }
    } },
    '@kit.AudioKit': { audio: {
      getAudioManager() { return { getSessionManager() { return audioSession; } }; },
      AudioSessionScene: { AUDIO_SESSION_SCENE_MEDIA: 1 },
      AudioConcurrencyMode: { CONCURRENCY_DEFAULT: 0 },
      AudioSessionStateChangeHint: {
        AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE: 1,
        AUDIO_SESSION_STATE_CHANGE_HINT_STOP: 2,
        AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP: 3
      },
      AudioSessionDeactivatedReason: { DEACTIVATED_LOWER_PRIORITY: 1 },
      OutputDeviceChangeRecommendedAction: { DEVICE_CHANGE_RECOMMEND_TO_STOP: 1 }
    } },
    '@kit.BackgroundTasksKit': { backgroundTaskManager: {
      BackgroundMode: { AUDIO_PLAYBACK: 2 },
      on(name, callback) { taskEvents.set(name, callback); },
      off(name, callback) { if (taskEvents.get(name) === callback) { taskEvents.delete(name); } },
      async startBackgroundRunning(_context, mode) {
        assert.equal(mode, 2); assert.equal(activated, true, 'audio focus must be activated');
        if (requirePlayingStream && !engines.some(engine => engine.active)) {
          const error = new Error('Continuous task verification failed: no active audio stream');
          error.code = 9800005; throw error;
        }
        assert.equal(background, 0, 'one native background task at a time');
        background++; events.push(['background-start']);
      },
      async stopBackgroundRunning() {
        assert.equal(background, 1, 'stop only a running native background task');
        background--; events.push(['background-stop']);
      }
    } }
  };
  const { AudioService } = require(path.join(sources, 'service/AudioService.ets'));
  const { AudioFlowService } = require(path.join(sources, 'service/AudioFlowService.ets'));
  const flow = AudioFlowService.getInstance();
  const speech = AudioService.getInstance();
  const context = resources.context; speech.initialize(context);
  return {
    flow, speech, context, native, engines, spoken, sessions, events, audioEvents, taskEvents, timers, warnings,
    get background() { return background; },
    get audioActivated() { return activated; },
    releaseSessionGate() { sessionGateResolve?.(); },
    advance: milliseconds => clock.advance(milliseconds),
    complete: (request, type) => native.complete(clock, request, type),
    async cleanup() {
      try {
        sessionGateResolve?.();
        await flow.release(); speech.destroy(); await drain();
        assert.equal(background, 0, 'release must end the background task');
        assert.equal(activated, false, 'release must deactivate audio focus');
        assert.equal(audioEvents.size, 0, 'release must unregister audio callbacks');
        assert.equal(taskEvents.size, 0, 'release must unregister task callbacks');
        assert.ok(sessions.every(session => session.destroyed), 'release must destroy every AVSession');
        assert.equal(timers.size, 0, 'release must cancel recall and TTS watchdog timers');
        assert.equal(native.downloads.length, 0, 'flow cannot download a speech model');
        assert.ok(engines.every(engine => engine.shutdowns === 1), 'all system speech engines must shut down once');
      } finally { clock.restore(); }
    }
  };
}

const word = (id, spelling, meaning = 'n. 微光；光线', example = 'A gentle light shines.') =>
  ({ id, word: spelling, phonetic: '', meaning, example, translation: '', sourceBookId: 'cet4' });

async function withHarness(options, run) {
  const harness = createHarness(options);
  try { await run(harness); } finally { await harness.cleanup(); }
}

const tests = [
  ['downloadable English falls back to installed bilingual speech for the full queue without downloading', async () => withHarness({
    voices: [
      { language: 'en-US', person: 8, style: 'interaction-broadcast', status: 'GA' },
      { language: 'zh-CN', person: 13, style: 'interaction-broadcast', status: 'INSTALLED' }
    ], requirePlayingStream: true
  }, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain();
    assert.equal(h.flow.getState().status, 'playing');
    assert.equal(h.spoken[0].text, 'glow');
    assert.equal(h.spoken[0].language, 'zh-CN');
    assert.equal(h.spoken[0].options.extraParams.languageContext, 'en-US');
    assert.equal(h.engines.length, 1, 'one installed bilingual system engine serves both languages');
    await h.complete(); await h.advance(2000);
    assert.deepEqual([h.spoken.at(-1).text, h.spoken.at(-1).language], ['微光', 'zh-CN']);
    await h.complete(); assert.equal(h.spoken.at(-1).text, 'A gentle light shines.');
    assert.equal(h.spoken.at(-1).language, 'zh-CN');
    await h.complete(); assert.equal(h.flow.getState().status, 'completed');
    assert.equal(h.engines.length, 1); assert.equal(h.background, 0);
  })],
  ['native audible completion controls the full bilingual queue', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow'), word(2, 'shine', 'v. 发光', '')], h.context); await drain();
    assert.equal(h.flow.getState().status, 'playing');
    assert.deepEqual(h.spoken.map(request => [request.text, request.language]), [['glow', 'en-US']]);
    await h.complete(undefined, 0);
    assert.equal(h.flow.getState().stage, 'word', 'synthesis complete is not playback complete');
    await h.complete();
    assert.equal(h.flow.getState().stage, 'recall');
    await h.advance(1999); assert.equal(h.spoken.length, 1);
    await h.advance(1); assert.deepEqual([h.spoken.at(-1).text, h.spoken.at(-1).language], ['微光', 'zh-CN']);
    await h.complete(); assert.deepEqual([h.spoken.at(-1).text, h.spoken.at(-1).language], ['A gentle light shines.', 'en-US']);
    await h.complete(); assert.equal(h.spoken.at(-1).text, 'shine');
    await h.complete(); await h.advance(2000); assert.equal(h.spoken.at(-1).text, '发光');
    await h.complete(); assert.equal(h.flow.getState().status, 'completed');
    assert.equal(h.background, 0); assert.ok(h.sessions.every(session => session.destroyed));
  })],
  ['recall waits for Core Speech audible completion even after synthesis is complete', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain();
    await h.complete(undefined, 0); await h.advance(5000);
    assert.equal(h.flow.getState().stage, 'word');
    assert.equal(h.flow.getState().status, 'playing'); assert.equal(h.spoken.length, 1);
    await h.complete(); assert.equal(h.flow.getState().stage, 'recall');
    await h.advance(2000); assert.equal(h.spoken.at(-1).language, 'zh-CN');
  })],
  ['pause preserves the remaining recall window and requires explicit resume', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain(); await h.complete(); await h.advance(700);
    h.flow.pause(); await drain(); assert.equal(h.flow.getState().status, 'paused'); assert.equal(h.background, 0);
    await h.advance(5000); assert.equal(h.spoken.length, 1);
    await h.flow.resume(); await drain(); await h.advance(1299); assert.equal(h.spoken.length, 1);
    await h.advance(1); assert.equal(h.spoken.at(-1).language, 'zh-CN');
  })],
  ['stale speech completion cannot advance a replacement queue', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain(); const stale = h.spoken.at(-1);
    await h.flow.start([word(2, 'shine')], h.context); await drain(); const current = h.spoken.at(-1);
    await h.complete(stale); assert.equal(h.flow.getState().word.word, 'shine');
    assert.equal(h.flow.getState().stage, 'word');
    await h.complete(current); assert.equal(h.flow.getState().stage, 'recall');
  })],
  ['rapid next/previous/stop/start controls keep one surviving native session', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow'), word(2, 'shine'), word(3, 'bright')], h.context); await drain();
    await Promise.all([h.flow.next(), h.flow.next(), h.flow.previous(), h.flow.stop(),
      h.flow.start([word(4, 'gentle')], h.context)]); await drain();
    assert.equal(h.flow.getState().status, 'playing'); assert.equal(h.flow.getState().word.word, 'gentle');
    assert.equal(h.sessions.filter(session => !session.destroyed).length, 1);
    assert.equal(h.background, 1); assert.equal(h.spoken.at(-1).text, 'gentle');
  })],
  ['stop while native session creation is pending cannot start delayed playback', async () => withHarness({ delaySessionCreation: true }, async h => {
    const pendingStart = h.flow.start([word(1, 'glow')], h.context); await drain();
    const pendingStop = h.flow.stop(); h.releaseSessionGate(); await Promise.all([pendingStart, pendingStop]); await drain();
    assert.equal(h.flow.getState().status, 'idle'); assert.equal(h.spoken.length, 0);
    assert.equal(h.background, 0); assert.ok(h.sessions.every(session => session.destroyed));
  })],
  ['AVSession headphone controls, output removal, and focus loss pause safely', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow'), word(2, 'shine')], h.context); await drain();
    h.sessions.at(-1).callbacks.get('playNext')(); await drain(); assert.equal(h.flow.getState().index, 1);
    h.sessions.at(-1).callbacks.get('pause')(); await drain(); assert.equal(h.flow.getState().status, 'paused');
    h.sessions.at(-1).callbacks.get('playPrevious')(); await drain(); assert.equal(h.flow.getState().index, 0);
    assert.equal(h.flow.getState().status, 'paused');
    h.sessions.at(-1).callbacks.get('play')(); await drain(); assert.equal(h.flow.getState().status, 'playing');
    h.audioEvents.get('currentOutputDeviceChanged')({ recommendedAction: 1 }); await drain();
    assert.equal(h.flow.getState().status, 'paused'); assert.match(h.flow.getState().error, /断开/);
    await h.flow.resume(); await drain();
    h.audioEvents.get('audioSessionStateChanged')({ stateChangeHint: 1 }); await drain();
    assert.equal(h.flow.getState().status, 'paused'); assert.equal(h.background, 0);
    h.audioEvents.get('audioSessionStateChanged')({ stateChangeHint: 0 }); await drain();
    assert.equal(h.flow.getState().status, 'paused', 'focus regained must not unexpectedly resume speech');
  })],
  ['backgrounding cancels foreground pronunciation without cancelling Audio Flow', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain(); const active = h.spoken.at(-1);
    h.speech.stopForeground(); await drain();
    assert.equal(active.engine.active, true); assert.equal(h.flow.getState().status, 'playing');
    const foreground = h.speech.speak('shine'); await drain();
    assert.equal(h.flow.getState().status, 'paused', 'foreground pronunciation must interrupt the listening queue');
    h.speech.stopForeground(); await foreground; await drain(); assert.equal(h.spoken.at(-1).engine.active, false);
  })],
  ['system cancellation releases the task without silently restarting speech', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain();
    // Native task is already gone when its cancellation callback arrives.
    await kits['@kit.BackgroundTasksKit'].backgroundTaskManager.stopBackgroundRunning(h.context);
    h.taskEvents.get('continuousTaskCancel')({ reason: 6 }); await drain();
    assert.equal(h.flow.getState().status, 'paused'); assert.match(h.flow.getState().error, /系统结束/);
    assert.equal(h.audioActivated, false); await h.advance(10000); assert.equal(h.spoken.length, 1);
  })],
  ['completed flow replays its retained queue using cached Core Speech engines', async () => withHarness({}, async h => {
    await h.flow.start([word(1, 'glow', 'n. 微光', '')], h.context); await drain();
    await h.complete(); await h.advance(2000); await h.complete();
    assert.equal(h.flow.getState().status, 'completed'); assert.equal(h.background, 0);
    await h.flow.resume(); await drain();
    assert.equal(h.flow.getState().status, 'playing'); assert.equal(h.flow.getState().word.word, 'glow');
    assert.equal(h.spoken.at(-1).text, 'glow'); assert.equal(h.spoken.at(-1).language, 'en-US');
    assert.equal(h.engines.length, 2); assert.equal(h.background, 1);
    await h.complete(); await h.advance(2000); await h.complete();
    assert.equal(h.flow.getState().status, 'completed'); assert.equal(h.background, 0);
  })],
  ['a device requiring an active playback stream can start the background task', async () => withHarness({ requirePlayingStream: true }, async h => {
    await h.flow.start([word(1, 'glow')], h.context); await drain();
    assert.equal(h.flow.getState().status, 'playing', 'start native audio before requesting its background task');
    const start = h.events.findIndex(event => event[0] === 'background-start');
    const speech = h.events.findIndex(event => event[0] === 'speech');
    assert.ok(speech >= 0 && start > speech, 'a real speech stream must precede the background request');
    assert.equal(h.background, 1);
  })]
];

(async () => {
  let failures = 0;
  for (const [name, test] of tests) {
    try { await test(); console.log(`PASS ${name}`); }
    catch (error) { failures++; console.error(`FAIL ${name}\n${error.stack}`); }
  }
  Module._load = originalLoad;
  if (originalEtsLoader) { require.extensions['.ets'] = originalEtsLoader; } else { delete require.extensions['.ets']; }
  global.setTimeout = originalTimeout; global.clearTimeout = originalClearTimeout; Date.now = originalNow;
  if (failures) { process.exitCode = 1; }
  else { console.log(`Audio Flow: ${tests.length} lifecycle and native-event checks passed.`); }
})();
