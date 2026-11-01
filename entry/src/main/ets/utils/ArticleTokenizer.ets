export const MAX_ARTICLE_CHARACTERS: number = 60000;
export const MAX_ARTICLES: number = 20;
const MAX_PARAGRAPH_CHARACTERS: number = 1200;
const MAX_PARAGRAPH_TOKENS: number = 160;

export class ArticleToken {
  text: string = '';
  spelling: string = '';
  start: number = 0;
  constructor(text: string, start: number, spelling: string = '') {
    this.text = text;
    this.start = start;
    this.spelling = spelling;
  }
}

export class ArticleParagraph {
  key: string = '';
  tokens: ArticleToken[] = [];
  constructor(key: string, tokens: ArticleToken[]) {
    this.key = key;
    this.tokens = tokens;
  }
}

/** Keep punctuation, Chinese text and whitespace verbatim; only English tokens are interactive. */
export function tokenizeArticleText(text: string): ArticleToken[] {
  const tokens: ArticleToken[] = [];
  const pattern = /[A-Za-z]+(?:['’][A-Za-z]+)*|[^A-Za-z]+/g;
  let match = pattern.exec(text);
  while (match !== null) {
    const value = match[0];
    const spelling = /^[A-Za-z]/.test(value) && value.length <= 80 ?
      value.toLowerCase().replace(/’/g, "'") : '';
    tokens.push(new ArticleToken(value, match.index, spelling));
    match = pattern.exec(text);
  }
  return tokens;
}

/** Exact spelling always wins. These are candidates, not claims that a suffix is a valid inflection. */
export function articleWordCandidates(spelling: string): string[] {
  const word = spelling.trim().toLowerCase().replace(/’/g, "'");
  if (word.length === 0 || word.length > 80 || !/^[a-z]+(?:'[a-z]+)*$/.test(word)) { return []; }
  const candidates: string[] = [word];
  const add = (value: string): void => {
    if (value.length >= 2 && candidates.indexOf(value) < 0) { candidates.push(value); }
  };
  if (word.endsWith("'s")) { add(word.slice(0, -2)); }
  if (word.endsWith('ies') && word.length > 4) { add(word.slice(0, -3) + 'y'); }
  if (word.endsWith('s') && word.length > 3) { add(word.slice(0, -1)); }
  if (word.endsWith('es') && word.length > 4) { add(word.slice(0, -2)); }
  if (word.endsWith('ied') && word.length > 4) { add(word.slice(0, -3) + 'y'); }
  if (word.endsWith('ed') && word.length > 4) {
    const stem = word.slice(0, -2);
    add(stem); add(stem + 'e');
    if (/([b-df-hj-np-tv-z])\1$/.test(stem)) { add(stem.slice(0, -1)); }
  }
  if (word.endsWith('ing') && word.length > 5) {
    const stem = word.slice(0, -3);
    add(stem); add(stem + 'e');
    if (/([b-df-hj-np-tv-z])\1$/.test(stem)) { add(stem.slice(0, -1)); }
  }
  if (word.endsWith('ly') && word.length > 4) {
    const stem = word.slice(0, -2);
    add(stem);
    if (stem.endsWith('i')) { add(stem.slice(0, -1) + 'y'); }
  }
  return candidates;
}

export function normalizeArticleBody(body: string): string {
  const normalized = body.replace(/^\uFEFF/, '').replace(/\r\n?|\u2028|\u2029/g, '\n');
  if (normalized.length > MAX_ARTICLE_CHARACTERS) { throw new Error('每篇文章不能超过 60,000 字符'); }
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(normalized)) {
    throw new Error('文章含无法显示的字符，请选择文本或 Word 文档');
  }
  const content = normalized.trim();
  if (content.length === 0) { throw new Error('请先粘贴或导入文章正文'); }
  return content;
}

/** Bound a single Flex even when the source contains one 60,000-character paragraph. */
export function articleParagraphs(body: string): ArticleParagraph[] {
  const paragraphs: ArticleParagraph[] = [];
  const lines = body.split('\n');
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    const line = lines[lineIndex];
    if (!line.trim()) { continue; }
    let chunk: ArticleToken[] = [];
    let characters = 0;
    let part = 0;
    const flush = (): void => {
      if (chunk.length > 0) {
        paragraphs.push(new ArticleParagraph(`${lineIndex}:${part++}`, chunk));
        chunk = []; characters = 0;
      }
    };
    for (const token of tokenizeArticleText(line)) {
      if (token.text.length > MAX_PARAGRAPH_CHARACTERS) {
        flush();
        // An overlong run cannot be a dictionary headword. Split it without inventing words.
        for (let offset = 0; offset < token.text.length; offset += MAX_PARAGRAPH_CHARACTERS) {
          paragraphs.push(new ArticleParagraph(`${lineIndex}:${part++}`,
            [new ArticleToken(token.text.slice(offset, offset + MAX_PARAGRAPH_CHARACTERS), token.start + offset)]));
        }
      } else {
        if (characters + token.text.length > MAX_PARAGRAPH_CHARACTERS || chunk.length >= MAX_PARAGRAPH_TOKENS) {
          flush();
        }
        chunk.push(token); characters += token.text.length;
      }
    }
    flush();
  }
  return paragraphs;
}
