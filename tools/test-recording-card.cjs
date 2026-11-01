/* Run actual recording/snapshot service methods with controlled SDK lifecycles.
 * Microphone fidelity, platform permission UI and PNG appearance require a device. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || path.join(
  process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents',
  'plugins/openharmony/ace-server/node_modules/typescript'));
const ets = path.resolve(__dirname, '../entry/src/main/ets');
const drain = async () => { for (let i = 0; i < 10; i++) { await new Promise(r => setImmediate(r)); } };
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
function load(file, kits) {
  const exports = {};
  const source = ts.transpileModule(fs.readFileSync(path.join(ets, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  new Function('exports', 'require', source)(exports, name => {
    assert.ok(name in kits, `unmocked dependency ${name}`); return kits[name];
  });
  return exports;
}
const wav = load('utils/RecordingWav.ets', {});
function harness() {
  const files = new Map(), handles = new Map(), capturers = [], players = [], timers = new Map(), statuses = [];
  const control = { permission: 0, createGate: undefined, startGate: undefined, playerGate: undefined,
    snapshotFail: false, packFail: false, writeFail: false, cancelSave: false, speechGate: undefined };
  let nextFd = 0, nextTimer = 0, packerReleases = 0, pixelReleases = 0, speechStops = 0, speechActive = false;
  const oldTimeout = global.setTimeout, oldClear = global.clearTimeout;
  global.setTimeout = (callback, delay) => { const id = ++nextTimer; timers.set(id, { callback, delay }); return id; };
  global.clearTimeout = id => timers.delete(id);
  const fileIo = {
    accessSync: filename => files.has(filename),
    listFileSync: dir => [...files.keys()].filter(x => x.startsWith(`${dir}/`)).map(x => x.slice(dir.length + 1)),
    unlinkSync: filename => files.delete(filename),
    openSync(filename, mode) {
      const file = { fd: ++nextFd, path: filename };
      if (mode & 4) { files.set(filename, new Uint8Array()); }
      assert.ok(files.has(filename), 'read file exists'); handles.set(file.fd, file); return file;
    },
    async open(filename, mode) { return this.openSync(filename, mode); },
    writeSync(fd, buffer) {
      if (control.writeFail) { return 0; }
      const file = handles.get(fd); assert.ok(file, 'write FD is open');
      const old = files.get(file.path), count = Math.min(buffer.byteLength, 7777);
      const next = new Uint8Array(old.length + count); next.set(old); next.set(new Uint8Array(buffer, 0, count), old.length);
      files.set(file.path, next); return count;
    },
    async write(fd, bytes) { return this.writeSync(fd, bytes); },
    statSync(fd) { return { size: files.get(handles.get(fd).path).length }; },
    closeSync(file) { assert.ok(handles.delete(file.fd), 'FD closes exactly once'); },
    async close(file) { this.closeSync(file); },
    OpenMode: { READ_ONLY: 1, READ_WRITE: 2, CREATE: 4, TRUNC: 8 }
  };
  const audio = {
    AudioSamplingRate: { SAMPLE_RATE_44100: 44100 }, AudioChannel: { CHANNEL_1: 1 },
    AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 }, AudioEncodingType: { ENCODING_TYPE_RAW: 0 },
    SourceType: { SOURCE_TYPE_MIC: 0 }, AudioState: { STATE_RUNNING: 2 },
    InterruptHint: { INTERRUPT_HINT_STOP: 3, INTERRUPT_HINT_PAUSE: 2 }, StreamUsage: { STREAM_USAGE_MUSIC: 1 },
    async createAudioCapturer(options) {
      assert.equal(options.streamInfo.samplingRate, 44100);
      if (control.createGate) { await control.createGate; }
      const callbacks = new Map();
      const capturer = { state: 1, starts: 0, stops: 0, releases: 0, callbacks,
        on(event, callback) { callbacks.set(event, callback); }, off(event) { callbacks.delete(event); },
        async start() { this.starts++; if (control.startGate) { await control.startGate; } this.state = 2; },
        async stop() { this.stops++; this.state = 3; },
        async release() { this.releases++; assert.equal(this.releases, 1); this.state = 4; },
        emit(bytes) { callbacks.get('readData')?.(bytes.buffer); }
      };
      capturers.push(capturer); return capturer;
    }
  };
  const media = { async createAVPlayer() {
    if (control.playerGate) { await control.playerGate; }
    const callbacks = new Map();
    const player = { state: 'idle', releases: 0, stops: 0, callbacks,
      on(event, callback) { callbacks.set(event, callback); }, off(event) { callbacks.delete(event); },
      set fdSrc(source) { assert.ok(handles.has(source.fd)); this.source = source; this.emit('initialized'); },
      emit(state) { this.state = state; callbacks.get('stateChange')?.(state); },
      async prepare() { this.emit('prepared'); }, async play() { this.emit('playing'); },
      async stop() { this.stops++; this.emit('stopped'); },
      async release() { this.releases++; assert.equal(this.releases, 1); this.state = 'released'; }
    }; players.push(player); return player;
  } };
  const speech = { stop() { speechStops++; if (speechActive && control.speechGate) { control.speechGate.resolve(); } },
    async speak() { speechActive = true; if (control.speechGate) { await control.speechGate.promise; } speechActive = false; } };
  const kits = { '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({
    async requestPermissionsFromUser(_context, permissions) {
      assert.deepEqual(permissions, ['ohos.permission.MICROPHONE']); return { authResults: [control.permission] };
    }
  }) } }, '@kit.AudioKit': { audio }, '@kit.MediaKit': { media }, '@kit.CoreFileKit': { fileIo,
    picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save(options) {
      assert.match(options.newFileNames[0], /\.png$/); return control.cancelSave ? [] : ['/destination/card.png'];
    } } } }, '@kit.BasicServicesKit': {}, '../utils/RecordingWav': wav,
    './AudioService': { AudioService: { getInstance: () => speech } }, '@kit.ArkUI': {},
    '@kit.ImageKit': { image: { createImagePacker() { return {
      async packing(_pixel, options) { assert.equal(options.format, 'image/png');
        if (control.packFail) { throw new Error('packing failed'); } return new Uint8Array([137, 80, 78, 71]).buffer; },
      async release() { packerReleases++; }
    }; } } } };
  const { ReadAlongRecorderService } = load('service/ReadAlongRecorderService.ets', kits);
  const { StudyCardImageService } = load('service/StudyCardImageService.ets', kits);
  const context = { cacheDir: '/cache' };
  const uiContext = { getHostContext: () => context, getComponentSnapshot: () => ({ async get(id) {
    assert.equal(id, 'card'); if (control.snapshotFail) { throw new Error('snapshot unavailable'); }
    return { async release() { pixelReleases++; } };
  } }) };
  const recorder = new ReadAlongRecorderService();
  recorder.setListener((...args) => statuses.push(args));
  return { recorder, files, handles, capturers, players, timers, statuses, control, context,
    StudyCardImageService, uiContext, get pixelReleases() { return pixelReleases; },
    get packerReleases() { return packerReleases; }, get speechStops() { return speechStops; },
    async recorded() { await recorder.start(context); capturers.at(-1).emit(new Uint8Array(44100)); await recorder.stop(); },
    async cleanup() { try { await recorder.dispose(); await drain();
      assert.equal(handles.size, 0, 'no leaked file descriptors'); assert.equal(timers.size, 0, 'no leaked timers');
      assert.ok(capturers.every(x => x.releases === 1 && x.callbacks.size === 0), 'all capturers/listeners released');
      assert.ok(players.every(x => x.releases === 1 && x.callbacks.size === 0), 'all players/listeners released');
      assert.ok([...files.keys()].every(x => !x.startsWith('/cache/')), 'leave page removes recordings');
    } finally { global.setTimeout = oldTimeout; global.clearTimeout = oldClear; } }
  };
}
const tests = [
  ['permission rejection is a false result with no capture or file', async h => {
    h.control.permission = -1; assert.equal(await h.recorder.requestPermission(h.context), false);
    assert.equal(h.capturers.length, 0); assert.equal(h.files.size, 0);
  }],
  ['release during capturer creation prevents late recording', async h => {
    const pending = gate(); h.control.createGate = pending.promise;
    const starting = h.recorder.start(h.context); await drain(); const disposal = h.recorder.dispose();
    pending.resolve(); await starting; await disposal;
    assert.equal(h.capturers[0].starts, 0); assert.equal(h.capturers[0].releases, 1);
  }],
  ['release during start stops late native capture and removes all buffers', async h => {
    const pending = gate(); h.control.startGate = pending.promise;
    const starting = h.recorder.start(h.context); await drain(); const disposal = h.recorder.dispose();
    pending.resolve(); await starting; await disposal; assert.equal(h.capturers[0].stops, 1);
  }],
  ['background stop invokes native stop before any awaited cleanup', async h => {
    await h.recorder.start(h.context); h.capturers[0].emit(new Uint8Array(44100));
    const stopping = h.recorder.stop(); assert.equal(h.capturers[0].stops, 1); await stopping;
    assert.equal(h.capturers[0].releases, 1);
  }],
  ['ten second recording is bounded and emits a playable PCM16 RIFF header', async h => {
    await h.recorder.start(h.context); h.capturers[0].emit(new Uint8Array(wav.RECORDING_MAX_BYTES + 10000));
    const limit = [...h.timers.values()].find(x => x.delay === 10000); assert.ok(limit); limit.callback(); await drain();
    const bytes = [...h.files.values()][0], view = new DataView(bytes.buffer);
    assert.equal(bytes.length, 44 + wav.RECORDING_MAX_BYTES);
    assert.equal(Buffer.from(bytes.slice(0, 4)).toString(), 'RIFF'); assert.equal(view.getUint32(24, true), 44100);
    assert.equal(view.getUint16(34, true), 16); assert.equal(view.getUint32(40, true), wav.RECORDING_MAX_BYTES);
  }],
  ['zero length press produces no cached recording', async h => {
    await h.recorder.start(h.context); await h.recorder.stop(); assert.equal(h.files.size, 0);
  }],
  ['short file writes are retried and failure closes handle and deletes partial recording', async h => {
    await h.recorded(); assert.equal([...h.files.values()][0].length, 44144);
    await h.recorder.start(h.context); h.capturers.at(-1).emit(new Uint8Array(44100));
    h.control.writeFail = true; await h.recorder.stop(); assert.equal(h.handles.size, 0); assert.equal(h.files.size, 0);
  }],
  ['new recording removes previous speech and stale crash cache only', async h => {
    h.files.set('/cache/lexiglow_follow_123.wav', new Uint8Array()); h.files.set('/cache/learning.db', new Uint8Array());
    await h.recorded(); assert.ok(!h.files.has('/cache/lexiglow_follow_123.wav')); assert.ok(h.files.has('/cache/learning.db'));
    h.files.delete('/cache/learning.db');
  }],
  ['playback completion releases player and open file before promise resolves', async h => {
    await h.recorded(); const playback = h.recorder.play(); await drain();
    assert.equal(h.players[0].state, 'playing'); h.players[0].emit('completed'); await playback;
    assert.equal(h.players[0].releases, 1); assert.equal(h.handles.size, 0);
  }],
  ['page departure during pending player creation releases its late player', async h => {
    await h.recorded(); const pending = gate(); h.control.playerGate = pending.promise;
    const playback = h.recorder.play(); await drain(); const disposal = h.recorder.dispose();
    pending.resolve(); await playback; await disposal; assert.equal(h.players[0].releases, 1);
  }],
  ['alternating playback waits for original before starting recorded voice', async h => {
    await h.recorded(); const pending = gate(); h.control.speechGate = pending;
    const playback = h.recorder.play('glow'); await drain(); assert.equal(h.players.length, 0);
    pending.resolve(); await drain(); assert.equal(h.players.length, 1);
    h.players[0].emit('completed'); await playback;
  }],
  ['background cancels original and never starts the recording afterwards', async h => {
    await h.recorded(); const pending = gate(); h.control.speechGate = pending;
    const playback = h.recorder.play('glow'); await drain(); await h.recorder.stopPlayback(); await playback;
    assert.equal(h.players.length, 0);
  }],
  ['player cancellation stops audio and frees its FD', async h => {
    await h.recorded(); const playback = h.recorder.play(); await drain();
    await h.recorder.stopPlayback(); await playback; assert.equal(h.players[0].stops, 1); assert.equal(h.handles.size, 0);
  }],
  ['snapshot save releases packer and pixel map and closes destination', async h => {
    assert.equal(await h.StudyCardImageService.save(h.uiContext, 'card', '2026-10-13'), true);
    assert.equal(h.packerReleases, 1); assert.equal(h.pixelReleases, 1); assert.equal(h.handles.size, 0);
    assert.deepEqual([...h.files.get('/destination/card.png')], [137, 80, 78, 71]);
  }],
  ['canceling image save is successful cancellation without creating a file', async h => {
    h.control.cancelSave = true; assert.equal(await h.StudyCardImageService.save(h.uiContext, 'card', '2026-10-13'), false);
    assert.equal(h.files.size, 0); assert.equal(h.packerReleases, 1); assert.equal(h.pixelReleases, 1);
  }],
  ['packer failure releases snapshot resources', async h => {
    h.control.packFail = true; await assert.rejects(h.StudyCardImageService.save(h.uiContext, 'card', '2026-10-13'));
    assert.equal(h.packerReleases, 1); assert.equal(h.pixelReleases, 1); assert.equal(h.handles.size, 0);
  }],
  ['PNG write failure closes destination file', async h => {
    h.control.writeFail = true; await assert.rejects(h.StudyCardImageService.save(h.uiContext, 'card', '2026-10-13'));
    assert.equal(h.packerReleases, 1); assert.equal(h.pixelReleases, 1); assert.equal(h.handles.size, 0);
  }]
];
(async () => {
  for (const [name, run] of tests) {
    const h = harness(); try { await run(h); console.log(`PASS ${name}`); } finally { await h.cleanup(); }
  }
  console.log(`${tests.length} recording/card lifecycle regressions passed; physical-device validation remains separate.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
