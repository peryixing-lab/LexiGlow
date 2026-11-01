import { ExperienceRepository } from './ExperienceRepository';
import { relationalStore } from '@kit.ArkData';
import { ConfusingWord, GlowRecord, PracticeResult, WordEnrichment, WordRelation, DailyPlan, DaySummary, DictionaryBook, DictionaryCatalog, LearnedDate, LearnedWord, ReviewRecord, ReviewResult,
  DataExport, MasteredWord, MistakeWord, ReviewUndo, Statistics, StudyItem, StudySession, Word, WordBook, WordProgress } from '../model/AppModels';
import { dateKey, dayStart, shiftedDate, weekStart } from '../utils/TimeUtils';
import { strengthAfterResult } from '../utils/MemoryUtils';
import { CONFUSING_SEEDS, ENRICHMENT_SEEDS } from '../utils/WordEnrichmentSeeds';
import { DatabaseManager, DatabaseTransaction } from './DatabaseManager';

export class LearningRepository {
  private database: DatabaseManager;

  constructor(database: DatabaseManager) {
    this.database = database;
  }

  private store(): relationalStore.RdbStore {
    return this.database.getStore();
  }

  async scalar(sql: string, args: relationalStore.ValueType[] = []): Promise<number> {
    const rows = await this.store().querySql(sql, args);
    try {
      return rows.goToFirstRow() ? rows.getDouble(0) : 0;
    } finally {
      rows.close();
    }
  }

  async dictionaryVersion(): Promise<number> {
    return this.scalar("SELECT CAST(value AS INTEGER) FROM app_meta WHERE key='dictionary_version'");
  }

  /** Restore the product-plan strength rules and totals without changing the saved schedule. */
  async migrateLearningSemantics(): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const versionRows = await store.querySql("SELECT value FROM app_meta WHERE key='learning_semantics_version'");
      let migrated = false;
      try {
        migrated = versionRows.goToFirstRow() && Number(versionRows.getString(0)) >= 2;
      } finally {
        versionRows.close();
      }
      if (migrated) {
        return;
      }

      const records: ReviewRecord[] = [];
      const rows = await store.querySql('SELECT * FROM review_record ORDER BY id ASC');
      try {
        while (rows.goToNextRow()) {
          records.push(this.readRecord(rows));
        }
      } finally {
        rows.close();
      }

      const progress: WordProgress[] = [];
      const progressRows = await store.querySql('SELECT * FROM word_progress');
      try {
        while (progressRows.goToNextRow()) {
          progress.push(this.readProgress(progressRows));
        }
      } finally {
        progressRows.close();
      }

      // A partial or inconsistent history cannot reconstruct the current strength safely.
      const recordCounts = new Map<number, number>();
      const originalStrengths = new Map<number, number>();
      const brokenWords = new Set<number>();
      for (const record of records) {
        // A newer +8 response-time event must never be replayed under the legacy +12 rule.
        if (record.result === ReviewResult.KNOW && record.responseMs > 4000 &&
          record.nextStrength === Math.min(100, record.previousStrength + 8)) {
          brokenWords.add(record.wordId);
        }
        const previousStrength = originalStrengths.get(record.wordId);
        const validResult = record.result === ReviewResult.FORGET || record.result === ReviewResult.FUZZY ||
          record.result === ReviewResult.KNOW;
        let validTransition = false;
        if (validResult) {
          const plannedStrength = strengthAfterResult(record.previousStrength, record.result);
          const legacyStrength = record.result === ReviewResult.KNOW ?
            Math.min(100, Math.max(50, record.previousStrength + 12)) :
            (record.result === ReviewResult.FUZZY ? Math.min(100, Math.max(25, record.previousStrength + 5)) :
              Math.max(0, record.previousStrength - 20));
          validTransition = record.nextStrength === plannedStrength || record.nextStrength === legacyStrength;
        }
        if (!validTransition || record.previousStrength < 0 || record.previousStrength > 100 ||
          record.nextStrength < 0 || record.nextStrength > 100 ||
          (previousStrength === undefined ? record.previousStrength !== 0 :
            record.previousStrength !== previousStrength)) {
          brokenWords.add(record.wordId);
        }
        recordCounts.set(record.wordId, (recordCounts.get(record.wordId) || 0) + 1);
        originalStrengths.set(record.wordId, record.nextStrength);
      }
      const validWords = new Set<number>();
      for (const saved of progress) {
        const recordCount = recordCounts.get(saved.wordId);
        if (recordCount !== undefined && recordCount === saved.reviewCount &&
          !brokenWords.has(saved.wordId) && originalStrengths.get(saved.wordId) === saved.strength) {
          validWords.add(saved.wordId);
        }
      }

