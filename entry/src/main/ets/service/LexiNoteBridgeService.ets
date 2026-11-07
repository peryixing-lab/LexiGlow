import { common, Want } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { ConfusingWord, MistakeWord, Word, WordEnrichment, WordProgress, WordRelation } from '../model/AppModels';
import { ArticleImport } from '../model/ArticleModels';
import { SentenceMemory } from '../model/ExperienceModels';
import { normalizeArticleBody } from '../utils/ArticleTokenizer';
import { dateKey } from '../utils/TimeUtils';
import { SharedWordService } from './SharedWordService';

/**
 * Bidirectional bridge between LexiGlow (词萤) and LexiNote (知萤):
 * 1. Exports words, collected sentences, and mistake books as YAML-Frontmatter + WikiLink Markdown notes for LexiNote.
 * 2. Converts incoming Markdown notes from LexiNote into clean prose articles for LexiGlow companion reading.
 */
export class LexiNoteBridgeService {
  static sanitizeFileName(rawTitle: string, fallback: string = '词萤学习笔记'): string {
    const cleaned = (rawTitle || '')
      .replace(/\.(md|markdown|txt)$/i, '')
      .replace(/[/\\:*?"<>|\r\n\u0000-\u001f]+/g, '_')
      .replace(/^[.\s_]+|[.\s_]+$/g, '')
      .slice(0, 80);
    return `${cleaned || fallback}.md`;
  }

  static resolveMarkdownUtd(): string {
    try {
      const resolved = utd.getUniformDataTypeByFilenameExtension('.md');
      if (resolved && resolved.trim().length > 0) {
        return resolved;
      }
    } catch (_) {}
    return 'general.markdown';
  }

  private static yamlString(value: string): string {
    return JSON.stringify((value || '').replace(/[\r\n\u0000-\u001f]+/g, ' ').trim());
  }

  private static focusWordFromSentence(sentence: string, explicitSpelling: string = ''): string {
    const cleanExplicit = explicitSpelling.trim().toLowerCase().replace(/’/g, "'");
    if (cleanExplicit) {
      return cleanExplicit;
    }
    const matches = (sentence || '').match(/[A-Za-z]+(?:['’-][A-Za-z]+)*/g) || [];
    let best = '';
    for (const token of matches) {
      const candidate = token.toLowerCase().replace(/’/g, "'");
      if (candidate.length > best.length && candidate.length <= 40) {
        best = candidate;
      }
    }
    return best;
  }

  private static highlightWikiLinkInSentence(sentence: string, focusWord: string): string {
    const cleanSentence = (sentence || '').trim();
    if (!focusWord) {
      return cleanSentence;
    }
    const escaped = focusWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`\\b(${escaped})\\b`, 'i');
    if (regex.test(cleanSentence)) {
      return cleanSentence.replace(regex, '[[$1]]');
    }
    return cleanSentence;
  }

  static buildWordNoteMarkdown(
    word: Word,
    progress: WordProgress,
    enrichment?: WordEnrichment,
    today: string = dateKey()
  ): string {
    const spelling = (word.word || '').trim();
    const cleanSpelling = spelling.toLowerCase().replace(/’/g, "'");
    const wordUri = `lexiglow://word?spelling=${encodeURIComponent(cleanSpelling)}`;
    const lines: string[] = [
      '---',
      `title: ${LexiNoteBridgeService.yamlString(spelling)}`,
      'notebook: "英语精读"',
      'tags: ["词萤词卡", "词汇积累"]',
      'source_app: "LexiGlow"',
      `source_uri: ${LexiNoteBridgeService.yamlString(wordUri)}`,
      `word: ${LexiNoteBridgeService.yamlString(spelling)}`,
      `strength: ${LexiNoteBridgeService.yamlString(String(progress.strength || 0))}`,
      `captured_date: ${LexiNoteBridgeService.yamlString(today)}`,
      '---',
      `- **音标**：${word.phonetic || '—'}`,
      `- **核心释义**：${(word.meaning || '').replace(/\r?\n/g, '；')}`,
      `- **记忆状态**：强度 ${progress.strength} / 100（已复习 ${progress.reviewCount} 次）`,
      `- **词萤联动**：[在词萤中打开词卡](${wordUri}) · [打开今日计划](lexiglow://study/plan)`
    ];
    if (word.example && word.example.trim()) {
      lines.push('', '## 例句与语境', '', `> ${word.example.trim()}`);
      if (word.translation && word.translation.trim()) {
        lines.push(`> ${word.translation.trim()}`);
      }
    }
    if (enrichment) {
      const notes: string[] = [];
      const rootParts: string[] = [];
      if (enrichment.prefix && enrichment.prefix.trim()) {
        rootParts.push(`前缀 ${enrichment.prefix.trim()}`);
      }
      if (enrichment.root && enrichment.root.trim()) {
        rootParts.push(`词根 ${enrichment.root.trim()}`);
      }
      if (enrichment.suffix && enrichment.suffix.trim()) {
        rootParts.push(`后缀 ${enrichment.suffix.trim()}`);
      }
      if (enrichment.analysis && enrichment.analysis.trim()) {
        rootParts.push(enrichment.analysis.trim());
      }
      if (rootParts.length > 0) {
        notes.push(`- **词根词缀**：${rootParts.join(' · ')}`);
      }
      if (enrichment.collocations && enrichment.collocations.length > 0) {
        notes.push(`- **常见搭配**：${enrichment.collocations.join(' · ')}`);
      }
      if (enrichment.familyWords && enrichment.familyWords.length > 0) {
        const familyLinked = enrichment.familyWords
          .map((rel: WordRelation): string => rel.word && rel.word.word ? `[[${rel.word.word.trim()}]]` : '')
          .filter((item: string): boolean => item.length > 0);
        if (familyLinked.length > 0) {
          notes.push(`- **同族派生**：${familyLinked.join(' · ')}`);
        }
      }
      if (enrichment.confusingWords && enrichment.confusingWords.length > 0) {
        const linked = enrichment.confusingWords
          .map((item: ConfusingWord): string => {
            const head = item.word && item.word.word ? item.word.word.trim() : '';
            const noteText = (item.note || (item.word ? item.word.meaning : '') || '').trim();
            if (!head) {
              return noteText;
            }
            return noteText ? `[[${head}]]（${noteText}）` : `[[${head}]]`;
          })
          .filter((entry: string): boolean => entry.length > 0);
        if (linked.length > 0) {
          notes.push(`- **易混辨析**：${linked.join('；')}`);
        }
      }
      if (notes.length > 0) {
        lines.push('', '## 词汇拓展与双链', '', ...notes);
      }
    }
    return lines.join('\n') + '\n';
  }

  static buildSentenceNoteMarkdown(memory: SentenceMemory, explicitSpelling: string = '', today: string = dateKey()): string {
    const focus = LexiNoteBridgeService.focusWordFromSentence(memory.sentence, explicitSpelling);
    const articleTitle = (memory.articleTitle || '英语伴读').trim();
    const sourceUri = memory.articleId !== 0 ? `lexiglow://article?id=${memory.articleId}` : 'lexiglow://study/sentences';
    const titleSuffix = focus ? focus : articleTitle.slice(0, 24);
    const noteTitle = `原句摘录 · ${titleSuffix}`;
    const linkedSentence = LexiNoteBridgeService.highlightWikiLinkInSentence(memory.sentence, focus);
    const lines: string[] = [
      '---',
      `title: ${LexiNoteBridgeService.yamlString(noteTitle)}`,
      'notebook: "英语精读"',
      'tags: ["词萤原句", "英语精读"]',
      'source_app: "LexiGlow"',
      `source_uri: ${LexiNoteBridgeService.yamlString(sourceUri)}`,
      `article_title: ${LexiNoteBridgeService.yamlString(articleTitle)}`,
      `captured_date: ${LexiNoteBridgeService.yamlString(today)}`,
      '---',
      `> ${linkedSentence}`,
      '',
      `- **来源文章**：《${articleTitle}》`
    ];
    if (focus) {
      lines.push(`- **核心词汇**：[[${focus}]]（[在词萤中查词](lexiglow://word?spelling=${encodeURIComponent(focus)})）`);
    }
    if (memory.note && memory.note.trim()) {
      lines.push(`- **精读笔记**：${memory.note.trim()}`);
    }
    const links: string[] = ['[打开词萤原句本](lexiglow://study/sentences)'];
    if (memory.articleId !== 0) {
      links.unshift(`[回到词萤原文伴读](lexiglow://article?id=${memory.articleId})`);
    }
    lines.push(`- **词萤联动**：${links.join(' · ')}`);
    return lines.join('\n') + '\n';
  }

  static buildSentenceCollectionMarkdown(memories: SentenceMemory[], today: string = dateKey()): string {
    const bounded = memories.slice(0, 50);
    const noteTitle = `词萤原句摘录合集 · ${today}`;
    const lines: string[] = [
      '---',
      `title: ${LexiNoteBridgeService.yamlString(noteTitle)}`,
      'notebook: "英语精读"',
      'tags: ["词萤原句", "原句合集"]',
      'source_app: "LexiGlow"',
      'source_uri: "lexiglow://study/sentences"',
      `captured_date: ${LexiNoteBridgeService.yamlString(today)}`,
      '---',
      `共收录 ${bounded.length} 条原句摘录，点击 \`[[单词]]\` 可在知萤中建立双向链接，或点击 [回到词萤原句本](lexiglow://study/sentences)。`
    ];
    for (let i = 0; i < bounded.length; i++) {
      const item = bounded[i];
      const focus = LexiNoteBridgeService.focusWordFromSentence(item.sentence);
      const linkedSentence = LexiNoteBridgeService.highlightWikiLinkInSentence(item.sentence, focus);
      const articleTitle = (item.articleTitle || '英语伴读').trim();
      lines.push('', `## ${i + 1}. 来自《${articleTitle}》`, '', `> ${linkedSentence}`);
      if (item.note && item.note.trim()) {
        lines.push('', `- **备注**：${item.note.trim()}`);
      }
      if (item.articleId !== 0) {
        lines.push(`- **原文直达**：[在词萤中打开《${articleTitle}》](lexiglow://article?id=${item.articleId})`);
      }
    }
    return lines.join('\n') + '\n';
  }

  static buildMistakeBookMarkdown(mistakes: MistakeWord[], today: string = dateKey()): string {
    const bounded = mistakes.slice(0, 50);
    const noteTitle = `词萤错题复盘 · ${today}`;
    const lines: string[] = [
      '---',
      `title: ${LexiNoteBridgeService.yamlString(noteTitle)}`,
      'notebook: "英语复盘"',
      'tags: ["词萤错题本", "词汇复盘"]',
      'source_app: "LexiGlow"',
      'source_uri: "lexiglow://study/mistakes"',
      `review_date: ${LexiNoteBridgeService.yamlString(today)}`,
      '---',
      `共整理 ${bounded.length} 个易错词，点击 \`[[单词]]\` 可在知萤中关联过往阅读笔记，或点击 [回到词萤错题本练习](lexiglow://study/mistakes)。`,
      '',
      '| 单词 | 音标 | 核心释义 | 错误次数 | 强度 | 词萤直达 |',
      '| :--- | :--- | :--- | :---: | :---: | :--- |'
    ];
    for (const item of bounded) {
      const spelling = (item.word.word || '').trim();
      const phonetic = (item.word.phonetic || '—').replace(/\|/g, '/');
      const meaning = (item.word.meaning || '').replace(/\r?\n/g, '；').replace(/\|/g, '｜').slice(0, 60);
      const cleanSpelling = spelling.toLowerCase().replace(/’/g, "'");
      const wordUri = `lexiglow://word?spelling=${encodeURIComponent(cleanSpelling)}`;
      lines.push(`| [[${spelling}]] | ${phonetic} | ${meaning} | ${item.wrongCount} 次 | ${item.strength} | [词卡](${wordUri}) |`);
    }
    const withExamples = bounded.filter((item: MistakeWord): boolean => !!(item.word.example && item.word.example.trim())).slice(0, 15);
    if (withExamples.length > 0) {
      lines.push('', '## 重点易错词例句', '');
      for (const item of withExamples) {
        lines.push(`- **[[${item.word.word}]]**：${item.word.example.trim()}${item.word.translation ? '（' + item.word.translation.trim() + '）' : ''}`);
      }
    }
    return lines.join('\n') + '\n';
  }

  static extractArticleFromMarkdown(rawMarkdown: string, fallbackTitle: string = '知萤联动文章'): ArticleImport {
    let text = (rawMarkdown || '').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    let frontmatterTitle = '';
    if (text.startsWith('---\n')) {
      const lines = text.split('\n');
      let endIdx = -1;
      for (let i = 1; i < lines.length; i++) {
        if (lines[i].trim() === '---' || lines[i].trim() === '...') {
          endIdx = i;
          break;
        }
        const titleMatch = /^title:\s*(.+)$/i.exec(lines[i].trim());
        if (titleMatch && !frontmatterTitle) {
          frontmatterTitle = titleMatch[1].replace(/^["']|["']$/g, '').trim();
        }
      }
      if (endIdx > 0) {
        text = lines.slice(endIdx + 1).join('\n');
      }
    }

    let headingTitle = '';
    const bodyLines: string[] = [];
    let inFence = false;
    for (const rawLine of text.split('\n')) {
      const trimmed = rawLine.trim();
      if (/^(`{3,}|~{3,})/.test(trimmed)) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        continue;
      }
      const hMatch = /^(#{1,6})\s+(.+)$/.exec(trimmed);
      if (hMatch) {
        if (hMatch[1].length === 1 && !headingTitle) {
          headingTitle = hMatch[2].replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_m: string, t: string, a: string): string => a || t).trim();
        } else {
          bodyLines.push(hMatch[2].trim());
        }
        continue;
      }
      if (/^\|(?:\s*:?-{2,}:?\s*\|)+$/.test(trimmed)) {
        continue;
      }
      const cleanedLine = rawLine
        .replace(/!\[([^\]]*)\]\([^)]+\)/g, '$1')
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
        .replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_m: string, target: string, alias: string): string => alias || target)
        .replace(/^\s*>\s?(?:\[![A-Z]+\]\s*)?/i, '')
        .replace(/^\s*[-*+]\s+\[[ xX]\]\s+/, '')
        .replace(/(\*\*|__|==|~~|\*|_)`?([^`*_~=\n]+)`?\1/g, '$2')
        .replace(/`([^`\n]+)`/g, '$1');
      bodyLines.push(cleanedLine);
    }

    const cleanFallback = (fallbackTitle || '')
      .replace(/\.(md|markdown|txt)$/i, '')
      .trim();
    const finalTitle = (frontmatterTitle || headingTitle || cleanFallback || '知萤联动文章').slice(0, 80);
    const normalizedBody = normalizeArticleBody(bodyLines.join('\n').replace(/\n{3,}/g, '\n\n'));
    const result = new ArticleImport();
    result.title = finalTitle;
    result.body = normalizedBody;
    return result;
  }

  static readSharedFileUri(uri: string): string {
    if (!uri) {
      return '';
    }
    const path = uri.startsWith('file:') ? new fileUri.FileUri(uri).path : uri;
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        let stat = fs.statSync(file.fd);
        if (stat.size <= 0 && fs.accessSync(path)) {
          stat = fs.statSync(path);
        }
        if (stat.size <= 0 || stat.size > 512 * 1024) {
          return '';
        }
        const buffer = new ArrayBuffer(stat.size);
        const readLen = fs.readSync(file.fd, buffer);
        return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(new Uint8Array(buffer, 0, readLen));
      } finally {
        fs.closeSync(file);
      }
    } catch (_) {
      if (fs.accessSync(path)) {
        try {
          return (fs.readTextSync(path) || '').replace(/^\uFEFF/, '');
        } catch (_) {}
      }
      return '';
    }
  }

  static async resolveSharedWant(want: Want): Promise<ArticleImport> {
    const result = new ArticleImport();
    result.title = '知萤联动笔记';
    result.body = '';
    try {
      const direct = await SharedWordService.textFromWant(want);
      if (direct) {
        result.body = direct;
      }
      if (want.action === 'ohos.want.action.sendData') {
        const shared = await systemShare.getSharedData(want);
        for (const record of shared.getRecords()) {
          if (record.title && record.title.trim()) {
            result.title = record.title.trim().replace(/\.(md|markdown|txt)$/i, '').slice(0, 80) || result.title;
          }
          if (!result.body && record.uri) {
            const fileText = LexiNoteBridgeService.readSharedFileUri(record.uri);
            if (fileText.trim()) {
              result.body = fileText.trim().slice(0, 60000);
            }
          }
        }
      }
      if (result.body.trim()) {
        const cleaned = LexiNoteBridgeService.extractArticleFromMarkdown(result.body, result.title);
        if (cleaned.title) {
          result.title = cleaned.title;
        }
        if (cleaned.body) {
          result.body = cleaned.body;
        }
      }
    } catch (_) {}
    return result;
  }

  static writeShareFile(context: common.Context, title: string, markdownContent: string): string {
    const baseDir = context.cacheDir || context.filesDir;
    const shareDir = `${baseDir}/lexinote-share`;
    if (!fs.accessSync(shareDir)) {
      fs.mkdirSync(shareDir, true);
    }
    const fileName = LexiNoteBridgeService.sanitizeFileName(title);
    const fullPath = `${shareDir}/${fileName}`;
    const normalized = markdownContent.replace(/\r\n?/g, '\n');
    const content = normalized.endsWith('\n') ? normalized : `${normalized}\n`;
    const file = fs.openSync(fullPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    return fullPath;
  }

  static extractFrontmatterTitle(markdownContent: string, fallbackTitle: string): string {
    const normalized = (markdownContent || '').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    if (normalized.startsWith('---\n')) {
      const lines = normalized.split('\n');
      for (let i = 1; i < lines.length; i++) {
        const trimmed = lines[i].trim();
        if (trimmed === '---' || trimmed === '...') {
          break;
        }
        const match = /^title:\s*(.+)$/i.exec(trimmed);
        if (match) {
          const rawVal = match[1].trim();
          if (rawVal.startsWith('"') && rawVal.endsWith('"')) {
            try {
              return (JSON.parse(rawVal) as string).trim();
            } catch (_) {}
          }
          return rawVal.replace(/^['"]|['"]$/g, '').trim();
        }
      }
    }
    return (fallbackTitle || '词萤学习笔记').replace(/\.(md|markdown|txt)$/i, '').trim() || '词萤学习笔记';
  }

  static async shareMarkdownToLexiNote(
    context: common.UIAbilityContext,
    title: string,
    markdownContent: string
  ): Promise<void> {
    const normalized = (markdownContent || '').replace(/\r\n?/g, '\n');
    const content = normalized.endsWith('\n') ? normalized : `${normalized}\n`;
    const cleanTitle = LexiNoteBridgeService.extractFrontmatterTitle(content, title);

    const encodedTitle = encodeURIComponent(cleanTitle);
    const encodedContent = encodeURIComponent(content);
    const importUri = encodedContent.length <= 3200
      ? `lexinote://import?source=LexiGlow&workspace=${encodeURIComponent('词萤')}&title=${encodedTitle}&content=${encodedContent}`
      : `lexinote://import?source=LexiGlow&workspace=${encodeURIComponent('词萤')}&title=${encodedTitle}`;
    const wantParams: Record<string, Object> = {
      'lexinoteMarkdownTitle': cleanTitle,
      'lexinoteMarkdownContent': content,
      'lexinoteSourceApp': 'LexiGlow',
      'lexinoteWorkspaceName': '词萤'
    };
    try {
      await context.startAbility({
        bundleName: 'com.lovexjy.lexinote',
        abilityName: 'EntryAbility',
        uri: importUri,
        parameters: wantParams
      });
      return;
    } catch (_) {
      try {
        await context.startAbility({
          action: 'ohos.want.action.viewData',
          entities: ['entity.system.browsable'],
          uri: importUri,
          parameters: wantParams
        });
        return;
      } catch (_) {}
    }

    const filePath = LexiNoteBridgeService.writeShareFile(context, cleanTitle, content);
    const fileName = LexiNoteBridgeService.sanitizeFileName(cleanTitle);
    const record: systemShare.SharedRecord = {
      utd: LexiNoteBridgeService.resolveMarkdownUtd(),
      uri: fileUri.getUriFromPath(filePath),
      title: fileName,
      label: 'FILE',
      description: '词萤 LexiGlow · 导出到知萤双链笔记'
    };
    const shareData = new systemShare.SharedData(record);
    const controller = new systemShare.ShareController(shareData);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }
}
