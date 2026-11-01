import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ArticleImport } from '../model/ArticleModels';
import { normalizeArticleBody } from '../utils/ArticleTokenizer';
import { DocxReader } from './DocxReader';

export class ArticleImportService {
  /** Picker cancellation returns no draft and never writes article data. */
  static async importFile(context: common.UIAbilityContext): Promise<ArticleImport | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['文章 TXT / DOCX|.txt,.docx'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) { return undefined; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0 || stat.size > 5 * 1024 * 1024) { throw new Error('请选择不超过 5 MB 的 TXT 或 DOCX 文章'); }
      const bytes = new Uint8Array(stat.size);
      let offset = 0;
      while (offset < bytes.length) {
        const chunk = new ArrayBuffer(Math.min(65536, bytes.length - offset));
        const count = await fileIo.read(file.fd, chunk);
        if (count <= 0) { throw new Error('文章未能完整读取，请重新选择'); }
        bytes.set(new Uint8Array(chunk, 0, count), offset); offset += count;
      }
      let filename = '';
      try { filename = decodeURIComponent(uris[0].split('/').pop() || ''); } catch (_) {}
      const isDocx = /\.docx$/i.test(filename) || (bytes[0] === 0x50 && bytes[1] === 0x4B);
      if (!isDocx && filename && !/\.txt$/i.test(filename)) { throw new Error('请选择 TXT 或 DOCX 文章'); }
      let body: string;
      if (isDocx) {
        body = await DocxReader.read(bytes);
      } else {
        try { body = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes); }
        catch (_) { throw new Error('TXT 编码无法读取，请保存为 UTF-8 后再导入'); }
      }
      const draft = new ArticleImport();
      draft.title = filename.replace(/\.(txt|docx)$/i, '').slice(0, 80) || '我的文章';
      draft.body = normalizeArticleBody(body);
      return draft;
    } finally { await fileIo.close(file); }
  }
}
