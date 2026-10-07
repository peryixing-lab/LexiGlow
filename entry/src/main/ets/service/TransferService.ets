import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { DocxReader } from './DocxReader';
import { Word } from '../model/AppModels';

export class ImportedBook {
  name: string;
  words: Word[];
  constructor(name: string, words: Word[]) {
    this.name = name;
    this.words = words;
  }
}

class ImportDocument {
  name: string = '';
  words: Word[] = [];
}

/** Picker grants access only to the file selected by the user, with no storage permission. */
export class TransferService {
  private static readonly MAX_BYTES: number = 5 * 1024 * 1024;
  private static readonly MAX_WORDS: number = 5000;

  static async importFile(context: common.UIAbilityContext): Promise<ImportedBook> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['词书 JSON / CSV / TXT / DOCX|.json,.csv,.txt,.docx'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) {
      throw new Error('已取消选择文件');
    }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0 || stat.size > TransferService.MAX_BYTES) {
        throw new Error('请选择不超过 5 MB 的词书文件');
      }
      const bytes = new Uint8Array(stat.size);
      let offset = 0;
      while (offset < stat.size) {
        const chunk = new ArrayBuffer(stat.size - offset);
        const count = await fileIo.read(file.fd, chunk);
        if (count <= 0) {
          break;
        }
        bytes.set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      if (offset !== stat.size) {
        throw new Error('文件未能完整读取，请重新选择');
      }
      let name = '我的导入词书';
      let extension = '';
      try {
        const part = decodeURIComponent(uris[0].split('/').pop() || '');
        if (part.length > 0) {
          name = part.replace(/\.(json|csv|txt|docx)$/i, '').slice(0, 60);
          extension = part.split('.').pop()?.toLowerCase() || '';
        }
      } catch (_error) {}
      if (extension === 'docx' || (bytes[0] === 0x50 && bytes[1] === 0x4B)) {
        return await TransferService.parseDocx(bytes, name);
      }
      const content = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
      return TransferService.parse(content, name);
    } finally {
      await fileIo.close(file);
    }
  }

  static async exportFile(context: common.UIAbilityContext, data: string): Promise<string> {
    return TransferService.save(context, data,
      `词萤学习备份_${new Date().toISOString().slice(0, 10)}.json`, 'JSON 数据|.json');
  }

  static async exportBookFile(context: common.UIAbilityContext, name: string, words: Word[],
    format: string): Promise<string> {
    const content = TransferService.formatBook(name, words, format);
    const filename = (name.trim().replace(/[\\/:*?"<>|\u0000-\u001F]/g, '_').slice(0, 60) || '词萤词书') + `.${format}`;
    return TransferService.save(context, content, filename, `词书 ${format.toUpperCase()}|.${format}`);
  }

  static formatBook(name: string, words: Word[], format: string): string {
    if (format === 'json') {
      const book = new ImportDocument();
      book.name = name;
      book.words = words;
      return JSON.stringify(book, null, 2);
    }
    if (format === 'csv') {
      const rows = ['word,phonetic,meaning,example,translation'];
      words.forEach((word: Word) => {
        rows.push([word.word, word.phonetic, word.meaning, word.example, word.translation]
          .map((value: string) => `"${value.replace(/"/g, '""')}"`).join(','));
      });
      return '\uFEFF' + rows.join('\r\n');
    }
    if (format === 'txt') {
      const rows = ['word\tphonetic\tmeaning\texample\ttranslation'];
      words.forEach((word: Word) => {
        rows.push([word.word, word.phonetic, word.meaning, word.example, word.translation]
          .map((value: string) => value.replace(/[\t\r\n]+/g, ' ')).join('\t'));
      });
      return '\uFEFF' + rows.join('\r\n');
    }
    throw new Error('请选择 JSON、CSV 或 TXT 导出格式');
  }

  private static async save(context: common.UIAbilityContext, data: string, filename: string,
    filter: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [filename];
    options.fileSuffixChoices = [filter];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) {
      throw new Error('已取消保存文件');
    }
    const bytes = new util.TextEncoder().encodeInto(data);
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const buffer = bytes.slice(offset).buffer;
        const count = await fileIo.write(file.fd, buffer);
        if (count <= 0) {
          throw new Error('备份未能完整写入，请重试');
        }
        offset += count;
      }
    } finally {
      await fileIo.close(file);
    }
    return uris[0];
  }

  /** Used by the in-app paste fallback as well as the system document picker. */
  static parse(text: string, name: string = '我的导入词书'): ImportedBook {
    const content = text.replace(/^\uFEFF/, '').trim();
    if (content.length === 0 || content.length > TransferService.MAX_BYTES) {
      throw new Error('词书内容为空或超过 5 MB');
    }
    let words: Word[] = [];
    let bookName = name;
    let allowPendingMeaning = false;
    if (content.startsWith('[') || content.startsWith('{')) {
      try {
        if (content.startsWith('[')) {
          words = JSON.parse(content) as Word[];
        } else {
          const document = JSON.parse(content) as ImportDocument;
          words = document.words;
          if (typeof document.name === 'string' && document.name.trim().length > 0) {
            bookName = document.name.trim();
          }
        }
      } catch (_error) {
        throw new Error('JSON 格式有误，请使用单词数组或含 words 数组的词书');
      }
    } else if (TransferService.hasHeader(content, ',')) {
      words = TransferService.csvWords(content);
    } else if (TransferService.hasHeader(content, '\t')) {
      words = TransferService.textWords(content);
      allowPendingMeaning = true;
    } else {
      words = TransferService.textWords(content);
      allowPendingMeaning = true;
    }
    if (!Array.isArray(words) || words.length === 0 || words.length > TransferService.MAX_WORDS) {
      throw new Error('每次导入应包含 1 至 5000 个单词');
    }
    const normalized: Word[] = [];
    const seen = new Set<string>();
    words.forEach((item: Word, index: number) => {
      if (item === null || typeof item !== 'object') {
        throw new Error(`第 ${index + 1} 个单词格式有误`);
      }
      const word = new Word();
      word.word = TransferService.field(item.word, 'word', index, 80, true).toLowerCase();
      word.meaning = TransferService.field(item.meaning, 'meaning', index, 600, !allowPendingMeaning);
      word.phonetic = TransferService.field(item.phonetic, 'phonetic', index, 200, false);
      word.example = TransferService.field(item.example, 'example', index, 2000, false);
      word.translation = TransferService.field(item.translation, 'translation', index, 2000, false);
      if (!/^[a-z][a-z '\-]*[a-z]$|^[a-z]$/.test(word.word)) {
        throw new Error(`第 ${index + 1} 个 word 应为英语单词或短语`);
      }
      if (!seen.has(word.word)) {
        seen.add(word.word);
        normalized.push(word);
      }
    });
    return new ImportedBook(bookName.trim().slice(0, 60) || '我的导入词书', normalized);
  }

  private static field(value: string, key: string, index: number, limit: number, required: boolean): string {
    if (value === undefined || value === null) {
      if (required) {
        throw new Error(`第 ${index + 1} 个单词缺少 ${key}`);
      }
      return '';
    }
    if (typeof value !== 'string') {
      throw new Error(`第 ${index + 1} 个单词的 ${key} 应为文本`);
    }
    const text = value.trim();
    if ((required && text.length === 0) || text.length > limit || /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(text)) {
      throw new Error(`第 ${index + 1} 个单词的 ${key} 为空、过长或含无效字符`);
    }
    return text;
  }

  static async parseDocx(bytes: Uint8Array, name: string = '我的导入词书'): Promise<ImportedBook> {
    const text = await DocxReader.read(bytes);
    const candidates = text.split(/\r\n|\r|\n/).filter((value: string) => {
      const line = value.trim();
      if (!line) { return false; }
      if (TransferService.hasHeader(line, '\t')) { return true; }
      if (line.includes('\t')) { return /^[a-z][a-z '\-]*$/i.test(line.split('\t')[0].trim()); }
      if (/^[a-z][a-z'\-]*$/i.test(line)) { return true; }
      return /^([A-Za-z][A-Za-z '\-]*?)\s*[:：]\s*(.+)$/.test(line) ||
        /^([A-Za-z][A-Za-z '\-]*?)\s+(?=(?:(?:n|v|adj|adv|prep|pron|conj|det|aux|num|interj|a)\.\s*)?[\u3400-\u9FFF])(.+)$/.test(line);
    });
    if (candidates.length === 0) { throw new Error('DOCX 中没有找到单词列表，请用单词表格或每行一个单词'); }
    return TransferService.parse(candidates.join('\n'), name);
  }

  private static headerName(value: string): string {
    const name = value.trim().replace(/^"|"$/g, '').toLowerCase();
    if (['word', '单词', '英文', '英语', '词汇'].indexOf(name) >= 0) { return 'word'; }
    if (['meaning', '释义', '中文', '中文释义', '含义'].indexOf(name) >= 0) { return 'meaning'; }
    if (['phonetic', '音标'].indexOf(name) >= 0) { return 'phonetic'; }
    if (['example', '例句', '英文例句'].indexOf(name) >= 0) { return 'example'; }
    if (['translation', '译文', '例句翻译', '中文例句'].indexOf(name) >= 0) { return 'translation'; }
    return name;
  }

  private static hasHeader(content: string, delimiter: string): boolean {
    const firstLine = content.split(/\r\n|\r|\n/)[0];
    return firstLine.includes(delimiter) && firstLine.split(delimiter)
      .some((value: string) => TransferService.headerName(value) === 'word');
  }

  private static textWords(content: string): Word[] {
    const words: Word[] = [];
    const lines = content.split(/\r\n|\r|\n/);
    let header: string[] = [];
    lines.forEach((value: string, index: number) => {
      const line = value.trim();
      if (!line) { return; }
      if (TransferService.hasHeader(line, '\t')) {
        header = line.split('\t').map((field: string) => TransferService.headerName(field));
        if (header.indexOf('meaning') < 0 || new Set<string>(header).size !== header.length) {
          throw new Error(`第 ${index + 1} 行表头需要唯一的单词和释义列`);
        }
        return;
      }
      if (/^(单词|英文|word)[\t ]+(释义|中文|meaning)$/i.test(line)) { return; }
      const word = new Word();
      if (line.includes('\t')) {
        const fields = line.split('\t');
        if (fields.length > 5) { throw new Error(`第 ${index + 1} 行列数过多，最多 5 列`); }
        word.word = fields[0].trim();
        if (header.length > 0) {
          word.word = (fields[header.indexOf('word')] || '').trim();
          word.meaning = (fields[header.indexOf('meaning')] || '').trim();
          word.phonetic = (fields[header.indexOf('phonetic')] || '').trim();
          word.example = (fields[header.indexOf('example')] || '').trim();
          word.translation = (fields[header.indexOf('translation')] || '').trim();
        } else if (fields.length <= 2) {
          word.meaning = (fields[1] || '').trim();
        } else {
          word.phonetic = (fields[1] || '').trim();
          word.meaning = (fields[2] || '').trim();
          word.example = (fields[3] || '').trim();
          word.translation = (fields[4] || '').trim();
        }
      } else {
        // An English headword/phrase followed by a Chinese definition, including a part-of-speech prefix.
        const match = line.match(/^([A-Za-z][A-Za-z '\-]*?)\s*[:：]\s*(.+)$/) ||
          line.match(/^([A-Za-z][A-Za-z '\-]*?)\s+(?=(?:(?:n|v|adj|adv|prep|pron|conj|det|aux|num|interj|a)\.\s*)?[\u3400-\u9FFF])(.+)$/);
        if (match) {
          word.word = match[1].trim();
          word.meaning = match[2].trim();
        } else {
          if (line.includes(' ')) { throw new Error(`第 ${index + 1} 行需要单个英语词，短语请同时填写释义`); }
          word.word = line;
        }
      }
      words.push(word);
    });
    return words;
  }

  private static csvWords(content: string, delimiter: string = ','): Word[] {
    const rows = TransferService.csvRows(content, delimiter);
    if (rows.length < 2) {
      throw new Error('CSV 需要表头和单词行；必需列为 word, meaning');
    }
    const header = rows[0].map((cell: string) => TransferService.headerName(cell));
    const wordIndex = header.indexOf('word');
    const meaningIndex = header.indexOf('meaning');
    if (wordIndex < 0 || meaningIndex < 0 || new Set<string>(header).size !== header.length) {
      throw new Error('CSV 表头需要唯一的 word 和 meaning 列');
    }
    const phoneticIndex = header.indexOf('phonetic');
    const exampleIndex = header.indexOf('example');
    const translationIndex = header.indexOf('translation');
    const words: Word[] = [];
    for (let index = 1; index < rows.length; index++) {
      const row = rows[index];
      if (row.length > header.length) {
        throw new Error(`CSV 第 ${index + 1} 行列数超过表头；含逗号的内容请用双引号包住`);
      }
      const word = new Word();
      word.word = row[wordIndex] || '';
      word.meaning = row[meaningIndex] || '';
      word.phonetic = phoneticIndex >= 0 ? row[phoneticIndex] || '' : '';
      word.example = exampleIndex >= 0 ? row[exampleIndex] || '' : '';
      word.translation = translationIndex >= 0 ? row[translationIndex] || '' : '';
      words.push(word);
    }
    return words;
  }

  /** RFC 4180 style parsing, including escaped quotes and quoted line breaks. */
  private static csvRows(content: string, delimiter: string = ','): string[][] {
    const rows: string[][] = [];
    let row: string[] = [];
    let cell = '';
    let quoted = false;
    let closedQuote = false;
    for (let index = 0; index < content.length; index++) {
      const character = content[index];
      if (quoted) {
        if (character === '"') {
          if (content[index + 1] === '"') {
            cell += '"';
            index++;
          } else {
            quoted = false;
            closedQuote = true;
          }
        } else {
          cell += character;
        }
      } else if (character === '"') {
        if (cell.length > 0 || closedQuote) {
          throw new Error('CSV 引号位置不正确');
        }
        quoted = true;
      } else if (character === delimiter || character === '\n' || character === '\r') {
        row.push(cell);
        cell = '';
        closedQuote = false;
        if (character !== delimiter) {
          if (character === '\r' && content[index + 1] === '\n') {
            index++;
          }
          if (row.some((value: string) => value.trim().length > 0)) {
            rows.push(row);
          }
          row = [];
          if (rows.length > TransferService.MAX_WORDS + 1) {
            throw new Error('每次最多导入 5000 个单词');
          }
        }
      } else {
        if (closedQuote && character !== ' ' && character !== '\t') {
          throw new Error('CSV 结束引号后应为逗号或换行');
        }
        if (!closedQuote) {
          cell += character;
        }
      }
      if (cell.length > 2000 || row.length > 20) {
        throw new Error('CSV 字段过长或列数过多');
      }
    }
    if (quoted) {
      throw new Error('CSV 引号未闭合');
    }
    row.push(cell);
    if (row.some((value: string) => value.trim().length > 0)) {
      rows.push(row);
    }
    return rows;
  }
}
