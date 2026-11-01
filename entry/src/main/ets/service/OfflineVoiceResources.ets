import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

/** Upgrade cleanup for the retired bundled voice. System voice data belongs to Huawei. */
export class OfflineVoiceResources {
  static async removeRetiredCaches(context: common.Context): Promise<void> {
    let names: string[];
    try { names = await fileIo.listFile(context.cacheDir, { recursion: false }); }
    catch (_error) { return; }
    for (const name of names) {
      if (!/^offline-speech-melo-en-[a-zA-Z0-9_-]+$/.test(name)) { continue; }
      const folder = `${context.cacheDir}/${name}`;
      try { if (!(await fileIo.stat(folder)).isDirectory()) { continue; } }
      catch (_error) { continue; }
      // Explicit allowlist preserves unrelated files, dictionaries and learning data.
      for (const filename of ['model.onnx', 'tokens.txt', 'lexicon.txt',
        'model.onnx.preparing', 'tokens.txt.preparing', 'lexicon.txt.preparing']) {
        try { await fileIo.unlink(`${folder}/${filename}`); } catch (_error) {}
      }
    }
  }
}
