import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { audio } from '@kit.AudioKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Word } from '../model/AppModels';
import { AudioService } from './AudioService';
import { audioCoreMeaning, audioEnglishExample, audioFlowQueue, copyAudioWord } from '../utils/AudioFlowUtils';

export class AudioFlowState {
  status: string = 'idle';
  stage: string = 'word';
  index: number = 0;
  total: number = 0;
  word: Word = new Word();
  error: string = '';
}

type AudioFlowListener = (state: AudioFlowState) => void;

/** A listening queue is independent from review judgments and never changes learning progress. */
export class AudioFlowService {
  private static instance: AudioFlowService = new AudioFlowService();
  private state: AudioFlowState = new AudioFlowState();
  private words: Word[] = [];
  private context?: common.UIAbilityContext;
  private listeners: AudioFlowListener[] = [];
  private session?: avSession.AVSession;
  private launchAgent?: WantAgent;
  private audioSession?: audio.AudioSessionManager;
  private backgroundRunning: boolean = false;
  private callbacksRegistered: boolean = false;
  private generation: number = 0;
  private lifecycle: Promise<void> = Promise.resolve();
  private recallTimer: number = -1;
  private recallRemaining: number = 2000;
  private recallStarted: number = 0;
  private resolveRecall?: () => void;
  private readonly speech: AudioService = AudioService.getInstance();
  private readonly onFocusLost = (_event: audio.AudioSessionDeactivatedEvent): void => {
    if (this.state.status === 'playing' || this.state.status === 'preparing') {
      this.pauseWithMessage('收听被其他音频打断，点击继续后从当前片段重播。');
    }
  };
  private readonly onFocusChanged = (event: audio.AudioSessionStateChangedEvent): void => {
    const hint = event.stateChangeHint;
    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP) {
      this.onFocusLost({ reason: audio.AudioSessionDeactivatedReason.DEACTIVATED_LOWER_PRIORITY });
    }
    // Resume requires an explicit user action, so a phone call cannot restart unexpected speech.
  };
  private readonly onOutputChanged = (event: audio.CurrentOutputDeviceChangedEvent): void => {
    if (event.recommendedAction === audio.OutputDeviceChangeRecommendedAction.DEVICE_CHANGE_RECOMMEND_TO_STOP) {
      this.pauseWithMessage('音频输出设备已断开，点击继续收听。');
    }
  };
  private readonly onBackgroundCancelled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (this.backgroundRunning) {
      this.backgroundRunning = false;
      this.pauseWithMessage(`后台播放已被系统结束（${info.reason}），回到应用后可继续。`);
    }
  };

  static getInstance(): AudioFlowService { return AudioFlowService.instance; }

  getState(): AudioFlowState {
    const value = new AudioFlowState();
    value.status = this.state.status;
    value.stage = this.state.stage;
    value.index = this.state.index;
    value.total = this.state.total;
    value.word = copyAudioWord(this.state.word);
    value.error = this.state.error;
    return value;
  }

  isActive(): boolean {
    return this.state.status === 'preparing' || this.state.status === 'playing' || this.state.status === 'paused';
  }

  subscribe(listener: AudioFlowListener): () => void {
    this.listeners.push(listener);
    listener(this.getState());
    return () => { this.listeners = this.listeners.filter((item: AudioFlowListener) => item !== listener); };
  }

  private notify(): void {
    for (const listener of this.listeners) { listener(this.getState()); }
  }

  /** Serialize native resource mutations so rapid controls cannot leak or destroy a newer session. */
  private mutate(operation: () => Promise<void>): Promise<void> {
    const next = this.lifecycle.then(operation);
    this.lifecycle = next.catch((error: Error) => {
      hilog.warn(0x0000, 'CiyingAudioFlow', 'Native audio operation failed: %{public}s', error.message);
    });
    return next;
  }

  async start(words: Word[], context: common.UIAbilityContext): Promise<void> {
    this.cancelPlayback();
    const version = this.generation;
    const queue = audioFlowQueue(words);
    this.words = queue;
    this.context = context;
    this.state = new AudioFlowState();
    this.state.total = queue.length;
    this.recallRemaining = 2000;
    if (queue.length === 0) {
      this.state.error = '当前没有可收听的单词，请先选择有中文释义的词书。';
      this.notify();
      await this.mutate(() => this.disposeNative());
      return;
    }
    this.state.word = copyAudioWord(queue[0]);
    this.state.status = 'preparing';
    this.notify();
    try {
      await this.mutate(async () => {
        await this.disposeNative();
        if (version !== this.generation) { return; }
        await this.speech.prepareFlow();
        if (version !== this.generation) { return; }
        await this.prepareNative(context);
        if (version !== this.generation) { return; }
        await this.activateFocus();
      });
      if (version !== this.generation) { return; }
      this.speech.setForegroundInterruption(() => { this.pause(); });
      this.state.status = 'playing';
      this.notify();
      this.runQueue(version);
    } catch (error) {
      if (version === this.generation) { await this.fail(error as Error); }
    }
  }

  pause(): void { this.pauseWithMessage(''); }

  private pauseWithMessage(message: string): void {
    if (this.state.status !== 'playing' && this.state.status !== 'preparing') { return; }
    this.cancelPlayback();
    this.state.status = 'paused';
    this.state.error = message;
    this.notify();
    this.mutate(async () => {
      await this.setPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
      await this.endBackground();
    }).catch((_error: Error) => {});
  }

  async resume(): Promise<void> {
    if (this.state.status === 'playing' || this.state.status === 'preparing' || !this.context || this.words.length === 0) {
      return;
    }
    if (this.state.status === 'completed' || this.state.status === 'idle') {
      await this.start(this.words, this.context);
      return;
    }
    const version = ++this.generation;
    this.state.status = 'preparing';
    this.state.error = '';
    this.notify();
    try {
      await this.mutate(async () => {
        if (version !== this.generation || !this.context) { return; }
        await this.speech.prepareFlow();
        if (version !== this.generation) { return; }
        if (!this.session) { await this.prepareNative(this.context); }
        if (version !== this.generation) { return; }
        await this.activateFocus();
      });
      if (version !== this.generation) { return; }
      this.speech.setForegroundInterruption(() => { this.pause(); });
      this.state.status = 'playing';
      this.notify();
      this.runQueue(version);
    } catch (error) {
      if (version === this.generation) { await this.fail(error as Error); }
    }
  }

  async previous(): Promise<void> { await this.moveTo(Math.max(0, this.state.index - 1)); }

  async next(): Promise<void> {
    if (this.state.index + 1 >= this.words.length) {
      await this.complete();
      return;
    }
    await this.moveTo(this.state.index + 1);
  }

  private async moveTo(index: number): Promise<void> {
    if (this.words.length === 0 || index >= this.words.length) { return; }
    const keepPaused = this.state.status === 'paused';
    this.cancelPlayback();
    this.state.index = index;
    this.state.word = copyAudioWord(this.words[index]);
    this.state.stage = 'word';
    this.state.error = '';
    this.recallRemaining = 2000;
    this.state.status = 'paused';
    this.notify();
    if (keepPaused) {
      await this.mutate(async () => { await this.setMetadata(); });
    } else { await this.resume(); }
  }

  async stop(): Promise<void> {
    this.cancelPlayback();
    this.state.status = 'idle';
    this.state.stage = 'word';
    this.state.error = '';
    this.recallRemaining = 2000;
    this.speech.setForegroundInterruption(undefined);
    this.notify();
    await this.mutate(() => this.disposeNative());
  }

  async release(): Promise<void> {
    await this.stop();
    this.context = undefined;
    this.words = [];
    this.listeners = [];
    this.state = new AudioFlowState();
  }

  private cancelPlayback(): void {
    this.generation++;
    if (this.recallTimer !== -1) {
      this.recallRemaining = Math.max(0, this.recallRemaining - (Date.now() - this.recallStarted));
      clearTimeout(this.recallTimer);
      this.recallTimer = -1;
      const resolve = this.resolveRecall;
      this.resolveRecall = undefined;
      if (resolve) { resolve(); }
    }
    this.speech.stop();
  }

  private waitForRecall(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.resolveRecall = resolve;
      this.recallStarted = Date.now();
      this.recallTimer = setTimeout(() => {
        this.recallTimer = -1;
        this.recallRemaining = 0;
        this.resolveRecall = undefined;
        resolve();
      }, this.recallRemaining);
    });
  }

  private async runQueue(version: number): Promise<void> {
    try {
      await this.setPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      while (version === this.generation && this.state.status === 'playing') {
        const word = this.words[this.state.index];
        if (!word) { await this.complete(); return; }
        if (this.state.stage === 'word') {
          await this.setMetadata();
          if (version !== this.generation) { return; }
          await this.speech.speak(word.word, 'en-US', true, () => { this.onSpeechStarted(version); });
          if (version !== this.generation) { return; }
          this.state.stage = 'recall';
          this.recallRemaining = 2000;
          this.notify();
        }
        if (this.state.stage === 'recall') {
          await this.waitForRecall();
          if (version !== this.generation) { return; }
          this.state.stage = 'meaning';
          this.notify();
        }
        if (this.state.stage === 'meaning') {
          await this.speech.speak(audioCoreMeaning(word.meaning), 'zh-CN', true, () => { this.onSpeechStarted(version); });
          if (version !== this.generation) { return; }
          this.state.stage = 'example';
          this.notify();
        }
        if (this.state.stage === 'example') {
          const example = audioEnglishExample(word.example);
          if (example) { await this.speech.speak(example, 'en-US', true, () => { this.onSpeechStarted(version); }); }
          if (version !== this.generation) { return; }
          if (this.state.index + 1 >= this.words.length) { await this.complete(); return; }
          this.state.index++;
          this.state.word = copyAudioWord(this.words[this.state.index]);
          this.state.stage = 'word';
          this.notify();
        }
      }
    } catch (error) {
      if (version === this.generation) { await this.fail(error as Error); }
    }
  }

  private async complete(): Promise<void> {
    this.cancelPlayback();
    this.state.status = this.words.length > 0 ? 'completed' : 'idle';
    this.state.error = '';
    this.speech.setForegroundInterruption(undefined);
    this.notify();
    await this.mutate(() => this.disposeNative());
  }

  private async fail(error: Error): Promise<void> {
    this.cancelPlayback();
    this.state.status = 'error';
    this.state.error = error.message || '离线收听暂时不可用，请检查设备语音包后重试。';
    this.speech.setForegroundInterruption(undefined);
    this.notify();
    await this.mutate(() => this.disposeNative());
  }

  private async prepareNative(context: common.UIAbilityContext): Promise<void> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
        moduleName: context.abilityInfo.moduleName, parameters: { route: 'audioFlow' } }],
      actionType: wantAgent.OperationType.START_ABILITY, requestCode: 6201,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    this.launchAgent = await wantAgent.getWantAgent(info);
    this.session = await avSession.createAVSession(context, '词萤听词', 'audio');
    const session = this.session;
    session.on('play', () => { this.resume().catch((error: Error) => { this.fail(error); }); });
    session.on('pause', () => { this.pause(); });
    session.on('stop', () => { this.stop().catch((error: Error) => { this.fail(error); }); });
    session.on('playNext', () => { this.next().catch((error: Error) => { this.fail(error); }); });
    session.on('playPrevious', () => { this.previous().catch((error: Error) => { this.fail(error); }); });
    await session.setLaunchAbility(this.launchAgent);
    await this.setMetadata();
    await this.setPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
    await session.activate();
    this.audioSession = audio.getAudioManager().getSessionManager();
    this.audioSession.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
    this.audioSession.on('audioSessionDeactivated', this.onFocusLost);
    this.audioSession.on('audioSessionStateChanged', this.onFocusChanged);
    this.audioSession.on('currentOutputDeviceChanged', this.onOutputChanged);
    backgroundTaskManager.on('continuousTaskCancel', this.onBackgroundCancelled);
    this.callbacksRegistered = true;
  }

  private async activateFocus(): Promise<void> {
    if (!this.audioSession) { throw new Error('音频会话尚未准备好'); }
    await this.audioSession.activateAudioSession({ concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT });
  }

  private onSpeechStarted(version: number): void {
    this.mutate(async () => {
      if (version !== this.generation || this.state.status !== 'playing') { return; }
      await this.beginBackground();
      if (version !== this.generation || this.state.status !== 'playing') { await this.endBackground(); }
    }).catch((error: Error) => {
      if (version === this.generation) { this.fail(error); }
    });
  }

  private async beginBackground(): Promise<void> {
    if (!this.audioSession || !this.context || !this.launchAgent) { throw new Error('后台播放尚未准备好'); }
    try {
      if (!this.backgroundRunning) {
        await backgroundTaskManager.startBackgroundRunning(this.context,
          backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, this.launchAgent);
        this.backgroundRunning = true;
      }
    } catch (error) {
      throw new Error(`无法启用后台收听，请重试（${(error as Error).message || '后台任务未获准'}）`);
    }
  }

  private async endBackground(): Promise<void> {
    if (this.backgroundRunning && this.context) {
      this.backgroundRunning = false;
      try { await backgroundTaskManager.stopBackgroundRunning(this.context); }
      catch (error) {
        hilog.warn(0x0000, 'CiyingAudioFlow', 'Stop background failed: %{public}s', (error as Error).message);
      }
    }
    if (this.audioSession?.isAudioSessionActivated()) {
      try { await this.audioSession.deactivateAudioSession(); } catch (_error) {}
    }
  }

  private async setMetadata(): Promise<void> {
    if (!this.session) { return; }
    const index = this.state.index;
    const word = this.words[index];
    if (!word) { return; }
    const metadata: avSession.AVMetadata = {
      assetId: `LexiGlowWord${word.id}Index${index}`, title: word.word,
      subtitle: audioCoreMeaning(word.meaning), artist: '词萤 · 离线听词', album: 'Audio Flow',
      avQueueName: `听词队列 · ${this.words.length} 词`,
      previousAssetId: index > 0 ? `LexiGlowWord${this.words[index - 1].id}Index${index - 1}` : '',
      nextAssetId: index + 1 < this.words.length ? `LexiGlowWord${this.words[index + 1].id}Index${index + 1}` : ''
    };
    await this.session.setAVMetadata(metadata);
  }

  private async setPlaybackState(state: avSession.PlaybackState): Promise<void> {
    if (!this.session) { return; }
    // TTS has no reliable duration/seek position; publish real state and active item only.
    await this.session.setAVPlaybackState({ state: state, speed: 1, activeItemId: this.state.index });
  }

  private async disposeNative(): Promise<void> {
    await this.endBackground();
    if (this.callbacksRegistered) {
      try { this.audioSession?.off('audioSessionDeactivated', this.onFocusLost); } catch (_error) {}
      try { this.audioSession?.off('audioSessionStateChanged', this.onFocusChanged); } catch (_error) {}
      try { this.audioSession?.off('currentOutputDeviceChanged', this.onOutputChanged); } catch (_error) {}
      try { backgroundTaskManager.off('continuousTaskCancel', this.onBackgroundCancelled); } catch (_error) {}
      this.callbacksRegistered = false;
    }
    const session = this.session;
    this.session = undefined;
    this.audioSession = undefined;
    this.launchAgent = undefined;
    if (session) {
      try { await session.deactivate(); } catch (_error) {}
      try { await session.destroy(); } catch (_error) {}
    }
  }
}
