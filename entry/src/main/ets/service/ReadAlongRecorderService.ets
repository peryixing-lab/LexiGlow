import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AudioService } from './AudioService';
import { recordingWav, RECORDING_LIMIT_MS, RECORDING_MAX_BYTES, RECORDING_SAMPLE_RATE } from '../utils/RecordingWav';

export type ReadAlongStateListener = (state: string, hasRecording: boolean, message: string) => void;

/** Each word detail owns one instance. Captured speech never leaves the app cache. */
export class ReadAlongRecorderService {
  private capturer?: audio.AudioCapturer;
  private startOperation?: Promise<void>;
  private stopOperation?: Promise<void>;
  private playbackOperation?: Promise<void>;
  private player?: media.AVPlayer;
  private playerStopOperation?: Promise<void>;
  private finishPlayback?: (error?: Error) => void;
  private chunks: Uint8Array[] = [];
  private byteLength: number = 0;
  private path: string = '';
  private wanted: boolean = false;
  private disposed: boolean = false;
  private timer: number = -1;
  private playbackGeneration: number = 0;
  private listener?: ReadAlongStateListener;
  private state: string = 'idle';
  private readListener: (buffer: ArrayBuffer) => void = (buffer: ArrayBuffer): void => {
    // The SDK forbids capturer API calls inside readData. Copy only; timer ends capture.
    if (!this.wanted || this.disposed) { return; }
    const count = Math.min(buffer.byteLength, RECORDING_MAX_BYTES - this.byteLength);
    if (count > 0) {
      this.chunks.push(new Uint8Array(buffer.slice(0, count)));
      this.byteLength += count;
    }
  };
  private interruptListener: (event: audio.InterruptEvent) => void = (event: audio.InterruptEvent): void => {
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP ||
      event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.stop().catch(() => {});
    }
  };

  setListener(listener?: ReadAlongStateListener): void { this.listener = listener; }

  async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    if (this.disposed) { return false; }
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
      ['ohos.permission.MICROPHONE']);
    return !this.disposed && result.authResults.length > 0 && result.authResults[0] === 0;
  }

  private publish(state: string, message: string = ''): void {
    this.state = state;
    if (!this.disposed && this.listener) { this.listener(state, this.path.length > 0, message); }
  }

  start(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.wanted || this.startOperation || this.stopOperation) { return Promise.resolve(); }
    this.wanted = true;
    this.publish('starting');
    const operation = this.startCapture(context);
    this.startOperation = operation;
    return operation.finally(() => { if (this.startOperation === operation) { this.startOperation = undefined; } });
  }

  private async startCapture(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.stopPlayback();
      AudioService.getInstance().stop();
      if (!this.wanted || this.disposed) { return; }
      this.deleteRecording();
      // Remove interrupted-process leftovers; only this feature's cache prefix is touched.
      fileIo.listFileSync(context.cacheDir).filter((name: string) => /^lexiglow_follow_\d+\.wav$/.test(name))
        .forEach((name: string) => { try { fileIo.unlinkSync(`${context.cacheDir}/${name}`); } catch (_) {} });
      this.chunks = [];
      this.byteLength = 0;
      const options: audio.AudioCapturerOptions = {
        streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_44100, channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE, encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
      };
      const capturer = await audio.createAudioCapturer(options);
      this.capturer = capturer;
      if (!this.wanted || this.disposed) { return; }
      capturer.on('readData', this.readListener);
      capturer.on('audioInterrupt', this.interruptListener);
      await capturer.start();
      if (!this.wanted || this.disposed) { return; }
      this.path = `${context.cacheDir}/lexiglow_follow_${Date.now()}.wav`;
      this.publish('recording');
      this.timer = setTimeout(() => { this.stop().catch(() => {}); }, RECORDING_LIMIT_MS);
    } catch (_) {
      this.wanted = false;
      await this.releaseCapturer();
      this.chunks = [];
      this.byteLength = 0;
      this.deleteRecording();
      this.publish('idle', '录音暂不可用，请检查麦克风权限后重试');
    }
  }

  stop(save: boolean = true): Promise<void> {
    this.wanted = false;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.stopOperation) { return this.stopOperation; }
    if (!this.capturer && !this.startOperation) { return Promise.resolve(); }
    this.publish('stopping');
    // Invoke stop immediately in the background callback, before awaiting setup/cleanup.
    let immediate: Promise<void> = Promise.resolve();
    if (this.capturer?.state === audio.AudioState.STATE_RUNNING) {
      immediate = this.capturer.stop().catch(() => {});
    }
    const operation = this.finishCapture(immediate, save);
    this.stopOperation = operation;
    return operation.finally(() => { if (this.stopOperation === operation) { this.stopOperation = undefined; } });
  }

  private async finishCapture(immediate: Promise<void>, save: boolean): Promise<void> {
    try {
      await immediate;
      if (this.startOperation) { await this.startOperation; }
      await this.releaseCapturer();
      if (save && !this.disposed && this.path && this.byteLength >= RECORDING_SAMPLE_RATE / 5) {
        const buffer = recordingWav(this.chunks, this.byteLength);
        const file = fileIo.openSync(this.path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (offset < buffer.byteLength) {
            const count = fileIo.writeSync(file.fd, buffer.slice(offset));
            if (count <= 0) { throw new Error('录音写入未完成'); }
            offset += count;
          }
        } finally { fileIo.closeSync(file); }
      } else { this.deleteRecording(); }
      this.publish(this.path ? 'ready' : 'idle', this.path ? '' : '按住片刻再松开，即可回放跟读');
    } catch (_) {
      this.deleteRecording();
      this.publish('idle', '录音未能保存，请再试一次');
    } finally {
      this.chunks = [];
      this.byteLength = 0;
    }
  }

  private async releaseCapturer(): Promise<void> {
    const capturer = this.capturer;
    this.capturer = undefined;
    if (!capturer) { return; }
    try { capturer.off('readData', this.readListener); } catch (_) {}
    try { capturer.off('audioInterrupt'); } catch (_) {}
    try { if (capturer.state === audio.AudioState.STATE_RUNNING) { await capturer.stop(); } }
    finally { await capturer.release(); }
  }

  private deleteRecording(): void {
    if (this.path) {
      try { if (fileIo.accessSync(this.path)) { fileIo.unlinkSync(this.path); } }
      finally { this.path = ''; }
    }
  }

  play(word: string = ''): Promise<void> {
    if (this.disposed || !this.path || this.wanted || this.startOperation || this.stopOperation) {
      return Promise.resolve();
    }
    const version = ++this.playbackGeneration;
    this.cancelPlayback();
    const previous = this.playbackOperation;
    const operation = this.playSequence(version, previous, word);
    this.playbackOperation = operation;
    return operation.finally(() => { if (this.playbackOperation === operation) { this.playbackOperation = undefined; } });
  }

  private async playSequence(version: number, previous: Promise<void> | undefined, word: string): Promise<void> {
    let message = '';
    try {
      if (previous) { await previous; }
      if (this.disposed || version !== this.playbackGeneration) { return; }
      AudioService.getInstance().stop();
      if (word.trim()) {
        this.publish('original');
        await AudioService.getInstance().speak(word, 'en-US');
      }
      if (this.disposed || version !== this.playbackGeneration) { return; }
      this.publish('playing');
      await this.playFile(version);
    } catch (_) { message = '暂时无法回放，请重试'; }
    finally { if (!this.disposed && version === this.playbackGeneration) { this.publish('ready', message); } }
  }

  private async playFile(version: number): Promise<void> {
    const player = await media.createAVPlayer();
    let file: fileIo.File | undefined = undefined;
    let timeout: number = -1;
    try {
      if (this.disposed || version !== this.playbackGeneration) { return; }
      this.player = player;
      file = fileIo.openSync(this.path, fileIo.OpenMode.READ_ONLY);
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const finish = (error?: Error): void => {
          if (settled) { return; }
          settled = true;
          if (error) { reject(error); } else { resolve(); }
        };
        this.finishPlayback = finish;
        player.on('error', (_error: BusinessError): void => { finish(new Error('回放失败')); });
        player.on('stateChange', (state: string): void => {
          if (settled || this.disposed || version !== this.playbackGeneration) { finish(); return; }
          if (state === 'initialized') {
            player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 };
            player.prepare().catch(() => { finish(new Error('回放准备失败')); });
          } else if (state === 'prepared') {
            player.play().catch(() => { finish(new Error('回放失败')); });
          } else if (state === 'completed') { finish(); }
        });
        timeout = setTimeout(() => { finish(new Error('回放超时')); }, 30000);
        player.fdSrc = { fd: file!.fd, offset: 0, length: fileIo.statSync(file!.fd).size };
      });
    } finally {
      if (timeout >= 0) { clearTimeout(timeout); }
      if (this.player === player) {
        if (this.playerStopOperation) { await this.playerStopOperation; }
        this.playerStopOperation = undefined;
        this.player = undefined;
        this.finishPlayback = undefined;
      }
      try { player.off('stateChange'); } catch (_) {}
      try { player.off('error'); } catch (_) {}
      try { await player.release(); } finally { if (file) { fileIo.closeSync(file); } }
    }
  }

  private cancelPlayback(): void {
    if (this.state === 'original') { AudioService.getInstance().stop(); }
    if (this.finishPlayback) { this.finishPlayback(); }
    const player = this.player;
    if (player && (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared')) {
      if (!this.playerStopOperation) { this.playerStopOperation = player.stop().catch(() => {}); }
    }
  }

  async stopPlayback(): Promise<void> {
    this.playbackGeneration++;
    this.cancelPlayback();
    if (this.playbackOperation) { await this.playbackOperation; }
    if (!this.disposed && (this.state === 'playing' || this.state === 'original')) {
      this.publish(this.path ? 'ready' : 'idle');
    }
  }

  /** Cancels pending creation, releases capturer/player/FD, and removes every owned recording. */
  async dispose(): Promise<void> {
    this.disposed = true;
    this.listener = undefined;
    const stopping = this.stop(false);
    const playback = this.stopPlayback();
    try { await stopping; await playback; }
    finally { this.deleteRecording(); this.chunks = []; this.byteLength = 0; }
  }
}
