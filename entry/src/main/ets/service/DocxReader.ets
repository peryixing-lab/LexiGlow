import { util, xml } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';

class DocumentEntry {
  name: string = '';
  offset: number = 0;
  compressedSize: number = 0;
  size: number = 0;
  crc: number = 0;
  method: number = 0;
  flags: number = 0;
}

/** Extracts only Word's main XML into a bounded buffer; no archive path is written to disk. */
export class DocxReader {
  private static readonly MAX_INPUT: number = 5 * 1024 * 1024;
  private static readonly MAX_XML: number = 4 * 1024 * 1024;

  static async read(bytes: Uint8Array): Promise<string> {
    if (bytes.length < 22 || bytes.length > DocxReader.MAX_INPUT) {
      throw new Error('DOCX 文件为空、损坏或超过 5 MB');
    }
    const entry = DocxReader.documentEntry(bytes);
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const offset = entry.offset;
    if (offset + 30 > bytes.length || view.getUint32(offset, true) !== 0x04034B50) {
      throw new Error('DOCX 压缩目录损坏');
    }
    const nameSize = view.getUint16(offset + 26, true);
    const extraSize = view.getUint16(offset + 28, true);
    const dataStart = offset + 30 + nameSize + extraSize;
    const localName = DocxReader.decode(bytes.slice(offset + 30, offset + 30 + nameSize));
    if (dataStart + entry.compressedSize > bytes.length || localName !== entry.name ||
      view.getUint16(offset + 6, true) !== entry.flags || view.getUint16(offset + 8, true) !== entry.method) {
      throw new Error('DOCX 压缩数据与目录不一致');
    }
    if ((entry.flags & 8) === 0 && (view.getUint32(offset + 18, true) !== entry.compressedSize ||
      view.getUint32(offset + 22, true) !== entry.size || view.getUint32(offset + 14, true) !== entry.crc)) {
      throw new Error('DOCX 正文校验失败');
    }
    const compressed = bytes.slice(dataStart, dataStart + entry.compressedSize);
    let document: Uint8Array;
    if (entry.method === 0) {
      if (entry.compressedSize !== entry.size) { throw new Error('DOCX 正文大小不正确'); }
      document = compressed;
    } else {
      const zip = await zlib.createZip();
      const output = new ArrayBuffer(entry.size + 1);
      const stream: zlib.ZStream = {
        nextIn: compressed.buffer,
        availableIn: compressed.length,
        nextOut: output,
        availableOut: output.byteLength
      };
      let initialized = false;
      try {
        if (await zip.inflateInit2(stream, -15) !== zlib.ReturnStatus.OK) {
          throw new Error('DOCX 解压初始化失败');
        }
        initialized = true;
        const status = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
        const result = await zip.getZStream();
        if (status !== zlib.ReturnStatus.STREAM_END || result.totalOut !== entry.size ||
          result.totalIn !== entry.compressedSize) {
          throw new Error('DOCX 正文超过限制或压缩数据损坏');
        }
        document = new Uint8Array(output, 0, entry.size);
      } catch (_error) {
        throw new Error('DOCX 正文无法解压，文件可能损坏或超过大小限制');
      } finally {
        if (initialized) {
          try { await zip.inflateEnd({}); } catch (_error) {}
        }
      }
    }
    const checksum = await zlib.createChecksum();
    const actualCrc = await checksum.crc32(0, document.slice().buffer);
    if ((actualCrc >>> 0) !== entry.crc) { throw new Error('DOCX 正文校验失败，请重新保存文件'); }
    return DocxReader.documentText(document);
  }

  private static decode(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
  }

