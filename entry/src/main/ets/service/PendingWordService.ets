import { relationalStore } from '@kit.ArkData';
import { DatabaseManager, DatabaseTransaction } from '../repository/DatabaseManager';
import { PendingWordDraft } from '../model/PendingWordModels';
import { DataExport } from '../model/AppModels';

/** Unknown words remain drafts until the user supplies a meaning; they are never daily tasks. */
export class PendingWordService {
  private static instance: PendingWordService = new PendingWordService();
  private database?: DatabaseManager;
  static getInstance(): PendingWordService { return PendingWordService.instance; }
  initialize(database: DatabaseManager): void { this.database = database; }
  private db(): DatabaseManager {
    if (!this.database) { throw new Error('待补充词尚未载入'); }
    return this.database;
  }
  private static read(rows: relationalStore.ResultSet): PendingWordDraft[] {
    const result: PendingWordDraft[] = [];
    try { while (rows.goToNextRow()) {
      const draft = new PendingWordDraft(); draft.id = rows.getString(0); draft.spelling = rows.getString(1);
      draft.sentence = rows.getString(2); draft.articleId = rows.getLong(3); draft.articleTitle = rows.getString(4);
      draft.paragraphKey = rows.getString(5); draft.targetText = rows.getString(6); draft.targetStart = rows.getLong(7);
      draft.createdAt = rows.getLong(8); result.push(draft);
    } } finally { rows.close(); }
    return result;
  }
  list(): Promise<PendingWordDraft[]> {
    return this.db().getStore().querySql('SELECT * FROM pending_word ORDER BY created_at DESC,id DESC LIMIT 500')
      .then((rows: relationalStore.ResultSet): PendingWordDraft[] => PendingWordService.read(rows));
  }
  async save(input: PendingWordDraft): Promise<void> {
    const draft = JSON.parse(JSON.stringify(input)) as PendingWordDraft;
    if (!draft.id || draft.id.length > 140 || !/^[a-z]+(?:['’][a-z]+)*$/i.test(draft.spelling) || draft.spelling.length > 80 ||
      !draft.sentence.trim() || draft.sentence.length > 2000 || !Number.isInteger(draft.targetStart) || draft.targetStart < 0 ||
      !/^[a-z]+(?:['’][a-z]+)*$/i.test(draft.targetText) || draft.targetText.length > 80 ||
      draft.targetText.toLowerCase().replace(/’/g, "'") !== draft.spelling.toLowerCase().replace(/’/g, "'") ||
      draft.sentence.slice(draft.targetStart, draft.targetStart + draft.targetText.length) !== draft.targetText ||
      /[A-Za-z'’]/.test(draft.sentence.charAt(draft.targetStart - 1)) ||
      /[A-Za-z'’]/.test(draft.sentence.charAt(draft.targetStart + draft.targetText.length)) ||
      !Number.isInteger(draft.articleId) || !draft.articleTitle.trim() || draft.articleTitle.length > 80 ||
      !draft.paragraphKey || draft.paragraphKey.length > 80 || !Number.isInteger(draft.createdAt) || draft.createdAt < 0) {
      throw new Error('待补充词或原句位置不完整，请重新点词');
    }
    draft.spelling = draft.spelling.toLowerCase();
    await this.db().transaction(async (store: DatabaseTransaction) => {
      if (draft.articleId > 0) {
        const article = await store.querySql('SELECT id FROM article WHERE id=?', [draft.articleId]);
        try { if (!article.goToFirstRow()) { draft.paragraphKey += '@deleted:' + draft.articleId; draft.articleId = 0; } }
        finally { article.close(); }
      }
      const existing = await store.querySql('SELECT id FROM pending_word WHERE spelling=? AND article_id=? AND paragraph_key=? AND sentence=?',
        [draft.spelling, draft.articleId, draft.paragraphKey, draft.sentence]);
      try { if (existing.goToFirstRow()) { return; } } finally { existing.close(); }
      const count = await store.querySql('SELECT COUNT(*) FROM pending_word');
      try { if (count.goToFirstRow() && count.getLong(0) >= 500) { throw new Error('待补充词已达 500 条，请先在我的原句中整理'); } }
      finally { count.close(); }
      await store.executeSql('INSERT INTO pending_word VALUES(?,?,?,?,?,?,?,?,?)',
        [draft.id, draft.spelling.toLowerCase(), draft.sentence, draft.articleId, draft.articleTitle,
          draft.paragraphKey, draft.targetText, draft.targetStart, draft.createdAt]);
    });
  }
  async remove(id: string): Promise<void> {
    await this.db().transaction(async (store: DatabaseTransaction) => { await store.executeSql('DELETE FROM pending_word WHERE id=?', [id]); });
  }
  async complete(draftId: string, meaning: string): Promise<void> {
    const text = meaning.trim();
    if (!text || text.length > 4000) { throw new Error('请填写不超过 4000 字的释义'); }
    await this.db().transaction(async (store: DatabaseTransaction) => {
      const draft = PendingWordService.read(await store.querySql('SELECT * FROM pending_word WHERE id=?', [draftId]))[0];
      if (!draft) { return; }
      await store.executeSql("INSERT OR IGNORE INTO word(word,phonetic,meaning,example,translation) VALUES(?,'',?,'','')", [draft.spelling, text]);
      const word = await store.querySql('SELECT id FROM word WHERE word=? COLLATE NOCASE', [draft.spelling]);
      let wordId = 0;
      try { if (word.goToFirstRow()) { wordId = word.getLong(0); } } finally { word.close(); }
      if (wordId <= 0) { throw new Error('单词未能保存，请重试'); }
      if (draft.articleId > 0) {
        const article = await store.querySql('SELECT id FROM article WHERE id=?', [draft.articleId]);
        try { if (!article.goToFirstRow()) { draft.paragraphKey += '@deleted:' + draft.articleId; draft.articleId = 0; } }
        finally { article.close(); }
      }
      const count = await store.querySql('SELECT COUNT(*),SUM(CASE WHEN word_id=? THEN 1 ELSE 0 END) FROM sentence_memory', [wordId]);
      try { if (count.goToFirstRow() && (count.getLong(0) >= 5000 || count.getLong(1) >= 100)) {
        throw new Error('原句收藏已达上限，请先整理后再补充');
      } } finally { count.close(); }
      await store.executeSql('INSERT INTO sentence_memory(id,word_id,article_id,article_title,paragraph_key,sentence,note,created_at,target_text,target_start,recall_enabled) VALUES(?,?,?,?,?,?,?,?,?,?,1) ON CONFLICT(word_id,article_id,paragraph_key,sentence) DO UPDATE SET target_text=excluded.target_text,target_start=excluded.target_start',
        ['pending_' + draft.id, wordId, draft.articleId, draft.articleTitle, draft.paragraphKey, draft.sentence, '', draft.createdAt, draft.targetText, draft.targetStart]);
      await store.executeSql('DELETE FROM pending_word WHERE id=?', [draftId]);
    });
  }
  static async exportInside(store: DatabaseTransaction, backup: DataExport): Promise<void> {
    backup.pendingWords = PendingWordService.read(await store.querySql('SELECT * FROM pending_word ORDER BY created_at DESC,id DESC'));
  }
  static async restoreInside(store: DatabaseTransaction, backup: DataExport): Promise<void> {
    if (backup.version < 5) {
      if (backup.version >= 4) {
        await store.executeSql("UPDATE pending_word SET paragraph_key=paragraph_key || '@restored:' || article_id,article_id=0 WHERE article_id>0");
      }
      return;
    }
    await store.executeSql('DELETE FROM pending_word');
    for (const draft of backup.pendingWords) {
      await store.executeSql('INSERT INTO pending_word VALUES(?,?,?,?,?,?,?,?,?)',
        [draft.id, draft.spelling, draft.sentence, draft.articleId, draft.articleTitle,
          draft.paragraphKey, draft.targetText, draft.targetStart, draft.createdAt]);
    }
  }
}
