import { relationalStore } from '@kit.ArkData';
import { DailyPlan, DaySummary, DictionaryBook, DictionaryCatalog, LearnedDate, LearnedWord, ReviewRecord, ReviewResult,
  Statistics, StudyItem, StudySession, Word, WordBook, WordProgress } from '../model/AppModels';
import { dateKey, dayStart, shiftedDate, weekStart } from '../utils/TimeUtils';
import { strengthAfterResult } from '../utils/MemoryUtils';
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

  async getWords(bookId: string, filter: string, query: string, limit: number = 80): Promise<Word[]> {
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
    sql += ' ORDER BY w.id LIMIT ?';
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
    const count = Math.max(1, Math.min(50, Math.floor(Number.isFinite(limit) ? limit : 10)));
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

  async getDue(now: number, limit: number, exam: boolean = false, bookId: string = ''): Promise<Word[]> {
    if (limit <= 0) {
      return [];
    }
    const order = exam ? 'p.wrong_count DESC,p.strength ASC,p.next_review_at ASC' :
      'p.next_review_at ASC,p.strength ASC';
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
    return plan;
  }

  async savePlan(plan: DailyPlan): Promise<void> {
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO daily_plan(date,new_target,review_target,new_done,review_done,estimated_minutes,budget) VALUES(?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET new_target=excluded.new_target,review_target=excluded.review_target,estimated_minutes=excluded.estimated_minutes,budget=excluded.budget',
        [plan.date, plan.newTarget, plan.reviewTarget, plan.newDone, plan.reviewDone, plan.estimatedMinutes, plan.budget]);
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
      await this.writeSession(store, session);
    });
  }

  private async writeSession(store: DatabaseTransaction, session: StudySession): Promise<void> {
    await store.executeSql('INSERT OR REPLACE INTO study_session(id,payload) VALUES(1,?)', [JSON.stringify(session)]);
  }

  /** Answer and resume cursor are one durable unit, preventing repeats after an interrupted save. */
  async record(previous: WordProgress, next: WordProgress, result: ReviewResult,
    responseMs: number, session: StudySession, now: number): Promise<void> {
    const date = dateKey(now);
    const isNew = previous.reviewCount === 0;
    const duration = Math.max(0, Math.min(300000, Math.floor(Number.isFinite(responseMs) ? responseMs : 0)));
    await this.database.transaction(async (store: DatabaseTransaction) => {
      await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count,wrong_count,favorite,is_new_word) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(word_id) DO UPDATE SET strength=excluded.strength,level=excluded.level,next_review_at=excluded.next_review_at,last_review_at=excluded.last_review_at,review_count=excluded.review_count,wrong_count=excluded.wrong_count',
        [next.wordId, next.strength, next.level, next.nextReviewAt, next.lastReviewAt, next.reviewCount,
          next.wrongCount, next.favorite ? 1 : 0, next.isNewWord ? 1 : 0]);
      await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
        [next.wordId, result, now, duration, previous.level, next.level, previous.strength, next.strength,
          isNew ? 'new' : 'review']);
      if (next.strength >= 75) {
        await store.executeSql('INSERT OR IGNORE INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)',
          [next.wordId, now]);
      }
      await store.executeSql(isNew ? 'UPDATE daily_plan SET new_done=new_done+1 WHERE date=?' :
        'UPDATE daily_plan SET review_done=review_done+1 WHERE date=?', [date]);
      await store.executeSql('INSERT INTO daily_summary(date,new_count,review_count,known_count,total_count,duration_ms) VALUES(?,?,?,?,1,?) ON CONFLICT(date) DO UPDATE SET new_count=new_count+excluded.new_count,review_count=review_count+excluded.review_count,known_count=known_count+excluded.known_count,total_count=total_count+1,duration_ms=duration_ms+excluded.duration_ms',
        [date, isNew ? 1 : 0, isNew ? 0 : 1, !isNew && result === ReviewResult.KNOW ? 1 : 0, duration]);
      await this.writeSession(store, session);
    });
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
}
