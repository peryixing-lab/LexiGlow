import { UIContext } from '@kit.ArkUI';
import { AudioService } from './AudioService';

/** Playback results never update an obsolete word after navigation or backgrounding. */
export class PronunciationPresenter {
  private requestVersion: number = 0;
  private pendingUpdate?: (state: string, message: string) => void;

  cancel(): void {
    this.requestVersion++;
    const update = this.pendingUpdate;
    this.pendingUpdate = undefined;
    if (update) { update('idle', ''); }
  }

  async play(text: string, ui: UIContext, isCurrent: () => boolean,
    update: (state: string, message: string) => void): Promise<void> {
    if (!isCurrent()) { return; }
    const version = ++this.requestVersion;
    const current = (): boolean => version === this.requestVersion && isCurrent();
    this.pendingUpdate = update;
    update('preparing', '正在准备单词朗读…');
    try {
      await AudioService.getInstance().speak(text);
      if (current()) { update('ready', ''); }
    } catch (error) {
      if (!current()) { return; }
      const message = (error as Error).message || '单词朗读失败，请稍后点击发音按钮重试。';
      update('error', message);
      ui.getPromptAction().showToast({ message: message, duration: 3000 });
    } finally {
      if (version === this.requestVersion) { this.pendingUpdate = undefined; }
    }
  }
}