      const strengths = new Map<number, number>();
      const firstMasteredAt = new Map<number, number>();
      for (const record of records) {
        if (!validWords.has(record.wordId)) {
          continue;
        }
        const saved = strengths.get(record.wordId);
        const previousStrength = saved === undefined ? record.previousStrength : saved;
        const nextStrength = strengthAfterResult(previousStrength, record.result);
        if (record.previousStrength !== previousStrength || record.nextStrength !== nextStrength) {
          await store.executeSql('UPDATE review_record SET previous_strength=?,next_strength=? WHERE id=?',
            [previousStrength, nextStrength, record.id]);
        }
        strengths.set(record.wordId, nextStrength);
        if (nextStrength >= 75 && !firstMasteredAt.has(record.wordId)) {
          firstMasteredAt.set(record.wordId, record.reviewAt);
        }
      }
      for (const saved of progress) {
        const strength = strengths.get(saved.wordId);
        if (strength !== undefined && saved.strength !== strength) {
          await store.executeSql('UPDATE word_progress SET strength=? WHERE word_id=?', [strength, saved.wordId]);
        }
      }
      // The floor-based version could create an early or entirely incorrect mastery event.
      // Complete histories let us replace its date exactly, or remove a mastery never earned.
      for (const wordId of validWords.keys()) {
        const masteredAt = firstMasteredAt.get(wordId);
        if (masteredAt !== undefined) {
          await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?) ON CONFLICT(word_id) DO UPDATE SET first_mastered_at=excluded.first_mastered_at',
            [wordId, masteredAt]);
        } else {
          await store.executeSql('DELETE FROM mastered_word WHERE word_id=?', [wordId]);
        }
      }
      await store.executeSql('UPDATE daily_summary SET total_count=new_count+review_count');
      await store.executeSql('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        ['learning_semantics_version', '2']);
    });
  }

  async importCatalog(catalog: DictionaryCatalog): Promise<void> {
    const storedVersion = await this.dictionaryVersion();
    if (storedVersion > catalog.version) {
      return;
    }
    if (storedVersion === catalog.version) {
      const books = await this.getBooks();
      const needsRepair = catalog.books.some((book: DictionaryBook) => {
        const saved = books.find((item: WordBook) => item.id === book.id);
        const unique = new Set<string>();
        for (const word of book.words) {
          unique.add(word.word.trim().toLowerCase());
        }
        return !saved || saved.totalCount !== unique.size;
      });
      if (!needsRepair) {
        return;
      }
    }
    for (const book of catalog.books) {
      await this.insertBook(book);
    }
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        ['dictionary_version', `${catalog.version}`]);
    });
  }

  async insertBook(book: DictionaryBook): Promise<number> {
    let count = 0;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO word_book(id,name,category,description) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, category=excluded.category, description=excluded.description',
        [book.id, book.name, book.category, book.description]);
      let identities = await this.wordIdentities(store);
      const pending = new Set<string>();
      let wordBatch: relationalStore.ValuesBucket[] = [];
      for (const word of book.words) {
        const identity = word.word.trim().toLowerCase();
        if (!identities.has(identity) && !pending.has(identity)) {
          const values: relationalStore.ValuesBucket = {
            word: identity, phonetic: word.phonetic, meaning: word.meaning,
            example: word.example, translation: word.translation
          };
          pending.add(identity);
          wordBatch.push(values);
          if (wordBatch.length === 500) {
            await store.batchInsert('word', wordBatch);
            wordBatch = [];
          }
        }
      }
      if (wordBatch.length > 0) {
        await store.batchInsert('word', wordBatch);
      }
      identities = await this.wordIdentities(store);
      const existing = new Set<number>();
      const rows = await store.querySql('SELECT word_id FROM word_book_item WHERE book_id=?', [book.id]);
      try {
        while (rows.goToNextRow()) {
          existing.add(rows.getLong(0));
        }
      } finally {
        rows.close();
      }
      let itemBatch: relationalStore.ValuesBucket[] = [];
      let index = 0;
      for (const word of book.words) {
        const id = identities.get(word.word.trim().toLowerCase());
        if (id !== undefined && !existing.has(id)) {
          const item: relationalStore.ValuesBucket = { book_id: book.id, word_id: id, order_index: index };
          if (book.category === 'custom') {
            item.override_word = word.word.trim();
            item.override_phonetic = word.phonetic;
            item.override_meaning = word.meaning;
            item.override_example = word.example;
            item.override_translation = word.translation;
          }
          itemBatch.push(item);
          existing.add(id);
          if (itemBatch.length === 500) {
            await store.batchInsert('word_book_item', itemBatch);
            itemBatch = [];
          }
        }
        index += 1;
      }
      if (itemBatch.length > 0) {
        await store.batchInsert('word_book_item', itemBatch);
      }
      const totals = await store.querySql('SELECT COUNT(*) FROM word_book_item WHERE book_id=?', [book.id]);
      try {
        count = totals.goToFirstRow() ? totals.getLong(0) : 0;
      } finally {
        totals.close();
      }
    });
    return count;
  }

  private async wordIdentities(store: DatabaseTransaction): Promise<Map<string, number>> {
    const identities = new Map<string, number>();
    const rows = await store.querySql('SELECT id,word FROM word');
    try {
      while (rows.goToNextRow()) {
        identities.set(rows.getString(1).trim().toLowerCase(), rows.getLong(0));
      }
    } finally {
      rows.close();
    }
    return identities;
  }

  async getBooks(): Promise<WordBook[]> {
    const rows = await this.store().querySql('SELECT b.*, COUNT(i.word_id) AS total_count, SUM(CASE WHEN p.review_count>0 THEN 1 ELSE 0 END) AS learned_count FROM word_book b LEFT JOIN word_book_item i ON b.id=i.book_id LEFT JOIN word_progress p ON i.word_id=p.word_id GROUP BY b.id ORDER BY b.rowid');
    const books: WordBook[] = [];
    try {
      while (rows.goToNextRow()) {
        const book = new WordBook();
        book.id = rows.getString(rows.getColumnIndex('id'));
        book.name = rows.getString(rows.getColumnIndex('name'));
        book.category = rows.getString(rows.getColumnIndex('category'));
        book.description = rows.getString(rows.getColumnIndex('description'));
        book.totalCount = rows.getLong(rows.getColumnIndex('total_count'));
        book.learnedCount = rows.getLong(rows.getColumnIndex('learned_count'));
        books.push(book);
      }
    } finally {
      rows.close();
    }
    return books;
  }

  private readWord(rows: relationalStore.ResultSet): Word {
    const word = new Word();
    word.id = rows.getLong(rows.getColumnIndex('id'));
    word.word = rows.getString(rows.getColumnIndex('word'));
    word.phonetic = rows.getString(rows.getColumnIndex('phonetic'));
    word.meaning = rows.getString(rows.getColumnIndex('meaning'));
    word.example = rows.getString(rows.getColumnIndex('example'));
    word.translation = rows.getString(rows.getColumnIndex('translation'));
    const sourceColumn = rows.columnNames.indexOf('source_book_id');
    if (sourceColumn >= 0) {
      word.sourceBookId = rows.getString(sourceColumn);
    }
    return word;
  }

  private scopedWordColumns(): string {
    return "w.id,COALESCE(i.override_word,w.word) AS word,COALESCE(i.override_phonetic,w.phonetic) AS phonetic,COALESCE(i.override_meaning,w.meaning) AS meaning,COALESCE(i.override_example,w.example) AS example,COALESCE(i.override_translation,w.translation) AS translation,COALESCE(i.book_id,'') AS source_book_id";
  }

  async queryWords(sql: string, args: relationalStore.ValueType[] = []): Promise<Word[]> {
    const rows = await this.store().querySql(sql, args);
    const words: Word[] = [];
    try {
      while (rows.goToNextRow()) {
        words.push(this.readWord(rows));
      }
    } finally {
      rows.close();
    }
    return words;
  }

  async getWord(id: number): Promise<Word> {
    const words = await this.queryWords('SELECT * FROM word WHERE id=?', [id]);
    if (words.length === 0) {
      throw new Error('这个单词暂时不可用');
    }
    return words[0];
  }

  async getWords(bookId: string, filter: string, query: string, limit: number = 50000): Promise<Word[]> {
    const args: relationalStore.ValueType[] = [];
    let sql = bookId.length > 0 ? `SELECT ${this.scopedWordColumns()} FROM word w JOIN word_book_item i ON w.id=i.word_id LEFT JOIN word_progress p ON w.id=p.word_id WHERE i.book_id=?` :
      'SELECT w.* FROM word w LEFT JOIN word_progress p ON w.id=p.word_id WHERE 1=1';
    if (bookId.length > 0) {
      args.push(bookId);
    }
    if (filter === 'favorites') {
      sql += ' AND p.favorite=1';
    } else if (filter === 'new') {
      sql += ' AND p.is_new_word=1';
    }
    if (query.trim().length > 0) {
      const needle = query.trim().replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
      sql += bookId.length > 0 ? " AND (COALESCE(i.override_word,w.word) LIKE ? ESCAPE '\\' OR COALESCE(i.override_meaning,w.meaning) LIKE ? ESCAPE '\\')" :
        " AND (w.word LIKE ? ESCAPE '\\' OR w.meaning LIKE ? ESCAPE '\\')";
      args.push(`${needle}%`);
      args.push(`%${needle}%`);
    }
    sql += ' ORDER BY w.word COLLATE NOCASE,w.id LIMIT ?';
    args.push(Math.max(1, Math.min(50000, limit)));
    return this.queryWords(sql, args);
  }

  private learnedHistoryJoin(): string {
    return "LEFT JOIN (SELECT word_id,MIN(review_at) AS first_learned_at FROM review_record WHERE item_type='new' GROUP BY word_id) f ON w.id=f.word_id";
  }

  /** Only the first new-word record establishes a learning date; later reviews never move it. */
  async getLearnedDates(): Promise<LearnedDate[]> {
    const rows = await this.store().querySql(`SELECT COALESCE(f.first_learned_at,0) AS first_learned_at FROM word w JOIN word_progress p ON w.id=p.word_id ${this.learnedHistoryJoin()} WHERE p.review_count>0`);
    const grouped = new Map<string, number>();
    try {
      while (rows.goToNextRow()) {
        const firstLearnedAt = rows.getDouble(0);
        const validTimestamp = Number.isFinite(firstLearnedAt) && firstLearnedAt > 0 &&
          firstLearnedAt <= 8640000000000000;
        const key = validTimestamp ? dateKey(firstLearnedAt) : '';
        grouped.set(key, (grouped.get(key) || 0) + 1);
      }
    } finally {
      rows.close();
    }
    const dates: LearnedDate[] = [];
    for (const key of grouped.keys()) {
      const group = new LearnedDate();
      group.date = key;
      group.count = grouped.get(key) || 0;
      dates.push(group);
    }
    dates.sort((left: LearnedDate, right: LearnedDate) => {
      if (left.date === right.date) {
        return 0;
      }
      if (left.date.length === 0) {
        return 1;
      }
      if (right.date.length === 0) {
        return -1;
      }
      return left.date > right.date ? -1 : 1;
    });
    return dates;
  }

  private learnedDateRange(date: string): number[] {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return [];
    }
    const year = Number(date.slice(0, 4));
    const month = Number(date.slice(5, 7));
    const day = Number(date.slice(8, 10));
    const parsed = new Date(0);
    parsed.setHours(0, 0, 0, 0);
    // setFullYear also handles years below 100 without Date's 1900 offset.
    parsed.setFullYear(year, month - 1, day);
    if (!Number.isFinite(parsed.getTime()) || parsed.getFullYear() !== year ||
      parsed.getMonth() !== month - 1 || parsed.getDate() !== day || dateKey(parsed.getTime()) !== date) {
      return [];
    }
    const start = dayStart(parsed.getTime());
    const next = new Date(start);
    next.setDate(next.getDate() + 1);
    return [start, next.getTime()];
  }

  async getLearnedWords(date: string, query: string = '', offset: number = 0, limit: number = 50,
    bookId: string = ''): Promise<LearnedWord[]> {
    const args: relationalStore.ValueType[] = [bookId];
    let sql = `SELECT ${this.scopedWordColumns()},CASE WHEN f.first_learned_at>0 AND f.first_learned_at<=8640000000000000 THEN f.first_learned_at ELSE 0 END AS first_learned_at,p.strength FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? ${this.learnedHistoryJoin()} WHERE p.review_count>0`;
    if (date.length === 0) {
      sql += ' AND (f.first_learned_at IS NULL OR f.first_learned_at<=0 OR f.first_learned_at>8640000000000000)';
    } else {
      const range = this.learnedDateRange(date);
      if (range.length === 0) {
        throw new Error('请选择有效的学习日期');
      }
      sql += ' AND f.first_learned_at>0 AND f.first_learned_at<=8640000000000000 AND f.first_learned_at>=? AND f.first_learned_at<?';
      args.push(range[0]);
      args.push(range[1]);
    }
    if (query.trim().length > 0) {
      const needle = query.trim().replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
      sql += " AND (COALESCE(i.override_word,w.word) LIKE ? ESCAPE '\\' OR COALESCE(i.override_meaning,w.meaning) LIKE ? ESCAPE '\\')";
      args.push(`${needle}%`);
      args.push(`%${needle}%`);
    }
    const pageSize = Math.max(1, Math.min(100, Math.floor(Number.isFinite(limit) ? limit : 50)));
    const pageOffset = Math.max(0, Math.min(Number.MAX_SAFE_INTEGER,
      Math.floor(Number.isFinite(offset) ? offset : 0)));
    sql += ' ORDER BY first_learned_at DESC,w.id DESC LIMIT ? OFFSET ?';
    args.push(pageSize);
    args.push(pageOffset);
    const rows = await this.store().querySql(sql, args);
    const learned: LearnedWord[] = [];
    try {
      while (rows.goToNextRow()) {
        const item = new LearnedWord();
        item.word = this.readWord(rows);
        const firstLearnedAt = rows.getDouble(rows.getColumnIndex('first_learned_at'));
        item.firstLearnedAt = Number.isFinite(firstLearnedAt) && firstLearnedAt > 0 &&
          firstLearnedAt <= 8640000000000000 ? firstLearnedAt : 0;
        item.strength = rows.getLong(rows.getColumnIndex('strength'));
        learned.push(item);
      }
    } finally {
      rows.close();
    }
    return learned;
  }

  /** The challenge is practice only: sampling leaves all learning and review progress untouched. */
  async getChallengeWords(limit: number = 10, bookId: string = ''): Promise<Word[]> {
    const count = Math.max(1, Math.min(1000, Math.floor(Number.isFinite(limit) ? limit : 10)));
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE p.review_count>0 AND LENGTH(TRIM(COALESCE(i.override_meaning,w.meaning)))>0 ORDER BY RANDOM() LIMIT ?`,
      [bookId, count]);
  }

  async getUnlearned(bookId: string, limit: number): Promise<Word[]> {
    if (limit <= 0) {
      return [];
    }
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w LEFT JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE COALESCE(p.review_count,0)=0 AND (p.is_new_word=1 OR i.word_id IS NOT NULL) ORDER BY COALESCE(p.is_new_word,0) DESC,COALESCE(i.order_index,0) ASC,w.id LIMIT ?`,
      [bookId, limit]);
  }

  async countUnlearned(bookId: string): Promise<number> {
    return this.scalar('SELECT COUNT(*) FROM word w LEFT JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE COALESCE(p.review_count,0)=0 AND (p.is_new_word=1 OR i.word_id IS NOT NULL)', [bookId]);
  }

  async getDue(now: number, limit: number, exam: boolean = false, bookId: string = '', buffered: boolean = false): Promise<Word[]> {
    if (limit <= 0) {
      return [];
    }
    const order = buffered ? 'p.strength ASC,p.consecutive_failures DESC,p.next_review_at ASC' : exam ? 'p.wrong_count DESC,p.strength ASC,p.next_review_at ASC' :
      'p.consecutive_failures DESC,p.next_review_at ASC,p.strength ASC';
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE p.review_count>0 AND p.next_review_at<=? ORDER BY ${order} LIMIT ?`, [bookId, now, limit]);
  }

  async getDailyWord(bookId: string, offset: number): Promise<Word[]> {
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_book_item i ON w.id=i.word_id WHERE i.book_id=? ORDER BY i.order_index LIMIT 1 OFFSET ?`, [bookId, offset]);
  }

  async getBookWord(bookId: string, wordId: number): Promise<Word> {
    const words = await this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_book_item i ON w.id=i.word_id WHERE i.book_id=? AND i.word_id=?`, [bookId, wordId]);
    if (words.length === 0) {
      throw new Error('词书中没有这个单词');
    }
    return words[0];
  }

  private async assertCustomBook(bookId: string): Promise<void> {
    const books = await this.getBooks();
    const book = books.find((item: WordBook) => item.id === bookId);
    if (!book || book.category !== 'custom') {
      throw new Error('只能编辑自己的自定义词书');
    }
  }

  async renameBook(bookId: string, name: string): Promise<void> {
    await this.assertCustomBook(bookId);
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('UPDATE word_book SET name=? WHERE id=?', [name, bookId]);
    });
  }

  async updateBookWord(bookId: string, wordId: number, edited: Word): Promise<number> {
    await this.assertCustomBook(bookId);
    await this.getBookWord(bookId, wordId);
    let targetId = wordId;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const oldRows = await store.querySql('SELECT order_index FROM word_book_item WHERE book_id=? AND word_id=?', [bookId, wordId]);
      let order = 0;
      try {
        if (!oldRows.goToFirstRow()) {
          throw new Error('词条已发生变化，请重新打开');
        }
        order = oldRows.getLong(0);
      } finally {
        oldRows.close();
      }
      const identity = edited.word.trim().toLowerCase();
      await store.executeSql('INSERT OR IGNORE INTO word(word,phonetic,meaning,example,translation) VALUES(?,?,?,?,?)',
        [identity, edited.phonetic, edited.meaning, edited.example, edited.translation]);
      const rows = await store.querySql('SELECT id FROM word WHERE word=? COLLATE NOCASE', [identity]);
      try {
        if (!rows.goToFirstRow()) {
          throw new Error('词条保存失败');
        }
        targetId = rows.getLong(0);
      } finally {
        rows.close();
      }
      if (targetId !== wordId) {
        const conflict = await store.querySql('SELECT 1 FROM word_book_item WHERE book_id=? AND word_id=?',
          [bookId, targetId]);
        try {
          if (conflict.goToFirstRow()) {
            throw new Error('这本词书已经有这个单词，请编辑原有词条或使用其他词头');
          }
        } finally {
          conflict.close();
        }
        await store.executeSql('DELETE FROM word_book_item WHERE book_id=? AND word_id=?', [bookId, wordId]);
      }
      await store.executeSql('INSERT INTO word_book_item(book_id,word_id,order_index,override_word,override_phonetic,override_meaning,override_example,override_translation) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(book_id,word_id) DO UPDATE SET override_word=excluded.override_word,override_phonetic=excluded.override_phonetic,override_meaning=excluded.override_meaning,override_example=excluded.override_example,override_translation=excluded.override_translation',
        [bookId, targetId, order, edited.word.trim(), edited.phonetic, edited.meaning, edited.example, edited.translation]);
    });
    return targetId;
  }

  async countDue(now: number): Promise<number> {
    return this.scalar('SELECT COUNT(*) FROM word_progress WHERE review_count>0 AND next_review_at<=?', [now]);
  }

  private readProgress(rows: relationalStore.ResultSet): WordProgress {
    const progress = new WordProgress();
    progress.wordId = rows.getLong(rows.getColumnIndex('word_id'));
    progress.strength = rows.getLong(rows.getColumnIndex('strength'));
    progress.level = rows.getLong(rows.getColumnIndex('level'));
    progress.nextReviewAt = rows.getLong(rows.getColumnIndex('next_review_at'));
    progress.lastReviewAt = rows.getLong(rows.getColumnIndex('last_review_at'));
    progress.reviewCount = rows.getLong(rows.getColumnIndex('review_count'));
    progress.wrongCount = rows.getLong(rows.getColumnIndex('wrong_count'));
    progress.favorite = rows.getLong(rows.getColumnIndex('favorite')) === 1;
    progress.isNewWord = rows.getLong(rows.getColumnIndex('is_new_word')) === 1;
    progress.hesitationCount = rows.getLong(rows.getColumnIndex('hesitation_count'));
    progress.lastResponseMs = rows.getLong(rows.getColumnIndex('last_response_ms'));
    progress.consecutiveFailures = rows.getLong(rows.getColumnIndex('consecutive_failures'));
    progress.consecutiveKnown = rows.getLong(rows.getColumnIndex('consecutive_known'));
    return progress;
  }

  async getProgress(id: number): Promise<WordProgress> {
    const rows = await this.store().querySql('SELECT * FROM word_progress WHERE word_id=?', [id]);
    try {
      if (rows.goToFirstRow()) {
        return this.readProgress(rows);
      }
    } finally {
      rows.close();
    }
    const progress = new WordProgress();
    progress.wordId = id;
    return progress;
  }

  async setFlag(id: number, favorite: boolean, value: boolean): Promise<void> {
    await this.getWord(id);
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT OR IGNORE INTO word_progress(word_id) VALUES(?)', [id]);
      await store.executeSql(favorite ? 'UPDATE word_progress SET favorite=? WHERE word_id=?' :
        'UPDATE word_progress SET is_new_word=? WHERE word_id=?', [value ? 1 : 0, id]);
    });
  }

  private readRecord(rows: relationalStore.ResultSet): ReviewRecord {
    const record = new ReviewRecord();
    record.itemType = rows.getString(rows.getColumnIndex('item_type'));
    record.id = rows.getLong(rows.getColumnIndex('id'));
    record.wordId = rows.getLong(rows.getColumnIndex('word_id'));
    record.result = rows.getLong(rows.getColumnIndex('result'));
    record.reviewAt = rows.getLong(rows.getColumnIndex('review_at'));
    record.responseMs = rows.getLong(rows.getColumnIndex('response_ms'));
    record.previousLevel = rows.getLong(rows.getColumnIndex('previous_level'));
    record.nextLevel = rows.getLong(rows.getColumnIndex('next_level'));
    record.previousStrength = rows.getLong(rows.getColumnIndex('previous_strength'));
    record.nextStrength = rows.getLong(rows.getColumnIndex('next_strength'));
    return record;
  }

  async getHistory(id: number): Promise<ReviewRecord[]> {
    const rows = await this.store().querySql('SELECT * FROM review_record WHERE word_id=? ORDER BY review_at DESC,id DESC LIMIT 5', [id]);
    const records: ReviewRecord[] = [];
    try {
      while (rows.goToNextRow()) {
        records.push(this.readRecord(rows));
      }
    } finally {
      rows.close();
    }
    return records;
  }

  async getPlan(date: string): Promise<DailyPlan | undefined> {
    const rows = await this.store().querySql('SELECT * FROM daily_plan WHERE date=?', [date]);
    try {
      return rows.goToFirstRow() ? this.readPlan(rows) : undefined;
    } finally {
      rows.close();
    }
  }

  private readPlan(rows: relationalStore.ResultSet): DailyPlan {
    const plan = new DailyPlan();
    plan.date = rows.getString(rows.getColumnIndex('date'));
    plan.newTarget = rows.getLong(rows.getColumnIndex('new_target'));
    plan.reviewTarget = rows.getLong(rows.getColumnIndex('review_target'));
    plan.newDone = rows.getLong(rows.getColumnIndex('new_done'));
    plan.reviewDone = rows.getLong(rows.getColumnIndex('review_done'));
    plan.estimatedMinutes = rows.getLong(rows.getColumnIndex('estimated_minutes'));
    plan.budget = rows.getString(rows.getColumnIndex('budget'));
    plan.backlogCount = rows.getLong(rows.getColumnIndex('backlog_count'));
    return plan;
  }

  async savePlan(plan: DailyPlan): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO daily_plan(date,new_target,review_target,new_done,review_done,estimated_minutes,budget,backlog_count) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET new_target=excluded.new_target,review_target=excluded.review_target,estimated_minutes=excluded.estimated_minutes,budget=excluded.budget,backlog_count=excluded.backlog_count',
        [plan.date, plan.newTarget, plan.reviewTarget, plan.newDone, plan.reviewDone, plan.estimatedMinutes, plan.budget, plan.backlogCount]);
    });
  }

  async loadSession(): Promise<StudySession> {
    const rows = await this.store().querySql('SELECT payload FROM study_session WHERE id=1');
    try {
      if (rows.goToFirstRow()) {
        const session = JSON.parse(rows.getString(0)) as StudySession;
        if (Array.isArray(session.items) && Number.isInteger(session.index) && session.index >= 0 &&
          session.index <= session.items.length && session.items.length <= 250 &&
          Number.isInteger(session.completed) && session.completed === session.index &&
          Number.isFinite(session.startedAt) && typeof session.mode === 'string' &&
          session.items.every((item: StudyItem) => item !== null && typeof item === 'object' &&
            item.word !== null && typeof item.word === 'object' && Number.isInteger(item.word.id) &&
            item.word.id > 0 && typeof item.word.word === 'string' && typeof item.word.phonetic === 'string' &&
            typeof item.word.meaning === 'string' && typeof item.word.example === 'string' &&
            typeof item.word.translation === 'string' && ['new', 'review'].indexOf(item.type) >= 0)) {
          return session;
        }
      }
    } catch (_) {
      // An invalid interrupted session cannot erase the committed progress or records.
    } finally {
      rows.close();
    }
    return new StudySession();
  }

  async saveSession(session: StudySession): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('DELETE FROM review_undo');
      await this.writeSession(store, session);
    });
  }

  private async writeSession(store: DatabaseTransaction, session: StudySession): Promise<void> {
    await store.executeSql('INSERT OR REPLACE INTO study_session(id,payload) VALUES(1,?)', [JSON.stringify(session)]);
  }

  /** Answer and resume cursor are one durable unit, preventing repeats after an interrupted save. */
  async record(previous: WordProgress, next: WordProgress, result: ReviewResult,
    responseMs: number, session: StudySession, now: number, extraNewGoal: number = 25): Promise<void> {
    const date = dateKey(now);
    const isNew = previous.reviewCount === 0;
    const duration = Math.max(0, Math.min(300000, Math.floor(Number.isFinite(responseMs) ? responseMs : 0)));
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const undo = new ReviewUndo();
      undo.wordId = next.wordId; undo.date = date; undo.glowDate = shiftedDate(now, -1);
      const oldProgress = await store.querySql('SELECT * FROM word_progress WHERE word_id=?', [next.wordId]);
      try { if (oldProgress.goToFirstRow()) { undo.progress = this.readProgress(oldProgress); } }
      finally { oldProgress.close(); }
      const oldPlan = await store.querySql('SELECT * FROM daily_plan WHERE date=?', [date]);
      try { if (oldPlan.goToFirstRow()) { undo.plan = this.readPlan(oldPlan); } }
      finally { oldPlan.close(); }
      const oldDay = await store.querySql('SELECT * FROM daily_summary WHERE date=?', [date]);
      try { if (oldDay.goToFirstRow()) { undo.day = this.readDay(oldDay); } }
      finally { oldDay.close(); }
      const oldMastered = await store.querySql('SELECT 1 FROM mastered_word WHERE word_id=?', [next.wordId]);
      try { undo.mastered = oldMastered.goToFirstRow(); } finally { oldMastered.close(); }
      const oldGlow = await store.querySql('SELECT * FROM daily_glow WHERE date=?', [undo.glowDate]);
      try {
        if (oldGlow.goToFirstRow()) {
          const glow = new GlowRecord(); glow.date = oldGlow.getString(0);
          glow.earnedOn = oldGlow.getString(1); glow.reason = oldGlow.getString(2); undo.glow = glow;
        }
      } finally { oldGlow.close(); }
      const oldSession = await store.querySql('SELECT payload FROM study_session WHERE id=1');
      try {
        undo.sessionExists = oldSession.goToFirstRow();
        if (undo.sessionExists) { undo.session = JSON.parse(oldSession.getString(0)) as StudySession; }
        else {
          undo.session = JSON.parse(JSON.stringify(session)) as StudySession;
          undo.session.index = Math.max(0, session.index - 1); undo.session.completed = undo.session.index;
        }
      } finally { oldSession.close(); }
      await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count,wrong_count,favorite,is_new_word,hesitation_count,last_response_ms,consecutive_failures,consecutive_known) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(word_id) DO UPDATE SET strength=excluded.strength,level=excluded.level,next_review_at=excluded.next_review_at,last_review_at=excluded.last_review_at,review_count=excluded.review_count,wrong_count=excluded.wrong_count,hesitation_count=excluded.hesitation_count,last_response_ms=excluded.last_response_ms,consecutive_failures=excluded.consecutive_failures,consecutive_known=excluded.consecutive_known',
        [next.wordId, next.strength, next.level, next.nextReviewAt, next.lastReviewAt, next.reviewCount,
          next.wrongCount, next.favorite ? 1 : 0, next.isNewWord ? 1 : 0, next.hesitationCount,
          next.lastResponseMs, next.consecutiveFailures, next.consecutiveKnown]);
      await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
        [next.wordId, result, now, duration, previous.level, next.level, previous.strength, next.strength,
          isNew ? 'new' : 'review']);
      const inserted = await store.querySql('SELECT last_insert_rowid()');
      try { undo.recordId = inserted.goToFirstRow() ? inserted.getLong(0) : 0; }
      finally { inserted.close(); }
      if (next.strength >= 75) {
        await store.executeSql('INSERT OR IGNORE INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)',
          [next.wordId, now]);
      }
      await store.executeSql(isNew ? 'UPDATE daily_plan SET new_done=new_done+1 WHERE date=?' :
        'UPDATE daily_plan SET review_done=review_done+1 WHERE date=?', [date]);
      await store.executeSql('INSERT INTO daily_summary(date,new_count,review_count,known_count,total_count,duration_ms) VALUES(?,?,?,?,1,?) ON CONFLICT(date) DO UPDATE SET new_count=new_count+excluded.new_count,review_count=review_count+excluded.review_count,known_count=known_count+excluded.known_count,total_count=total_count+1,duration_ms=duration_ms+excluded.duration_ms',
        [date, isNew ? 1 : 0, isNew ? 0 : 1, !isNew && result === ReviewResult.KNOW ? 1 : 0, duration]);
      await this.restoreYesterdayGlow(store, now, extraNewGoal);
      await this.writeSession(store, session);
      await store.executeSql('INSERT OR REPLACE INTO review_undo(id,payload) VALUES(1,?)', [JSON.stringify(undo)]);
    });
  }

  async clearUndo(): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => { await store.executeSql('DELETE FROM review_undo'); });
  }

  async undoLast(): Promise<StudySession | undefined> {
    let restored: StudySession | undefined = undefined;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const rows = await store.querySql('SELECT payload FROM review_undo WHERE id=1');
      let undo: ReviewUndo;
      try {
        if (!rows.goToFirstRow()) { return; }
        undo = JSON.parse(rows.getString(0)) as ReviewUndo;
      } finally { rows.close(); }
      await store.executeSql('DELETE FROM review_record WHERE id=? AND word_id=?', [undo.recordId, undo.wordId]);
      if (undo.progress) {
        const p = undo.progress;
        await store.executeSql('INSERT OR REPLACE INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count,wrong_count,favorite,is_new_word,hesitation_count,last_response_ms,consecutive_failures,consecutive_known) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [p.wordId,p.strength,p.level,p.nextReviewAt,p.lastReviewAt,p.reviewCount,p.wrongCount,p.favorite?1:0,p.isNewWord?1:0,p.hesitationCount,p.lastResponseMs,p.consecutiveFailures,p.consecutiveKnown]);
      } else { await store.executeSql('DELETE FROM word_progress WHERE word_id=?', [undo.wordId]); }
      await store.executeSql('DELETE FROM daily_plan WHERE date=?', [undo.date]);
      if (undo.plan) {
        const p = undo.plan;
        await store.executeSql('INSERT INTO daily_plan(date,new_target,review_target,new_done,review_done,estimated_minutes,budget,backlog_count) VALUES(?,?,?,?,?,?,?,?)',
          [p.date,p.newTarget,p.reviewTarget,p.newDone,p.reviewDone,p.estimatedMinutes,p.budget,p.backlogCount]);
      }
      await store.executeSql('DELETE FROM daily_summary WHERE date=?', [undo.date]);
      if (undo.day) {
        const d = undo.day;
        await store.executeSql('INSERT INTO daily_summary(date,new_count,review_count,known_count,total_count,duration_ms) VALUES(?,?,?,?,?,?)',
          [d.date,d.newCount,d.reviewCount,d.knownCount,d.totalCount,d.durationMs]);
      }
      if (!undo.mastered) { await store.executeSql('DELETE FROM mastered_word WHERE word_id=?', [undo.wordId]); }
      await store.executeSql('DELETE FROM daily_glow WHERE date=?', [undo.glowDate]);
      if (undo.glow) {
        const g = undo.glow;
        await store.executeSql('INSERT INTO daily_glow(date,earned_on,reason) VALUES(?,?,?)',[g.date,g.earnedOn,g.reason]);
      }
      if (undo.sessionExists) { await this.writeSession(store, undo.session); }
      else { await store.executeSql('DELETE FROM study_session'); }
      await store.executeSql('DELETE FROM review_undo');
      restored = undo.session;
    });
    return restored;
  }

  async getMistakes(offset: number = 0, limit: number = 50): Promise<MistakeWord[]> {
    const rows = await this.store().querySql('SELECT w.*,p.wrong_count,p.last_review_at,p.strength FROM word w JOIN word_progress p ON w.id=p.word_id WHERE p.wrong_count>0 AND p.strength<75 ORDER BY p.wrong_count DESC,p.last_review_at DESC,w.id LIMIT ? OFFSET ?',
      [Math.max(1,Math.min(50,Math.floor(limit))),Math.max(0,Math.floor(offset))]);
    const result: MistakeWord[] = [];
    try {
      while (rows.goToNextRow()) {
        const item = new MistakeWord(); item.word = this.readWord(rows);
        item.wrongCount = rows.getLong(rows.getColumnIndex('wrong_count'));
        item.lastReviewAt = rows.getLong(rows.getColumnIndex('last_review_at'));
        item.strength = rows.getLong(rows.getColumnIndex('strength')); result.push(item);
      }
    } finally { rows.close(); }
    return result;
  }

  private readDay(rows: relationalStore.ResultSet): DaySummary {
    const day = new DaySummary();
    day.date = rows.getString(rows.getColumnIndex('date'));
    day.newCount = rows.getLong(rows.getColumnIndex('new_count'));
    day.reviewCount = rows.getLong(rows.getColumnIndex('review_count'));
    day.knownCount = rows.getLong(rows.getColumnIndex('known_count'));
    day.totalCount = rows.getLong(rows.getColumnIndex('total_count'));
    day.durationMs = rows.getLong(rows.getColumnIndex('duration_ms'));
    return day;
  }

  async getDays(since: string = ''): Promise<DaySummary[]> {
    const rows = await this.store().querySql('SELECT * FROM daily_summary WHERE date>=? ORDER BY date ASC', [since]);
    const days: DaySummary[] = [];
    try {
      while (rows.goToNextRow()) {
        days.push(this.readDay(rows));
      }
    } finally {
      rows.close();
    }
    return days;
  }

  async getStatistics(now: number): Promise<Statistics> {
    const stats = new Statistics();
    stats.totalLearned = await this.scalar('SELECT COUNT(*) FROM word_progress WHERE review_count>0');
    stats.mastered = await this.scalar('SELECT COUNT(*) FROM word_progress WHERE review_count>0 AND strength>=75');
    stats.weekMastered = await this.scalar('SELECT COUNT(*) FROM mastered_word WHERE first_mastered_at>=? AND first_mastered_at<=?', [weekStart(now), now]);
    for (let index = 0; index < 4; index++) {
      stats.strengthCounts[index] = await this.scalar('SELECT COUNT(*) FROM word_progress WHERE review_count>0 AND strength>=? AND strength<?', [index * 25, index === 3 ? 101 : (index + 1) * 25]);
    }
    const actualDays = await this.getDays();
    const glowRecords = await this.getGlowRecords();
    stats.glowDays = glowRecords.map((item: GlowRecord) => item.date);
    const byDate = new Map<string, DaySummary>();
    for (const day of actualDays) {
      byDate.set(day.date, day);
    }
    // Zero-activity dates belong on the calendar as well as days with persisted events.
    for (let offset = -27; offset <= 0; offset++) {
      const key = shiftedDate(now, offset);
      const saved = byDate.get(key);
      const day = saved || new DaySummary();
      day.date = key;
      day.glowing = stats.glowDays.indexOf(key) >= 0;
      stats.days.push(day);
    }
    const recent = actualDays.filter((day: DaySummary) => day.date >= dateKey(weekStart(now)) && day.date <= dateKey(now));
    let known = 0;
    let reviews = 0;
    for (const day of recent) {
      known += day.knownCount;
      reviews += day.reviewCount;
    }
    stats.successRate = reviews > 0 ? Math.round(known / reviews * 100) : 0;
    const activeDates = new Set<string>();
    for (const day of actualDays) {
      if (day.totalCount > 0) {
        activeDates.add(day.date);
      }
    }
    let offset = activeDates.has(dateKey(now)) ? 0 : -1;
    while (activeDates.has(shiftedDate(now, offset))) {
      stats.streak += 1;
      offset -= 1;
    }
    return stats;
  }

  async backupBookWords(bookId: string): Promise<Word[]> {
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_book_item i ON w.id=i.word_id WHERE i.book_id=? ORDER BY i.order_index,w.id`, [bookId]);
  }

  backupNonBuiltinWords(): Promise<Word[]> {
    return this.queryWords("SELECT w.* FROM word w WHERE w.id NOT IN(SELECT i.word_id FROM word_book_item i JOIN word_book b ON i.book_id=b.id WHERE b.category<>'custom') ORDER BY w.id");
  }

  async allWords(): Promise<Word[]> {
    const rows = await this.store().querySql('SELECT * FROM word ORDER BY id');
    const words: Word[] = [];
    try { while (rows.goToNextRow()) { words.push(this.readWord(rows)); } }
    finally { rows.close(); }
    return words;
  }

  async allMasteredWords(): Promise<MasteredWord[]> {
    const rows = await this.store().querySql('SELECT word_id,first_mastered_at FROM mastered_word ORDER BY word_id');
    const result: MasteredWord[] = [];
    try {
      while (rows.goToNextRow()) {
        const item = new MasteredWord();
        item.wordId = rows.getLong(0); item.firstMasteredAt = rows.getLong(1); result.push(item);
      }
    } finally { rows.close(); }
    return result;
  }

  private async restoreBatch(store: DatabaseTransaction, table: string,
    rows: relationalStore.ValuesBucket[]): Promise<void> {
    for (let offset = 0; offset < rows.length; offset += 500) {
      await store.batchInsert(table, rows.slice(offset, offset + 500));
    }
  }

  /** The entire replacement, including settings, is one durable transaction. */
  async restoreBackup(backup: DataExport): Promise<number> {
    let skipped = 0;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const idMap = new Map<number, number>();
      for (const book of backup.books.filter((book: DictionaryBook) => book.category === 'custom')) {
        if (!book.id.startsWith('custom_')) { throw new Error('自定义词书编号有误'); }
        for (const word of book.words) {
          await store.executeSql('INSERT OR IGNORE INTO word(word,phonetic,meaning,example,translation) VALUES(?,?,?,?,?)',
            [word.word.trim().toLowerCase(), word.phonetic, word.meaning, word.example, word.translation]);
        }
      }
      const builtinIds = new Set<number>();
      backup.books.filter((book: DictionaryBook) => book.category !== 'custom').forEach((book: DictionaryBook) => {
        book.words.forEach((word: Word) => { builtinIds.add(word.id); });
      });
      for (const word of backup.words) {
        if (word.meaning.length > 0 && !builtinIds.has(word.id)) {
          await store.executeSql('INSERT OR IGNORE INTO word(word,phonetic,meaning,example,translation) VALUES(?,?,?,?,?)',
            [word.word.trim().toLowerCase(),word.phonetic,word.meaning,word.example,word.translation]);
        }
      }
      const available = await this.wordIdentities(store);
      for (const word of backup.words) {
        const localId = available.get(word.word.trim().toLowerCase());
        if (localId !== undefined) { idMap.set(word.id, localId); }
        else { skipped++; }
      }
      backup.progress = backup.progress.filter((p: WordProgress) => idMap.has(p.wordId));
      backup.progress.forEach((p: WordProgress) => { p.wordId = idMap.get(p.wordId) || 0; });
      backup.records = backup.records.filter((r: ReviewRecord) => idMap.has(r.wordId));
      backup.records.forEach((r: ReviewRecord) => { r.wordId = idMap.get(r.wordId) || 0; });
      backup.masteredWords = backup.masteredWords.filter((m: MasteredWord) => idMap.has(m.wordId));
      backup.masteredWords.forEach((m: MasteredWord) => { m.wordId = idMap.get(m.wordId) || 0; });
      const oldIndex = backup.session.index;
      backup.session.index = backup.session.items.slice(0, oldIndex).filter((item: StudyItem) => idMap.has(item.word.id)).length;
      backup.session.completed = backup.session.index;
      backup.session.items = backup.session.items.filter((item: StudyItem) => idMap.has(item.word.id));
      backup.session.items.forEach((item: StudyItem) => { item.word.id = idMap.get(item.word.id) || 0; });
      for (const table of ['review_undo', 'study_session', 'review_record', 'word_progress', 'mastered_word',
        'daily_plan', 'daily_summary', 'practice_result', 'daily_glow']) {
        await store.executeSql(`DELETE FROM ${table}`);
      }
      await store.executeSql("DELETE FROM word_book_item WHERE book_id IN(SELECT id FROM word_book WHERE category='custom')");
      await store.executeSql("DELETE FROM word_book WHERE category='custom'");
      for (const book of backup.books.filter((book: DictionaryBook) => book.category === 'custom')) {
        await store.executeSql('INSERT INTO word_book(id,name,category,description) VALUES(?,?,?,?)',
          [book.id, book.name, book.category, book.description]);
        await this.restoreBatch(store, 'word_book_item', book.words.map((word: Word, index: number): relationalStore.ValuesBucket => {
          return { book_id: book.id, word_id: idMap.get(word.id) || 0, order_index: index, override_word: word.word,
            override_phonetic: word.phonetic, override_meaning: word.meaning, override_example: word.example,
            override_translation: word.translation };
        }));
      }
      await this.restoreBatch(store, 'word_progress', backup.progress.map((p: WordProgress): relationalStore.ValuesBucket => {
        return { word_id: p.wordId, strength: p.strength, level: p.level, next_review_at: p.nextReviewAt,
          last_review_at: p.lastReviewAt, review_count: p.reviewCount, wrong_count: p.wrongCount,
          favorite: p.favorite ? 1 : 0, is_new_word: p.isNewWord ? 1 : 0, hesitation_count: p.hesitationCount,
          last_response_ms: p.lastResponseMs, consecutive_failures: p.consecutiveFailures, consecutive_known: p.consecutiveKnown };
      }));
      await this.restoreBatch(store, 'review_record', backup.records.map((r: ReviewRecord): relationalStore.ValuesBucket => {
        return { id: r.id, word_id: r.wordId, result: r.result, review_at: r.reviewAt, response_ms: r.responseMs,
          previous_level: r.previousLevel, next_level: r.nextLevel, previous_strength: r.previousStrength,
          next_strength: r.nextStrength, item_type: r.itemType };
      }));
      await this.restoreBatch(store, 'mastered_word', backup.masteredWords.map((m: MasteredWord): relationalStore.ValuesBucket => {
        return { word_id: m.wordId, first_mastered_at: m.firstMasteredAt };
      }));
      await this.restoreBatch(store, 'daily_plan', backup.plans.map((p: DailyPlan): relationalStore.ValuesBucket => {
        return { date: p.date, new_target: p.newTarget, review_target: p.reviewTarget, new_done: p.newDone,
          review_done: p.reviewDone, estimated_minutes: p.estimatedMinutes, budget: p.budget, backlog_count: p.backlogCount };
      }));
      await this.restoreBatch(store, 'daily_summary', backup.days.map((d: DaySummary): relationalStore.ValuesBucket => {
        return { date: d.date, new_count: d.newCount, review_count: d.reviewCount, known_count: d.knownCount,
          total_count: d.totalCount, duration_ms: d.durationMs };
      }));
      await this.restoreBatch(store, 'practice_result', backup.practiceResults.map((p: PracticeResult): relationalStore.ValuesBucket => {
        return { id: p.id, mode: p.mode, correct_count: p.correct, total_count: p.total,
          duration_ms: p.durationMs, practiced_at: p.completedAt };
      }));
      await this.restoreBatch(store, 'daily_glow', backup.glowRecords.map((g: GlowRecord): relationalStore.ValuesBucket => {
        return { date: g.date, earned_on: g.earnedOn, reason: g.reason };
      }));
      await ExperienceRepository.restore(store, backup, idMap);
      await this.writeSession(store, backup.session);
      await store.executeSql("INSERT OR REPLACE INTO app_meta(key,value) VALUES('user_settings',?)", [JSON.stringify(backup.settings)]);
      await store.executeSql("INSERT OR REPLACE INTO app_meta(key,value) VALUES('learning_semantics_version','2')");
      await store.executeSql("INSERT OR REPLACE INTO app_meta(key,value) VALUES('adaptive_metrics_version','1')");
    }, true);
    return skipped;
  }

  async allProgress(): Promise<WordProgress[]> {
    const rows = await this.store().querySql('SELECT * FROM word_progress ORDER BY word_id');
    const progress: WordProgress[] = [];
    try {
      while (rows.goToNextRow()) {
        progress.push(this.readProgress(rows));
      }
    } finally {
      rows.close();
    }
    return progress;
  }

  async allRecords(): Promise<ReviewRecord[]> {
    const rows = await this.store().querySql('SELECT * FROM review_record ORDER BY id');
    const records: ReviewRecord[] = [];
    try {
      while (rows.goToNextRow()) {
        records.push(this.readRecord(rows));
      }
    } finally {
      rows.close();
    }
    return records;
  }

  async allPlans(): Promise<DailyPlan[]> {
    const rows = await this.store().querySql('SELECT * FROM daily_plan ORDER BY date');
    const plans: DailyPlan[] = [];
    try {
      while (rows.goToNextRow()) {
        plans.push(this.readPlan(rows));
      }
    } finally {
      rows.close();
    }
    return plans;
  }
  /** Reconstruct only new counters; existing intervals, strength, and raw review records are untouched. */
  async migrateAdaptiveMetrics(): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const meta = await store.querySql("SELECT value FROM app_meta WHERE key='adaptive_metrics_version'");
      let complete = false;
      try {
        complete = meta.goToFirstRow() && meta.getString(0) === '1';
      } finally {
        meta.close();
      }
      if (complete) {
        return;
      }
      const metrics = new Map<number, WordProgress>();
      const rows = await store.querySql('SELECT word_id,result,response_ms FROM review_record ORDER BY id');
      try {
        while (rows.goToNextRow()) {
          const wordId = rows.getLong(0);
          const metric = metrics.get(wordId) || new WordProgress();
          const result = rows.getLong(1);
          metric.lastResponseMs = Math.max(0, rows.getLong(2));
          metric.consecutiveKnown = result === ReviewResult.KNOW ? metric.consecutiveKnown + 1 : 0;
          metric.consecutiveFailures = result === ReviewResult.KNOW ? 0 : metric.consecutiveFailures + 1;
          if (metric.lastResponseMs > 3500 || metric.consecutiveFailures >= 2) {
            metric.hesitationCount += 1;
          }
          metrics.set(wordId, metric);
        }
      } finally {
        rows.close();
      }
      for (const wordId of metrics.keys()) {
        const metric = metrics.get(wordId);
        if (!metric) {
          continue;
        }
        await store.executeSql('UPDATE word_progress SET hesitation_count=?,last_response_ms=?,consecutive_failures=?,consecutive_known=? WHERE word_id=?',
          [metric.hesitationCount, metric.lastResponseMs, metric.consecutiveFailures, metric.consecutiveKnown, wordId]);
      }
      await store.executeSql('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)', ['adaptive_metrics_version', '1']);
    });
  }

  async importEnrichmentSeeds(): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      const versionRows = await store.querySql("SELECT key,value FROM app_meta WHERE key IN('dictionary_version','lexical_enrichment_version')");
      let dictionaryVersion = '0';
      let enrichmentVersion = '';
      try {
        while (versionRows.goToNextRow()) {
          if (versionRows.getString(0) === 'dictionary_version') {
            dictionaryVersion = versionRows.getString(1);
          } else {
            enrichmentVersion = versionRows.getString(1);
          }
        }
      } finally {
        versionRows.close();
      }
      const targetVersion = `1_${dictionaryVersion}`;
      if (enrichmentVersion === targetVersion) {
        return;
      }
      const identities = await this.wordIdentities(store);
      for (const seed of ENRICHMENT_SEEDS) {
        const wordId = identities.get(seed.word);
        if (wordId === undefined) {
          continue;
        }
        await store.executeSql('INSERT OR REPLACE INTO word_enrichment(word_id,core_meanings,collocations) VALUES(?,?,?)',
          [wordId, JSON.stringify(seed.coreMeanings), JSON.stringify(seed.collocations)]);
        if (seed.analysis.length > 0) {
          await store.executeSql('INSERT OR REPLACE INTO word_etymology(word_id,root,prefix,suffix,analysis,family_words) VALUES(?,?,?,?,?,?)',
            [wordId, seed.root, seed.prefix, seed.suffix, seed.analysis, JSON.stringify(seed.family)]);
        }
      }
      for (const seed of CONFUSING_SEEDS) {
        const first = identities.get(seed.first);
        const second = identities.get(seed.second);
        if (first === undefined || second === undefined) {
          continue;
        }
        await store.executeSql('INSERT OR REPLACE INTO confusing_words(word_id,paired_word_id,distinction_note) VALUES(?,?,?)',
          [first, second, seed.note]);
        await store.executeSql('INSERT OR REPLACE INTO confusing_words(word_id,paired_word_id,distinction_note) VALUES(?,?,?)',
          [second, first, seed.note]);
      }
      await store.executeSql('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        ['lexical_enrichment_version', targetVersion]);
    });
  }

  async findWordBySpelling(spelling: string): Promise<Word | undefined> {
    const words = await this.queryWords('SELECT * FROM word WHERE word=? COLLATE NOCASE LIMIT 1', [spelling.trim()]);
    return words.length > 0 ? words[0] : undefined;
  }

  async getWordEnrichment(wordId: number): Promise<WordEnrichment> {
    const enrichment = new WordEnrichment();
    const rows = await this.store().querySql('SELECT core_meanings,collocations FROM word_enrichment WHERE word_id=?', [wordId]);
    try {
      if (rows.goToFirstRow()) {
        enrichment.coreMeanings = JSON.parse(rows.getString(0)) as string[];
        enrichment.collocations = JSON.parse(rows.getString(1)) as string[];
      }
    } finally {
      rows.close();
    }
    let family: string[] = [];
    const etymology = await this.store().querySql('SELECT root,prefix,suffix,analysis,family_words FROM word_etymology WHERE word_id=?', [wordId]);
    try {
      if (etymology.goToFirstRow()) {
        enrichment.root = etymology.getString(0);
        enrichment.prefix = etymology.getString(1);
        enrichment.suffix = etymology.getString(2);
        enrichment.analysis = etymology.getString(3);
        family = JSON.parse(etymology.getString(4)) as string[];
      }
    } finally {
      etymology.close();
    }
    for (const spelling of family) {
      const word = await this.findWordBySpelling(spelling);
      if (word && word.id !== wordId) {
        const relation = new WordRelation();
        relation.word = word;
        const progress = await this.getProgress(word.id);
        relation.strength = progress.strength;
        relation.learned = progress.reviewCount > 0;
        enrichment.familyWords.push(relation);
      }
    }
    const pairs = await this.store().querySql('SELECT paired_word_id,distinction_note FROM confusing_words WHERE word_id=? ORDER BY paired_word_id', [wordId]);
    const pairedIds: number[] = [];
    const notes: string[] = [];
    try {
      while (pairs.goToNextRow()) {
        pairedIds.push(pairs.getLong(0));
        notes.push(pairs.getString(1));
      }
    } finally {
      pairs.close();
    }
    for (let index = 0; index < pairedIds.length; index++) {
      const pair = new ConfusingWord();
      pair.word = await this.getWord(pairedIds[index]);
      pair.note = notes[index];
      enrichment.confusingWords.push(pair);
    }
    return enrichment;
  }

  async getNightWords(now: number, limit: number = 5, bookId: string = ''): Promise<Word[]> {
    const count = Math.max(1, Math.min(5, Math.floor(Number.isFinite(limit) ? limit : 5)));
    const tomorrow = new Date(dayStart(now));
    tomorrow.setDate(tomorrow.getDate() + 1);
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? JOIN (SELECT word_id,COUNT(*) AS misses FROM review_record WHERE review_at>=? AND review_at<? AND result IN(0,1) GROUP BY word_id) r ON w.id=r.word_id WHERE p.review_count>0 ORDER BY r.misses DESC,p.strength ASC,p.last_review_at DESC LIMIT ?`,
      [bookId, dayStart(now), tomorrow.getTime(), count]);
  }

  async getAudioWords(now: number, limit: number = 30, bookId: string = ''): Promise<Word[]> {
    const count = Math.max(1, Math.min(120, Math.floor(Number.isFinite(limit) ? limit : 30)));
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE p.review_count>0 ORDER BY CASE WHEN p.next_review_at<=? THEN 0 ELSE 1 END,p.consecutive_failures DESC,p.strength ASC,p.next_review_at ASC LIMIT ?`,
      [bookId, now, count]);
  }

  async getSpellingWords(limit: number = 5, bookId: string = ''): Promise<Word[]> {
    const count = Math.max(1, Math.min(20, Math.floor(Number.isFinite(limit) ? limit : 5)));
    return this.queryWords(`SELECT ${this.scopedWordColumns()} FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_book_item i ON w.id=i.word_id AND i.book_id=? WHERE p.review_count>0 AND LENGTH(w.word) BETWEEN 3 AND 24 AND w.word NOT GLOB '*[^a-zA-Z]*' ORDER BY CASE WHEN p.strength>=75 THEN 0 ELSE 1 END,RANDOM() LIMIT ?`, [bookId, count]);
  }

  async getConstellationWords(limit: number = 120): Promise<LearnedWord[]> {
    const count = Math.max(1, Math.min(120, Math.floor(Number.isFinite(limit) ? limit : 120)));
    const rows = await this.store().querySql('SELECT w.*,p.strength,p.next_review_at,COALESCE(e.root,\'\') AS family_key,COALESCE(f.first_learned_at,0) AS first_learned_at FROM word w JOIN word_progress p ON w.id=p.word_id LEFT JOIN word_etymology e ON w.id=e.word_id LEFT JOIN (SELECT word_id,MIN(review_at) AS first_learned_at FROM review_record GROUP BY word_id) f ON w.id=f.word_id WHERE p.review_count>0 ORDER BY p.last_review_at DESC,w.id LIMIT ?', [count]);
    const words: LearnedWord[] = [];
    try {
      while (rows.goToNextRow()) {
        const item = new LearnedWord();
        item.word = this.readWord(rows);
        item.strength = rows.getLong(rows.getColumnIndex('strength'));
        item.nextReviewAt = rows.getLong(rows.getColumnIndex('next_review_at'));
        item.familyKey = rows.getString(rows.getColumnIndex('family_key'));
        item.firstLearnedAt = rows.getLong(rows.getColumnIndex('first_learned_at'));
        words.push(item);
      }
    } finally {
      rows.close();
    }
    return words;
  }

  async savePracticeResult(mode: string, correct: number, total: number, durationMs: number,
    now: number): Promise<PracticeResult> {
    if (['spelling', 'meaning', 'recall', 'dictation', 'cloze', 'mistake'].indexOf(mode) < 0 || !Number.isInteger(total) || total < 1 || total > 50 ||
      !Number.isInteger(correct) || correct < 0 || correct > total || !Number.isFinite(durationMs) || durationMs < 0) {
      throw new Error('练习结果格式不正确');
    }
    const result = new PracticeResult();
    result.mode = mode;
    result.correct = correct;
    result.total = total;
    result.durationMs = Math.min(3600000, Math.floor(durationMs));
    result.completedAt = now;
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO practice_result(mode,correct_count,total_count,duration_ms,practiced_at) VALUES(?,?,?,?,?)',
        [mode, correct, total, result.durationMs, now]);
      const rows = await store.querySql('SELECT last_insert_rowid()');
      try {
        result.id = rows.goToFirstRow() ? rows.getLong(0) : 0;
      } finally {
        rows.close();
      }
    });
    return result;
  }

  async getPracticeResults(limit: number = 10): Promise<PracticeResult[]> {
    const count = Math.max(1, Math.min(100000, Math.floor(Number.isFinite(limit) ? limit : 10)));
    const rows = await this.store().querySql('SELECT * FROM practice_result ORDER BY practiced_at DESC,id DESC LIMIT ?', [count]);
    const results: PracticeResult[] = [];
    try {
      while (rows.goToNextRow()) {
        const result = new PracticeResult();
        result.id = rows.getLong(rows.getColumnIndex('id'));
        result.mode = rows.getString(rows.getColumnIndex('mode'));
        result.correct = rows.getLong(rows.getColumnIndex('correct_count'));
        result.total = rows.getLong(rows.getColumnIndex('total_count'));
        result.durationMs = rows.getLong(rows.getColumnIndex('duration_ms'));
        result.completedAt = rows.getLong(rows.getColumnIndex('practiced_at'));
        results.push(result);
      }
    } finally {
      rows.close();
    }
    return results;
  }

  private async restoreYesterdayGlow(store: DatabaseTransaction, now: number, extraNewGoal: number): Promise<void> {
    const today = dateKey(now);
    const yesterday = shiftedDate(now, -1);
    const previous = await store.querySql('SELECT total_count FROM daily_summary WHERE date=?', [yesterday]);
    let active = false;
    try {
      active = previous.goToFirstRow() && previous.getLong(0) > 0;
    } finally {
      previous.close();
    }
    if (active) {
      return;
    }
    const rows = await store.querySql('SELECT s.new_count,p.review_done,p.review_target FROM daily_summary s JOIN daily_plan p ON s.date=p.date WHERE s.date=?', [today]);
    let reason = '';
    try {
      if (rows.goToFirstRow()) {
        if (rows.getLong(2) > 0 && rows.getLong(1) >= rows.getLong(2)) {
          reason = 'review_complete';
        } else if (rows.getLong(0) >= extraNewGoal) {
          reason = 'extra_five_new';
        }
      }
    } finally {
      rows.close();
    }
    if (reason.length > 0) {
      await store.executeSql('INSERT OR IGNORE INTO daily_glow(date,earned_on,reason) VALUES(?,?,?)', [yesterday, today, reason]);
    }
  }

  async getGlowRecords(): Promise<GlowRecord[]> {
    const rows = await this.store().querySql('SELECT * FROM daily_glow ORDER BY date');
    const records: GlowRecord[] = [];
    try {
      while (rows.goToNextRow()) {
        const record = new GlowRecord();
        record.date = rows.getString(rows.getColumnIndex('date'));
        record.earnedOn = rows.getString(rows.getColumnIndex('earned_on'));
        record.reason = rows.getString(rows.getColumnIndex('reason'));
        records.push(record);
      }
    } finally {
      rows.close();
    }
    return records;
  }
}
