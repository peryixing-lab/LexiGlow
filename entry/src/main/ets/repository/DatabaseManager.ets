import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

const SCHEMA_VERSION = 2;
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

  async initialize(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'ciying.db', securityLevel: relationalStore.SecurityLevel.S1
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

  async transaction(operation: (store: DatabaseTransaction) => Promise<void>): Promise<void> {
    const task = this.writes.then(async () => {
      const transaction = await this.getStore().createTransaction();
      try {
        await operation(new DatabaseTransaction(transaction));
        await transaction.commit();
      } catch (error) {
        await transaction.rollback();
        throw new Error((error as Error).message || '学习数据保存失败');
      }
    });
    this.writes = task.then(() => {}, () => {});
    await task;
  }
}
