import { relationalStore } from '@kit.ArkData';
import { Article, ArticleSummary } from '../model/ArticleModels';
import { articleWordCandidates, MAX_ARTICLES, normalizeArticleBody } from '../utils/ArticleTokenizer';
import { DatabaseManager, DatabaseTransaction } from './DatabaseManager';

/** Shares the learning connection and mutation queue; the 20-article limit is checked inside the write transaction. */
export class ArticleRepository {
  private database: DatabaseManager;
  private candidates: (spelling: string) => string[];
  constructor(database: DatabaseManager, candidates: (spelling: string) => string[] = articleWordCandidates) {
    this.database = database; this.candidates = candidates;
  }

  async list(): Promise<ArticleSummary[]> {
    const rows = await this.database.getStore().querySql(
      'SELECT id,title,LENGTH(body) AS character_count,created_at FROM article ORDER BY created_at DESC,id DESC LIMIT 20');
    const articles: ArticleSummary[] = [];
    try {
      while (rows.goToNextRow()) {
        const article = new ArticleSummary();
        article.id = rows.getLong(0); article.title = rows.getString(1);
        article.characterCount = rows.getLong(2); article.createdAt = rows.getLong(3);
        articles.push(article);
      }
    } finally { rows.close(); }
    return articles;
  }

  async get(id: number): Promise<Article | undefined> {
    if (!Number.isInteger(id) || id <= 0) { return undefined; }
    const rows = await this.database.getStore().querySql('SELECT id,title,body,created_at FROM article WHERE id=?', [id]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const article = new Article();
      article.id = rows.getLong(0); article.title = rows.getString(1); article.body = rows.getString(2);
      article.characterCount = article.body.length; article.createdAt = rows.getLong(3);
      return article;
    } finally { rows.close(); }
  }

  async save(title: string, body: string, now: number = Date.now()): Promise<number> {
    const content = normalizeArticleBody(body);
    const name = title.trim().slice(0, 80) || '未命名文章';
    let id = 0;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const count = await store.querySql('SELECT COUNT(*) FROM article');
      try {
        if (count.goToFirstRow() && count.getLong(0) >= MAX_ARTICLES) {
          throw new Error('最多保存 20 篇文章，请先删除一篇再导入');
        }
      } finally { count.close(); }
      await store.executeSql('INSERT INTO article(title,body,created_at) VALUES(?,?,?)', [name, content, now]);
      const inserted = await store.querySql('SELECT last_insert_rowid()');
      try { if (inserted.goToFirstRow()) { id = inserted.getLong(0); } } finally { inserted.close(); }
    });
    return id;
  }

  async remove(id: number): Promise<void> {
    if (!Number.isInteger(id) || id <= 0) { throw new Error('文章编号无效'); }
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('UPDATE sentence_memory SET article_id=0, paragraph_key=paragraph_key || ? WHERE article_id=?', ['@deleted:' + id, id]);
      await store.executeSql('UPDATE pending_word SET article_id=0, paragraph_key=paragraph_key || ? WHERE article_id=?', ['@deleted:' + id, id]);
      await store.executeSql('DELETE FROM reading_progress WHERE article_id=?', [id]);
      await store.executeSql('DELETE FROM article WHERE id=?', [id]);
    });
  }

  async learnedSpellings(spellings: string[]): Promise<string[]> {
    const matched = new Set<string>();
    // Small bounded queries keep all imported/curated inputs below SQLite's parameter limit.
    for (let start = 0; start < spellings.length; start += 80) {
      const chunk = spellings.slice(start, start + 80);
      const candidates = Array.from(new Set<string>(chunk.flatMap((word: string) => this.candidates(word))));
      if (candidates.length === 0) { continue; }
      const rows = await this.database.getStore().querySql(
        `SELECT w.word FROM word w JOIN word_progress p ON p.word_id=w.id WHERE p.review_count>0 AND w.word COLLATE NOCASE IN (${candidates.map(() => '?').join(',')})`, candidates);
      const known = new Set<string>();
      try { while (rows.goToNextRow()) { known.add(rows.getString(0).toLowerCase()); } } finally { rows.close(); }
      chunk.forEach((word: string) => {
        if (this.candidates(word).some((candidate: string) => known.has(candidate))) { matched.add(word); }
      });
    }
    return Array.from(matched);
  }

  /** One bounded IN query per rendered paragraph, including regular-form candidates. */
  async paragraphStrengths(spellings: string[]): Promise<Map<string, number>> {
    const candidates = new Set<string>();
    const unique = new Set<string>(spellings);
    unique.forEach((spelling: string) => {
      this.candidates(spelling).forEach((candidate: string) => { candidates.add(candidate); });
    });
    const strengths = new Map<string, number>();
    const values: relationalStore.ValueType[] = [];
    candidates.forEach((candidate: string) => { values.push(candidate); });
    if (values.length === 0) { return strengths; }
    // Paragraphs are capped at 160 tokens (at most 80 words). Each word has at most 6 candidates.
    if (values.length > 900) { throw new Error('文章段落过长，请重新载入'); }
    const placeholders = values.map(() => '?').join(',');
    const rows = await this.database.getStore().querySql(
      `SELECT w.word,COALESCE(p.strength,0) FROM word w LEFT JOIN word_progress p ON w.id=p.word_id WHERE w.word COLLATE NOCASE IN (${placeholders})`, values);
    const matched = new Map<string, number>();
    try {
      while (rows.goToNextRow()) { matched.set(rows.getString(0).toLowerCase(), rows.getLong(1)); }
    } finally { rows.close(); }
    unique.forEach((spelling: string) => {
      const forms = this.candidates(spelling);
      for (const candidate of forms) {
        const strength = matched.get(candidate);
        if (strength !== undefined) { strengths.set(spelling, strength); break; }
      }
    });
    return strengths;
  }
}
