import { relationalStore } from '@kit.ArkData';
import { PracticeAttempt, SentenceMemory, ReadingProgress } from '../model/ExperienceModels';
import { Article } from '../model/ArticleModels';
import { DataExport } from '../model/AppModels';
import { DatabaseManager, DatabaseTransaction } from './DatabaseManager';

export class ExperienceRepository {
  private database: DatabaseManager;
  constructor(database: DatabaseManager) { this.database = database; }

  async saveAttempt(attempt: PracticeAttempt): Promise<void> {
    if (!attempt.id || attempt.wordId <= 0 || !['meaning', 'dictation', 'spelling', 'cloze'].includes(attempt.mode) ||
      !Number.isFinite(attempt.durationMs) || attempt.durationMs < 0) { throw new Error('练习记录不完整'); }
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT OR IGNORE INTO practice_attempt(id,word_id,mode,correct,hinted,duration_ms,recorded_at) VALUES(?,?,?,?,?,?,?)',
        [attempt.id, attempt.wordId, attempt.mode, attempt.correct ? 1 : 0, attempt.hinted ? 1 : 0,
          Math.min(3600000, Math.floor(attempt.durationMs)), attempt.recordedAt]);
    });
  }

  async attempts(wordId: number = 0): Promise<PracticeAttempt[]> {
    const rows = await this.database.getStore().querySql(wordId > 0 ?
      'SELECT * FROM practice_attempt WHERE word_id=? ORDER BY recorded_at DESC,id DESC LIMIT 100' :
      'SELECT * FROM practice_attempt ORDER BY recorded_at DESC,id DESC LIMIT 1000', wordId > 0 ? [wordId] : []);
    return ExperienceRepository.readAttempts(rows);
  }

  private static readAttempts(rows: relationalStore.ResultSet): PracticeAttempt[] {
    const result: PracticeAttempt[] = [];
    try { while (rows.goToNextRow()) {
      const item = new PracticeAttempt(); item.id = rows.getString(0); item.wordId = rows.getLong(1);
      item.mode = rows.getString(2); item.correct = rows.getLong(3) === 1; item.hinted = rows.getLong(4) === 1;
      item.durationMs = rows.getLong(5); item.recordedAt = rows.getLong(6); result.push(item);
    } } finally { rows.close(); }
    return result;
  }

  async sentences(wordId: number = 0): Promise<SentenceMemory[]> {
    const rows = await this.database.getStore().querySql(wordId > 0 ?
      'SELECT * FROM sentence_memory WHERE word_id=? ORDER BY created_at DESC LIMIT 100' :
      'SELECT * FROM sentence_memory ORDER BY created_at DESC LIMIT 5000', wordId > 0 ? [wordId] : []);
    return ExperienceRepository.readSentences(rows);
  }

  private static readSentences(rows: relationalStore.ResultSet): SentenceMemory[] {
    const result: SentenceMemory[] = [];
    try { while (rows.goToNextRow()) {
      const item = new SentenceMemory(); item.id = rows.getString(0); item.wordId = rows.getLong(1);
      item.articleId = rows.getLong(2); item.articleTitle = rows.getString(3); item.paragraphKey = rows.getString(4);
      item.sentence = rows.getString(5); item.note = rows.getString(6); item.createdAt = rows.getLong(7); result.push(item);
    } } finally { rows.close(); }
    return result;
  }

  async saveSentence(item: SentenceMemory): Promise<void> {
    if (!item.id || item.wordId <= 0 || !item.sentence.trim() || item.sentence.length > 2000 || item.note.length > 500) {
      throw new Error('原句不能为空，备注最多 500 字');
    }
    await this.database.transaction(async (store: DatabaseTransaction) => {
      if (item.articleId > 0) {
        const source = await store.querySql('SELECT id FROM article WHERE id=?', [item.articleId]);
        try { if (!source.goToFirstRow()) { item.paragraphKey += '@deleted:' + item.articleId; item.articleId = 0; } }
        finally { source.close(); }
      }
      const existing = await store.querySql('SELECT id FROM sentence_memory WHERE word_id=? AND article_id=? AND paragraph_key=? AND sentence=?',
        [item.wordId, item.articleId, item.paragraphKey, item.sentence]);
      let existingId = '';
      try { if (existing.goToFirstRow()) { existingId = existing.getString(0); } } finally { existing.close(); }
      if (existingId) {
        await store.executeSql('UPDATE sentence_memory SET note=? WHERE id=?', [item.note.trim(), existingId]); return;
      }
      const count = await store.querySql('SELECT COUNT(*) FROM sentence_memory WHERE word_id=?', [item.wordId]);
      try { if (count.goToFirstRow() && count.getLong(0) >= 100) { throw new Error('这个词已收藏 100 条原句，请先整理后再保存'); } }
      finally { count.close(); }
      const total = await store.querySql('SELECT COUNT(*) FROM sentence_memory');
      try { if (total.goToFirstRow() && total.getLong(0) >= 5000) { throw new Error('已收藏 5000 条原句，请先整理后再保存'); } }
      finally { total.close(); }
      await store.executeSql('INSERT INTO sentence_memory(id,word_id,article_id,article_title,paragraph_key,sentence,note,created_at) VALUES(?,?,?,?,?,?,?,?)',
        [item.id, item.wordId, item.articleId, item.articleTitle, item.paragraphKey, item.sentence, item.note.trim(), item.createdAt]);
    });
  }

  async removeSentence(id: string): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => { await store.executeSql('DELETE FROM sentence_memory WHERE id=?', [id]); });
  }

  async reading(articleId: number): Promise<ReadingProgress> {
    const rows = await this.database.getStore().querySql('SELECT * FROM reading_progress WHERE article_id=?', [articleId]);
    const progress = new ReadingProgress(); progress.articleId = articleId;
    try { if (rows.goToFirstRow()) {
      progress.paragraphIndex = rows.getLong(1); progress.completed = rows.getLong(2) === 1;
      progress.answers = JSON.parse(rows.getString(3)) as number[]; progress.updatedAt = rows.getLong(4);
    } } finally { rows.close(); }
    return progress;
  }

  async savePosition(articleId: number, paragraphIndex: number): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql("INSERT INTO reading_progress VALUES(?,?,0,'[]',?) ON CONFLICT(article_id) DO UPDATE SET paragraph_index=excluded.paragraph_index,updated_at=excluded.updated_at",
        [articleId, paragraphIndex, Date.now()]);
    });
  }

  async saveReading(progress: ReadingProgress): Promise<void> {
    if (!Number.isInteger(progress.articleId) || progress.articleId === 0 || !Number.isInteger(progress.paragraphIndex) ||
      progress.paragraphIndex < 0 || progress.answers.length > 10) { throw new Error('阅读位置无效'); }
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO reading_progress(article_id,paragraph_index,completed,answers,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(article_id) DO UPDATE SET completed=excluded.completed,answers=excluded.answers,updated_at=excluded.updated_at',
        [progress.articleId, progress.paragraphIndex, progress.completed ? 1 : 0, JSON.stringify(progress.answers), progress.updatedAt]);
    });
  }

  async exportInto(backup: DataExport): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      backup.practiceAttempts = ExperienceRepository.readAttempts(await store.querySql('SELECT * FROM practice_attempt ORDER BY recorded_at DESC,id DESC'));
      backup.sentences = ExperienceRepository.readSentences(await store.querySql('SELECT * FROM sentence_memory ORDER BY created_at DESC'));
      const articles = await store.querySql('SELECT id,title,body,created_at FROM article ORDER BY id');
      try { while (articles.goToNextRow()) {
        const article = new Article(); article.id = articles.getLong(0); article.title = articles.getString(1);
        article.body = articles.getString(2); article.characterCount = article.body.length; article.createdAt = articles.getLong(3);
        backup.articles.push(article);
      } } finally { articles.close(); }
      const readings = await store.querySql('SELECT * FROM reading_progress ORDER BY article_id');
      try { while (readings.goToNextRow()) {
        const progress = new ReadingProgress(); progress.articleId = readings.getLong(0); progress.paragraphIndex = readings.getLong(1);
        progress.completed = readings.getLong(2) === 1; progress.answers = JSON.parse(readings.getString(3)) as number[];
        progress.updatedAt = readings.getLong(4); backup.readingProgress.push(progress);
      } } finally { readings.close(); }
    });
  }

  static async restore(store: DatabaseTransaction, backup: DataExport, idMap: Map<number, number>): Promise<void> {
    await store.executeSql('DELETE FROM practice_attempt');
    for (const item of backup.practiceAttempts) {
      const wordId = idMap.get(item.wordId); if (!wordId) { continue; }
      await store.executeSql('INSERT INTO practice_attempt VALUES(?,?,?,?,?,?,?)',
        [item.id, wordId, item.mode, item.correct ? 1 : 0, item.hinted ? 1 : 0, item.durationMs, item.recordedAt]);
    }
    // Older backups did not contain reading data; keep local articles and memories intact.
    if (backup.version < 4) { return; }
    for (const table of ['sentence_memory', 'reading_progress', 'article']) { await store.executeSql(`DELETE FROM ${table}`); }
    for (const article of backup.articles) {
      await store.executeSql('INSERT INTO article(id,title,body,created_at) VALUES(?,?,?,?)',
        [article.id, article.title, article.body, article.createdAt]);
    }
    for (const item of backup.sentences) {
      const wordId = idMap.get(item.wordId); if (!wordId) { continue; }
      await store.executeSql('INSERT INTO sentence_memory VALUES(?,?,?,?,?,?,?,?)',
        [item.id, wordId, item.articleId, item.articleTitle, item.paragraphKey, item.sentence, item.note, item.createdAt]);
    }
    for (const item of backup.readingProgress) {
      await store.executeSql('INSERT INTO reading_progress VALUES(?,?,?,?,?)',
        [item.articleId, item.paragraphIndex, item.completed ? 1 : 0, JSON.stringify(item.answers), item.updatedAt]);
    }
  }
}
