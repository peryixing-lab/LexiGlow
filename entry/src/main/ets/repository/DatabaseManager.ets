import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

const SCHEMA_VERSION = 6;
const SCHEMA: string[] = [
  'CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS word (id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT NOT NULL UNIQUE COLLATE NOCASE, phonetic TEXT NOT NULL, meaning TEXT NOT NULL, example TEXT NOT NULL, translation TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS word_book (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS word_book_item (book_id TEXT NOT NULL, word_id INTEGER NOT NULL, order_index INTEGER NOT NULL, override_word TEXT, override_phonetic TEXT, override_meaning TEXT, override_example TEXT, override_translation TEXT, PRIMARY KEY(book_id, word_id), FOREIGN KEY(book_id) REFERENCES word_book(id), FOREIGN KEY(word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS word_progress (word_id INTEGER PRIMARY KEY, strength INTEGER NOT NULL DEFAULT 0, level INTEGER NOT NULL DEFAULT 0, next_review_at INTEGER NOT NULL DEFAULT 0, last_review_at INTEGER NOT NULL DEFAULT 0, review_count INTEGER NOT NULL DEFAULT 0, wrong_count INTEGER NOT NULL DEFAULT 0, favorite INTEGER NOT NULL DEFAULT 0, is_new_word INTEGER NOT NULL DEFAULT 0, FOREIGN KEY(word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS review_record (id INTEGER PRIMARY KEY AUTOINCREMENT, word_id INTEGER NOT NULL, result INTEGER NOT NULL, review_at INTEGER NOT NULL, response_ms INTEGER NOT NULL, previous_level INTEGER NOT NULL, next_level INTEGER NOT NULL, previous_strength INTEGER NOT NULL, next_strength INTEGER NOT NULL, item_type TEXT NOT NULL, FOREIGN KEY(word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS daily_plan (date TEXT PRIMARY KEY, new_target INTEGER NOT NULL, review_target INTEGER NOT NULL, new_done INTEGER NOT NULL DEFAULT 0, review_done INTEGER NOT NULL DEFAULT 0, estimated_minutes INTEGER NOT NULL, budget TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS daily_summary (date TEXT PRIMARY KEY, new_count INTEGER NOT NULL DEFAULT 0, review_count INTEGER NOT NULL DEFAULT 0, known_count INTEGER NOT NULL DEFAULT 0, total_count INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS mastered_word (word_id INTEGER PRIMARY KEY, first_mastered_at INTEGER NOT NULL, FOREIGN KEY(word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS study_session (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_progress_due ON word_progress(next_review_at, strength)',
  'CREATE INDEX IF NOT EXISTS idx_word_search ON word(word COLLATE NOCASE)',
  'CREATE INDEX IF NOT EXISTS idx_book_order ON word_book_item(book_id, order_index)',
  'CREATE INDEX IF NOT EXISTS idx_record_word_time ON review_record(word_id, review_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_record_time ON review_record(review_at)',
  'CREATE INDEX IF NOT EXISTS idx_mastered_time ON mastered_word(first_mastered_at)'
];

const SCHEMA_V3: string[] = [
  "CREATE TABLE IF NOT EXISTS word_etymology (word_id INTEGER PRIMARY KEY, root TEXT NOT NULL DEFAULT '', prefix TEXT NOT NULL DEFAULT '', suffix TEXT NOT NULL DEFAULT '', analysis TEXT NOT NULL, family_words TEXT NOT NULL, FOREIGN KEY(word_id) REFERENCES word(id))",
  'CREATE TABLE IF NOT EXISTS word_enrichment (word_id INTEGER PRIMARY KEY, core_meanings TEXT NOT NULL, collocations TEXT NOT NULL, FOREIGN KEY(word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS confusing_words (word_id INTEGER NOT NULL, paired_word_id INTEGER NOT NULL, distinction_note TEXT NOT NULL, PRIMARY KEY(word_id,paired_word_id), FOREIGN KEY(word_id) REFERENCES word(id), FOREIGN KEY(paired_word_id) REFERENCES word(id))',
  'CREATE TABLE IF NOT EXISTS practice_result (id INTEGER PRIMARY KEY AUTOINCREMENT, mode TEXT NOT NULL, correct_count INTEGER NOT NULL, total_count INTEGER NOT NULL, duration_ms INTEGER NOT NULL, practiced_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS daily_glow (date TEXT PRIMARY KEY, earned_on TEXT NOT NULL, reason TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_practice_time ON practice_result(practiced_at DESC)'
];

const SCHEMA_V4: string[] = [
  'CREATE TABLE IF NOT EXISTS review_undo (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS article (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_article_created ON article(created_at DESC,id DESC)',
  'CREATE INDEX IF NOT EXISTS idx_progress_mistakes ON word_progress(wrong_count DESC,last_review_at DESC)'
];

const SCHEMA_V5: string[] = [
  'CREATE TABLE IF NOT EXISTS practice_attempt (id TEXT PRIMARY KEY, word_id INTEGER NOT NULL REFERENCES word(id), mode TEXT NOT NULL, correct INTEGER NOT NULL, hinted INTEGER NOT NULL, duration_ms INTEGER NOT NULL, recorded_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_attempt_word ON practice_attempt(word_id,recorded_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_attempt_time ON practice_attempt(recorded_at DESC)',
  'CREATE TABLE IF NOT EXISTS sentence_memory (id TEXT PRIMARY KEY, word_id INTEGER NOT NULL REFERENCES word(id), article_id INTEGER NOT NULL, article_title TEXT NOT NULL, paragraph_key TEXT NOT NULL, sentence TEXT NOT NULL, note TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(word_id,article_id,paragraph_key,sentence))',
  'CREATE INDEX IF NOT EXISTS idx_sentence_word ON sentence_memory(word_id,created_at DESC)',
  'CREATE TABLE IF NOT EXISTS reading_progress (article_id INTEGER PRIMARY KEY, paragraph_index INTEGER NOT NULL, completed INTEGER NOT NULL, answers TEXT NOT NULL, updated_at INTEGER NOT NULL)'
];

