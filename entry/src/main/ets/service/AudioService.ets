import { textToSpeech } from '@kit.CoreSpeechKit';

/** Uses the device's English voice model; pronunciation never requires a network request. */
export class AudioService {
  private static instance: AudioService = new AudioService();
  private engine?: textToSpeech.TextToSpeechEngine;
  private loading?: Promise<textToSpeech.TextToSpeechEngine>;
  private generation: number = 0;
  private sequence: number = 0;
  private requestId: string = '';
  private resolvePlayback?: () => void;
  private rejectPlayback?: (error: Error) => void;
  private timer: number = -1;
  private listener: textToSpeech.SpeakListener = {
    onStart: (_id: string, _response: textToSpeech.StartResponse): void => {},
    onComplete: (id: string, response: textToSpeech.CompleteResponse): void => {
      if (id === this.requestId && response.type === 1) {
        this.finish();
      }
    },
    onStop: (id: string, _response: textToSpeech.StopResponse): void => {
      if (id === this.requestId) {
        this.finish();
      }
    },
    onError: (id: string, _code: number, _message: string): void => {
      if (id === this.requestId) {
        this.finish(new Error('暂时无法发音，请检查设备是否已安装英语语音包'));
      }
    }
  };

  static getInstance(): AudioService {
    return AudioService.instance;
  }

  private async prepare(): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.engine) {
      return this.engine;
    }
    if (this.loading) {
      return this.loading;
    }
    const currentGeneration = this.generation;
    const params: textToSpeech.CreateEngineParams = { language: 'en-US', person: 8, online: 1 };
    this.loading = textToSpeech.createEngine(params);
    try {
      const engine = await this.loading;
      if (currentGeneration !== this.generation) {
        engine.shutdown();
        throw new Error('发音已取消');
      }
      engine.setListener(this.listener);
      this.engine = engine;
      return engine;
    } catch (_error) {
      throw new Error('暂时无法发音，请先在设备语音设置中安装英语语音包');
    } finally {
      this.loading = undefined;
    }
  }

  async speak(text: string): Promise<void> {
    const value = text.trim();
    if (value.length === 0 || value.length > 500) {
      throw new Error('发音内容为空或过长');
    }
    const currentGeneration = this.generation;
    const engine = await this.prepare();
    if (currentGeneration !== this.generation) {
      return;
    }
    this.stopPlayback();
    this.requestId = `LexiGlow${Date.now()}${++this.sequence}`;
    return new Promise<void>((resolve, reject) => {
      this.resolvePlayback = resolve;
      this.rejectPlayback = reject;
      this.timer = setTimeout(() => {
        this.finish(new Error('发音未能完成，请检查英语语音包'));
        engine.stop();
      }, 30000);
      try {
        const params: textToSpeech.SpeakParams = { requestId: this.requestId };
        engine.speak(value, params);
      } catch (_error) {
        this.finish(new Error('暂时无法发音，请检查英语语音包'));
      }
    });
  }

  private finish(error?: Error): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    const resolve = this.resolvePlayback;
    const reject = this.rejectPlayback;
    this.resolvePlayback = undefined;
    this.rejectPlayback = undefined;
    this.requestId = '';
    if (error && reject) {
      reject(error);
    } else if (resolve) {
      resolve();
    }
  }

  private stopPlayback(): void {
    this.finish();
    if (this.engine) {
      try {
        this.engine.stop();
      } catch (_error) {}
    }
  }

  stop(): void {
    this.generation++;
    this.stopPlayback();
  }

  release(): void {
    this.stop();
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (_error) {}
      this.engine = undefined;
    }
  }
}