  private static documentEntry(bytes: Uint8Array): DocumentEntry {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let end = -1;
    for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65557); offset--) {
      if (view.getUint32(offset, true) === 0x06054B50 &&
        offset + 22 + view.getUint16(offset + 20, true) === bytes.length) {
        end = offset;
        break;
      }
    }
    if (end < 0 || view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0) {
      throw new Error('DOCX 不是有效的单卷 Word 文档');
    }
    const count = view.getUint16(end + 10, true);
    const centralSize = view.getUint32(end + 12, true);
    const centralStart = view.getUint32(end + 16, true);
    if (count < 1 || count > 2000 || count !== view.getUint16(end + 8, true) ||
      centralStart + centralSize !== end) {
      throw new Error('DOCX 压缩目录过大或格式不支持');
    }
    let offset = centralStart;
    let totalSize = 0;
    let document: DocumentEntry | undefined;
    const names = new Set<string>();
    for (let index = 0; index < count; index++) {
      if (offset + 46 > end || view.getUint32(offset, true) !== 0x02014B50) {
        throw new Error('DOCX 压缩目录损坏');
      }
      const flags = view.getUint16(offset + 8, true);
      const method = view.getUint16(offset + 10, true);
      const compressedSize = view.getUint32(offset + 20, true);
      const size = view.getUint32(offset + 24, true);
      const nameSize = view.getUint16(offset + 28, true);
      const extraSize = view.getUint16(offset + 30, true);
      const commentSize = view.getUint16(offset + 32, true);
      const entryEnd = offset + 46 + nameSize + extraSize + commentSize;
      if (nameSize < 1 || nameSize > 1024 || entryEnd > end || (flags & 1) !== 0 ||
        (method !== 0 && method !== 8) || size === 0xFFFFFFFF || compressedSize === 0xFFFFFFFF ||
        view.getUint16(offset + 34, true) !== 0) {
        throw new Error('DOCX 使用了不支持的加密或压缩格式');
      }
      const name = DocxReader.decode(bytes.slice(offset + 46, offset + 46 + nameSize));
      if (name.startsWith('/') || /[\\:\u0000-\u001F]/.test(name) ||
        name.split('/').some((part: string) => part === '..' || part === '.') || names.has(name) ||
        ((view.getUint32(offset + 38, true) >>> 16) & 0xF000) === 0xA000) {
        throw new Error('DOCX 含不安全的压缩路径');
      }
      names.add(name);
      totalSize += size;
      if (totalSize > 20 * 1024 * 1024) { throw new Error('DOCX 解压内容超过 20 MB'); }
      if (name === 'word/document.xml') {
        if (size < 1 || size > DocxReader.MAX_XML || compressedSize > DocxReader.MAX_INPUT) {
          throw new Error('DOCX 正文超过 4 MB');
        }
        document = new DocumentEntry();
        document.name = name;
        document.offset = view.getUint32(offset + 42, true);
        document.compressedSize = compressedSize;
        document.size = size;
        document.method = method;
        document.flags = flags;
        document.crc = view.getUint32(offset + 16, true);
        if (document.offset + 30 + nameSize + compressedSize > centralStart) {
          throw new Error('DOCX 正文位置不正确');
        }
      }
      offset = entryEnd;
    }
    if (offset !== end || !document || !names.has('[Content_Types].xml')) {
      throw new Error('DOCX 缺少 Word 正文，请使用 .docx 格式');
    }
    return document;
  }

  private static documentText(document: Uint8Array): string {
    const source = DocxReader.decode(document);
    if (/<!\s*(DOCTYPE|ENTITY)\b/i.test(source)) {
      throw new Error('DOCX 正文不允许 DTD 或外部实体');
    }
    const output: string[] = [];
    let paragraph = '';
    let cell = '';
    let row: string[] = [];
    let inCell = false;
    let inText = false;
    let isDocument = false;
    let limitReached = false;
    const xmlBuffer = new ArrayBuffer(document.byteLength);
    new Uint8Array(xmlBuffer).set(document);
    const parser = new xml.XmlPullParser(xmlBuffer, 'utf-8');
    const options: xml.ParseOptions = {
      supportDoctype: false,
      ignoreNameSpace: false,
      tokenValueCallbackFunction: (event: xml.EventType, value: xml.ParseInfo): boolean => {
        if (value.getDepth() > 100 || output.length > 10000) {
          limitReached = true;
          return false;
        }
        const name = value.getName().split(':').pop() || '';
        const namespace = value.getNamespace();
        const isWordTag = namespace === 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' ||
          namespace === 'http://purl.oclc.org/ooxml/wordprocessingml/main';
        if (event === xml.EventType.START_TAG && isWordTag) {
          if (name === 'document') { isDocument = true; }
          if (name === 'tr') { row = []; }
          if (name === 'tc') { inCell = true; cell = ''; }
          if (name === 'p') { paragraph = ''; }
          if (name === 't') { inText = true; }
          if (name === 'tab') { paragraph += '\t'; }
          if (name === 'br' || name === 'cr') { paragraph += '\n'; }
        } else if (event === xml.EventType.END_TAG && isWordTag) {
          if (name === 't') { inText = false; }
          if (name === 'p') {
            if (inCell) { cell += (cell ? ' ' : '') + paragraph; }
            else if (paragraph.trim()) { output.push(paragraph); }
            paragraph = '';
          }
          if (name === 'tc') { row.push(cell.trim()); inCell = false; cell = ''; }
          if (name === 'tr' && row.length > 0) { output.push(row.join('\t')); row = []; }
        } else if (inText && (event === xml.EventType.TEXT || event === xml.EventType.CDSECT ||
          event === xml.EventType.ENTITY_REFERENCE)) {
          paragraph += value.getText();
        }
        return true;
      }
    };
    try { parser.parseXml(options); }
    catch (_error) { throw new Error('DOCX 正文 XML 格式有误'); }
    if (limitReached || !isDocument) { throw new Error('DOCX 正文层级过深或格式不支持'); }
    return output.join('\n');
  }
}