const SCHEMA_V6: string[] = [
  "ALTER TABLE sentence_memory ADD COLUMN target_text TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE sentence_memory ADD COLUMN target_start INTEGER NOT NULL DEFAULT -1',
  'ALTER TABLE sentence_memory ADD COLUMN recall_enabled INTEGER NOT NULL DEFAULT 1',
  'CREATE TABLE IF NOT EXISTS sentence_recall_attempt (id TEXT PRIMARY KEY, sentence_id TEXT NOT NULL REFERENCES sentence_memory(id) ON DELETE CASCADE, correct INTEGER NOT NULL, hinted INTEGER NOT NULL, duration_ms INTEGER NOT NULL, recorded_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_sentence_recall_time ON sentence_recall_attempt(sentence_id,recorded_at DESC)',
  'CREATE TABLE IF NOT EXISTS pending_word (id TEXT PRIMARY KEY, spelling TEXT NOT NULL COLLATE NOCASE, sentence TEXT NOT NULL, article_id INTEGER NOT NULL, article_title TEXT NOT NULL, paragraph_key TEXT NOT NULL, target_text TEXT NOT NULL, target_start INTEGER NOT NULL, created_at INTEGER NOT NULL, UNIQUE(spelling,article_id,paragraph_key,sentence))'
];

/** All reads and writes inside a transaction use its connection, including reads after batchInsert. */
export class DatabaseTransaction {
  private transaction: relationalStore.Transaction;

  constructor(transaction: relationalStore.Transaction) {
    this.transaction = transaction;
  }

  async executeSql(sql: string, args: relationalStore.ValueType[] = []): Promise<void> {
    await this.transaction.execute(sql, args);
  }

  querySql(sql: string, args: relationalStore.ValueType[] = []): Promise<relationalStore.ResultSet> {
    return this.transaction.querySql(sql, args);
  }

  batchInsert(table: string, values: relationalStore.ValuesBucket[]): Promise<number> {
    return this.transaction.batchInsert(table, values);
  }
}

/** Owns the connection and serializes transactions so one mutation cannot commit another's work. */
export class DatabaseManager {
  private store: relationalStore.RdbStore | undefined = undefined;
  private writes: Promise<void> = Promise.resolve();
  private safetyBackupName: string = 'pre_restore.db';

  async initialize(context: common.Context, databaseName: string = 'ciying.db'): Promise<void> {
    this.safetyBackupName = databaseName === 'ciying.db' ? 'pre_restore.db' : `${databaseName}.pre_restore.db`;
    const config: relationalStore.StoreConfig = {
      name: databaseName, securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql('PRAGMA foreign_keys = ON');
    if (this.store.version > SCHEMA_VERSION) {
      throw new Error('学习数据来自较新版本，请更新词萤后再打开');
    }
    if (this.store.version < SCHEMA_VERSION) {
      const previousVersion = this.store.version;
      await this.transaction(async (store: DatabaseTransaction) => {
        if (previousVersion === 0) {
          for (const statement of SCHEMA) {
            await store.executeSql(statement);
          }
        } else if (previousVersion === 1) {
          for (const column of ['word', 'phonetic', 'meaning', 'example', 'translation']) {
            await store.executeSql(`ALTER TABLE word_book_item ADD COLUMN override_${column} TEXT`);
          }
        }
        if (previousVersion < 3) {
          for (const column of ['hesitation_count', 'last_response_ms', 'consecutive_failures', 'consecutive_known']) {
            await store.executeSql(`ALTER TABLE word_progress ADD COLUMN ${column} INTEGER NOT NULL DEFAULT 0`);
          }
          await store.executeSql('ALTER TABLE daily_plan ADD COLUMN backlog_count INTEGER NOT NULL DEFAULT 0');
          for (const statement of SCHEMA_V3) {
            await store.executeSql(statement);
          }
        }
        if (previousVersion < 4) {
          for (const statement of SCHEMA_V4) { await store.executeSql(statement); }
        }
        if (previousVersion < 5) {
          for (const statement of SCHEMA_V5) { await store.executeSql(statement); }
        }
        if (previousVersion < 6) {
          for (const statement of SCHEMA_V6) { await store.executeSql(statement); }
        }
        await store.executeSql(`PRAGMA user_version = ${SCHEMA_VERSION}`);
      });
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('学习数据库尚未初始化');
    }
    return this.store;
  }

  async transaction(operation: (store: DatabaseTransaction) => Promise<void>, safetyBackup: boolean = false): Promise<void> {
    const task = this.writes.then(async () => {
      // Backup failure aborts before any mutation. WAL/transaction rollback also protects process interruption.
      if (safetyBackup) { await this.getStore().backup(this.safetyBackupName); }
      const transaction = await this.getStore().createTransaction();
      try {
        await operation(new DatabaseTransaction(transaction));
        await transaction.commit();
      } catch (error) {
        try { await transaction.rollback(); } catch (_) {
          if (!safetyBackup) { throw new Error('学习事务回滚失败，请重新打开应用'); }
        }
        if (safetyBackup) { await this.getStore().restore(this.safetyBackupName); }
        throw new Error((error as Error).message || '学习数据保存失败');
      }
    });
    this.writes = task.then(() => {}, () => {});
    await task;
  }

  async backup(destination: string): Promise<void> {
    const task = this.writes.then(() => this.getStore().backup(destination));
    this.writes = task.then(() => {}, () => {});
    await task;
  }
}
