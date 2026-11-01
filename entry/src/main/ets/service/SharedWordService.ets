import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';

/** Receives selected/shared text. Saving words remains an explicit action in the UI. */
export class SharedWordService {
  private static requestRevision: number = 0;

  static wordsFromText(text: string): string[] {
    const matches = text.slice(0, 4096).match(/[A-Za-z]+(?:['’-][A-Za-z]+)*/g) || [];
    const words: string[] = [];
    for (const match of matches) {
      const word = match.toLowerCase().replace(/’/g, "'");
      if (word.length <= 64 && words.indexOf(word) < 0) {
        words.push(word);
      }
      if (words.length >= 20) { break; }
    }
    return words;
  }

  private static publish(text: string): boolean {
    const bounded = text.trim().slice(0, 4096);
    if (SharedWordService.wordsFromText(bounded).length === 0) { return false; }
    AppStorage.setOrCreate('lexiglowSharedText', bounded);
    const revision = AppStorage.get<number>('lexiglowSharedRevision') || 0;
    AppStorage.setOrCreate('lexiglowSharedRevision', revision + 1);
    return true;
  }

  static async textFromWant(want: Want): Promise<string> {
    const selected = want.parameters?.lexiglowSharedText;
    if (typeof selected === 'string') { return selected.trim().slice(0, 4096); }
    if (want.action !== 'ohos.want.action.sendData') { return ''; }
    const shared = await systemShare.getSharedData(want);
    const contents: string[] = [];
    for (const record of shared.getRecords()) {
      if ((record.utd === 'general.plain-text' || record.utd === 'general.text') && record.content) {
        contents.push(record.content);
      }
    }
    return contents.join('\n').trim().slice(0, 4096);
  }

  static async captureWant(want: Want): Promise<boolean> {
    const request = ++SharedWordService.requestRevision;
    // Private parameter supplied by the PC/2in1 selection extension; never a write command.
    const selected = want.parameters?.lexiglowSharedText;
    if (typeof selected === 'string') {
      return SharedWordService.publish(selected);
    }
    if (want.action !== 'ohos.want.action.sendData') { return false; }
    try {
      const text = await SharedWordService.textFromWant(want);
      if (request !== SharedWordService.requestRevision) { return false; }
      return SharedWordService.publish(text);
    } catch (_) {
      // A malformed/non-ShareKit Want must not cause a database write or read the clipboard.
      return false;
    }
  }
}
