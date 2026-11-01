/* Core Speech Kit boundary mocks. Device playback and system download dialogs need a real device. */
const assert = require('node:assert/strict');
const settle = async () => { for (let i = 0; i < 10; i++) { await new Promise(resolve => setImmediate(resolve)); } };
const voice = (language = 'en-US', person = language === 'en-US' ? 8 : 13, status = 'INSTALLED') =>
  ({ language, person, status, style: 'interaction-broadcast', gender: 'Female', description: '' });
const nativeError = (code, message) => Object.assign(new Error(message), { code });
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject }; };
function createClock() {
  const originalTimeout = global.setTimeout, originalClearTimeout = global.clearTimeout, originalNow = Date.now;
  let now = 1800000000000, id = 0;
  const timers = new Map();
  global.setTimeout = (callback, delay = 0) => {
    const key = ++id; timers.set(key, { callback, at: now + delay });
    if (delay === 0) { setImmediate(() => { const timer = timers.get(key); if (timer) { timers.delete(key); timer.callback(); } }); }
    return key;
  };
  global.clearTimeout = key => timers.delete(key);
  Date.now = () => now;
  return { timers,
    async advance(milliseconds) {
      const target = now + milliseconds;
      for (;;) {
        const next = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) { break; }
        now = next[1].at; timers.delete(next[0]); next[1].callback(); await settle();
      }
      now = target; await settle();
    },
    restore() { global.setTimeout = originalTimeout; global.clearTimeout = originalClearTimeout; Date.now = originalNow; }
  };
}
function createVoiceResources() {
  const files = new Map(), directories = new Set(['/fixture/cache']), calls = [];
  const fileIo = {
    async stat(name) { calls.push(['stat', name]);
      if (directories.has(name)) { return { isDirectory: () => true }; }
      if (files.has(name)) { return { isDirectory: () => false }; }
      throw nativeError(13900002, 'Missing file');
    },
    async listFile(folder, options) { calls.push(['listFile', folder, options]); assert.equal(options.recursion, false);
      const prefix = `${folder}/`; return [...new Set([...directories, ...files.keys()].filter(name => name.startsWith(prefix))
        .map(name => name.slice(prefix.length).split('/')[0]))]; },
    async unlink(name) { calls.push(['unlink', name]); files.delete(name); }
  };
  const context = { cacheDir: '/fixture/cache',
    abilityInfo: { bundleName: 'com.lovexjy.lexiglow', name: 'EntryAbility', moduleName: 'entry' } };
  return { files, directories, calls, context, fileIo };
}
function createNativeAudio({ voices = [voice(), voice('zh-CN')], onSpeech = () => {} } = {}) {
  const controls = { voices, queryError: undefined, queryGate: undefined, engineError: undefined,
    engineGate: undefined, listenerError: undefined, speakError: undefined,
    downloadError: undefined, downloadThrow: undefined, downloadGate: undefined,
    downloadListenError: undefined, shutdownStops: false };
  const queries = [], engines = [], spoken = [], downloads = [];
  const tts = {
    async listVoices(params) {
      queries.push(params); assert.equal(params.online, 1, 'only offline mode is allowed');
      if (controls.queryGate) { await controls.queryGate; }
      if (controls.queryError) { throw controls.queryError; }
      return controls.voices.map(value => ({ ...value }));
    },
    async createEngine(params) {
      assert.equal(params.online, 1); assert.ok(['en-US', 'zh-CN'].includes(params.language));
      if (controls.engineError) { throw controls.engineError; }
      const engine = { params, active: false, stopped: 0, shutdowns: 0, listener: undefined,
        setListener(listener) { if (controls.listenerError) { throw controls.listenerError; } this.listener = listener; },
        speak(text, options) {
          this.lastRequestId = options.requestId;
          if (controls.speakError) { throw controls.speakError; }
          this.active = true;
          const request = { text, options, language: params.language, engine: this };
          spoken.push(request); onSpeech(request); this.listener.onStart(options.requestId, { type: 1 });
        },
        stop() { this.active = false; this.stopped++; },
        shutdown() { this.active = false; this.shutdowns++;
          if (controls.shutdownStops && this.lastRequestId) { this.listener?.onStop(this.lastRequestId, { type: 1 }); }
        }
      };
      engines.push(engine);
      if (controls.engineGate) { await controls.engineGate; }
      return engine;
    },
    downloadVoice(params, callback) {
      if (controls.downloadThrow) { throw controls.downloadThrow; }
      const callbacks = new Map();
      const response = {
        requestId: params.requestId,
        on(name, handler) { if (controls.downloadListenError) { throw controls.downloadListenError; } callbacks.set(name, handler); },
        off(name) { callbacks.delete(name); }
      };
      const call = { params, response, callbacks,
        emit(name, value) {
          if (name === 'complete') {
            for (const item of controls.voices) {
              if (item.language === params.language && item.person === params.person) { item.status = 'INSTALLED'; }
            }
          }
          callbacks.get(name)?.(value || voice(params.language, params.person));
        }
      };
      downloads.push(call);
      const deliver = () => callback(controls.downloadError, response);
      if (controls.downloadGate) { controls.downloadGate.then(deliver); } else { deliver(); }
    }
  };
  return { controls, tts, queries, engines, spoken, downloads,
    async complete(_clock, request = spoken.at(-1), type = 1) {
      assert.ok(request, 'a native speech request must exist');
      if (type === 1) { request.engine.active = false; }
      request.engine.listener.onComplete(request.options.requestId, { type }); await settle();
    }
  };
}
module.exports = { createNativeAudio, createVoiceResources, createClock, settle, voice, nativeError, deferred };
