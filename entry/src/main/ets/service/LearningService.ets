import { ExperienceRepository } from '../repository/ExperienceRepository';
import { ExperienceService } from './ExperienceService';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { PracticeResult, WordEnrichment, AppSnapshot, DailyPlan, DataExport, DictionaryBook, DictionaryCatalog, ReviewRecord, ReviewResult,
  LearnedDate, LearnedWord, MistakeWord, WordIdentity, WordBook, MasteredWord, StudyItem, StudySession, UserSettings, Word, WordProgress } from '../model/AppModels';
import { ArticleService } from './ArticleService';
import { BackupService } from './BackupService';
import { DatabaseManager } from '../repository/DatabaseManager';
import { LearningRepository } from '../repository/LearningRepository';
import { UserSettingsStore } from '../store/UserSettingsStore';
import { dateKey, dayStart } from '../utils/TimeUtils';
import { dailyReviewQuota, examPlanAdvice, scheduleReview } from './ReviewScheduler';

/** The UI only talks to this service; SQL, scheduling, and durable resume stay below the page layer. */
export class LearningService {
  private static instance: LearningService = new LearningService();
  private database: DatabaseManager = new DatabaseManager();
  private repository: LearningRepository = new LearningRepository(this.database);
  private settingsStore: UserSettingsStore = new UserSettingsStore();
  private session: StudySession = new StudySession();
  private initializing: Promise<void> | undefined = undefined;
  private answering: Promise<StudySession> | undefined = undefined;
  private ready: boolean = false;
  private undoAvailable: boolean = false;
  private operations: Promise<void> = Promise.resolve();

  /** A restore must not race an older plan refresh, setting change, answer, or export snapshot. */
  private serialize<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operations.then(operation);
    this.operations = result.then(() => {}, () => {});
    return result;
  }

  static getInstance(): LearningService {
    return LearningService.instance;
  }

  async initialize(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    if (!this.initializing) {
      this.initializing = this.prepare(context);
    }
    try {
      await this.initializing;
    } catch (error) {
      this.initializing = undefined;
      throw new Error((error as Error).message || '学习数据初始化失败');
    }
  }

  private async prepare(context: common.Context): Promise<void> {
    await this.database.initialize(context);
    await this.settingsStore.initialize(context, this.database);
    const bytes = await context.resourceManager.getRawFileContent('wordbooks/catalog.json');
    const catalog = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as DictionaryCatalog;
    if (!Number.isInteger(catalog.version) || catalog.version < 1 || !Array.isArray(catalog.books) ||
      catalog.books.length === 0) {
      throw new Error('内置词书格式不正确');
    }
    for (const book of catalog.books) {
      this.validateWords(book.words);
    }
    await this.repository.importCatalog(catalog);
    await this.repository.migrateLearningSemantics();
    await this.repository.migrateAdaptiveMetrics();
    await this.repository.importEnrichmentSeeds();
    const settings = this.getSettings();
    const books = await this.repository.getBooks();
    if (books.length === 0) {
      throw new Error('没有可学习的词书');
    }
    if (!books.some((book) => book.id === settings.currentBookId)) {
      settings.currentBookId = books[0].id;
      await this.settingsStore.save(settings);
    }
    await this.repository.clearUndo();
    ExperienceService.getInstance().initialize(this.database);
    ArticleService.getInstance().initialize(context, this.database);
    this.session = await this.repository.loadSession();
    await this.ensurePlan();
    this.ready = true;
  }

  getSettings(): UserSettings {
    return this.settingsStore.getSettings();
  }

  updateSettings(settings: UserSettings): Promise<void> {
    return this.serialize(() => this.updateSettingsNow(settings));
  }

  private async updateSettingsNow(settings: UserSettings): Promise<void> {
    const books = await this.repository.getBooks();
    if (!books.some((book) => book.id === settings.currentBookId)) {
      throw new Error('请选择一个已有词书');
    }
    await this.settingsStore.save(settings);
    await this.ensurePlan();
  }

  private async ensurePlan(now: number = Date.now()): Promise<DailyPlan> {
    return this.refreshPlan(now);
  }

  private async refreshPlan(now: number = Date.now()): Promise<DailyPlan> {
    const settings = this.getSettings();
    const key = dateKey(now);
    const existing = await this.repository.getPlan(key);
    const plan = existing || new DailyPlan();
    plan.date = key;
    // 旧预算/考试偏好仍可读取和导出，每日新词量始终使用用户保存的目标。
    plan.budget = 'normal';
    const due = await this.repository.countDue(now);
    // Persist today's largest workload so a 20% release never turns into the full queue mid-day.
    plan.backlogCount = Math.max(plan.backlogCount, due + plan.reviewDone);
    plan.reviewTarget = Math.max(plan.reviewDone, dailyReviewQuota(plan.backlogCount, 'normal'));
    const available = await this.repository.countUnlearned(settings.currentBookId);
    plan.newTarget = Math.max(plan.newDone, Math.min(plan.newDone + available,
      settings.dailyNewTarget));
    plan.estimatedMinutes = this.estimateMinutes(plan);
    await this.repository.savePlan(plan);
    return plan;
  }

  private estimateMinutes(plan: DailyPlan): number {
    return Math.ceil((Math.max(0, plan.newTarget - plan.newDone) * 30 +
      Math.max(0, plan.reviewTarget - plan.reviewDone) * 12) / 60);
  }

  getSnapshot(): Promise<AppSnapshot> {
    return this.serialize(() => this.getSnapshotNow());
  }

  private async getSnapshotNow(): Promise<AppSnapshot> {
    const now = Date.now();
    const snapshot = new AppSnapshot();
    snapshot.settings = this.getSettings();
    snapshot.plan = await this.ensurePlan(now);
    snapshot.books = await this.repository.getBooks();
    snapshot.dueCount = await this.repository.countDue(now);
    snapshot.mistakeCount = await this.repository.scalar('SELECT COUNT(*) FROM word_progress WHERE wrong_count>0 AND strength<75');
    snapshot.favoriteCount = await this.repository.scalar('SELECT COUNT(*) FROM word_progress WHERE favorite=1');
    snapshot.newWordCount = await this.repository.scalar('SELECT COUNT(*) FROM word_progress WHERE is_new_word=1');
    snapshot.stats = await this.repository.getStatistics(now);
    snapshot.advice = examPlanAdvice(snapshot.settings.examDate,
      await this.repository.countUnlearned(snapshot.settings.currentBookId), snapshot.settings.dailyNewTarget, now);
    const selected = snapshot.books.find((book) => book.id === snapshot.settings.currentBookId);
    if (selected && selected.totalCount > 0) {
      const offset = Math.floor(dayStart(now) / 86400000) % selected.totalCount;
      const words = await this.repository.getDailyWord(selected.id, offset);
      if (words.length > 0) {
        snapshot.dailyWord = words[0];
      }
    }
    return snapshot;
  }

  getWords(bookId: string, filter: string, query: string): Promise<Word[]> {
    return this.repository.getWords(bookId, filter, query);
  }

  getWord(id: number): Promise<Word> {
    return this.repository.getWord(id);
  }

  getProgress(id: number): Promise<WordProgress> {
    return this.repository.getProgress(id);
  }

  getHistory(id: number): Promise<ReviewRecord[]> {
    return this.repository.getHistory(id);
  }

  getLearnedDates(): Promise<LearnedDate[]> {
    return this.repository.getLearnedDates();
  }

  getLearnedWords(date: string, query: string = '', offset: number = 0): Promise<LearnedWord[]> {
    return this.repository.getLearnedWords(date, query, offset, 50, this.getSettings().currentBookId);
  }

  getChallengeWords(limit: number = 10): Promise<Word[]> {
    return this.repository.getChallengeWords(limit, this.getSettings().currentBookId);
  }

  async getTargetedWords(ids: number[]): Promise<Word[]> {
    const words: Word[] = [];
    for (const id of Array.from(new Set<number>(ids)).slice(0, 10)) {
      const progress = await this.repository.getProgress(id);
      if (progress.reviewCount > 0) {
        try { words.push(await this.repository.getBookWord(this.getSettings().currentBookId, id)); }
        catch { words.push(await this.repository.getWord(id)); }
      }
    }
    return words;
  }

  getWordEnrichment(id: number): Promise<WordEnrichment> {
    return this.repository.getWordEnrichment(id);
  }

  findWordBySpelling(headword: string): Promise<Word | undefined> {
    return this.repository.findWordBySpelling(headword);
  }

  getNightWords(limit: number = 5): Promise<Word[]> {
    return this.repository.getNightWords(Date.now(), limit, this.getSettings().currentBookId);
  }

  getAudioWords(limit: number = 30): Promise<Word[]> {
    return this.repository.getAudioWords(Date.now(), limit, this.getSettings().currentBookId);
  }

  getDeskWords(limit: number = 30): Promise<Word[]> {
    return this.getAudioWords(limit);
  }

  getSpellingWords(limit: number = 5): Promise<Word[]> {
    return this.repository.getSpellingWords(limit, this.getSettings().currentBookId);
  }

  getConstellationWords(limit: number = 120): Promise<LearnedWord[]> {
    return this.repository.getConstellationWords(limit);
  }

  savePracticeResult(mode: string, correct: number, total: number, durationMs: number): Promise<PracticeResult> {
    return this.serialize(() => this.repository.savePracticeResult(mode, correct, total, durationMs, Date.now()));
  }

  getPracticeResults(limit: number = 10): Promise<PracticeResult[]> {
    return this.repository.getPracticeResults(limit);
  }

  setFavorite(id: number, value: boolean): Promise<void> {
    return this.serialize(() => this.repository.setFlag(id, true, value));
  }

  setNewWord(id: number, value: boolean): Promise<void> {
    return this.serialize(() => this.repository.setFlag(id, false, value));
  }

  startSession(mode: string): Promise<StudySession> {
    return this.serialize(() => this.startSessionNow(mode));
  }

  private async startSessionNow(mode: string): Promise<StudySession> {
    if (['today', 'review', 'quick', 'onboarding', 'mistake'].indexOf(mode) < 0) {
      throw new Error('未知学习模式');
    }
    if (this.session.mode === mode && this.session.index < this.session.items.length) {
      return this.getSession();
    }
    const now = Date.now();
    const plan = await this.ensurePlan(now);
    const settings = this.getSettings();
    let reviewLimit = Math.max(0, plan.reviewTarget - plan.reviewDone);
    let newLimit = Math.max(0, plan.newTarget - plan.newDone);
    if (mode === 'review') {
      reviewLimit = Math.max(0, plan.reviewTarget - plan.reviewDone);
      newLimit = 0;
    } else if (mode === 'quick') {
      reviewLimit = Math.min(5, reviewLimit);
      newLimit = await this.repository.countDue(now) > 0 ? 3 : 6;
    } else if (mode === 'onboarding') {
      reviewLimit = 0;
      newLimit = 3;
    }
    const due = mode === 'mistake' ? (await this.repository.getMistakes(0, 20)).map((item: MistakeWord) => item.word) :
      await this.repository.getDue(now, reviewLimit, settings.learningMode === 'exam', settings.currentBookId, plan.backlogCount > 100);
    const fresh = mode === 'mistake' ? [] : await this.repository.getUnlearned(settings.currentBookId, newLimit);
    const next = new StudySession();
    next.mode = mode;
    next.startedAt = now;
    for (const word of due) {
      const item = new StudyItem();
      item.word = word;
      item.type = 'review';
      next.items.push(item);
    }
    for (const word of fresh) {
      const item = new StudyItem();
      item.word = word;
      item.type = 'new';
      next.items.push(item);
    }
    this.undoAvailable = false;
    await this.repository.saveSession(next);
    this.session = next;
    return this.getSession();
  }

  getSession(): StudySession {
    // The page receives a copy; direct UI state mutation cannot alter the persistent cursor.
    return JSON.parse(JSON.stringify(this.session)) as StudySession;
  }

  async record(result: ReviewResult, responseMs: number): Promise<StudySession> {
    if (!this.answering) {
      this.answering = this.serialize(() => this.submit(result, responseMs));
    }
    try {
      return await this.answering;
    } finally {
      this.answering = undefined;
    }
  }

  private async submit(result: ReviewResult, responseMs: number): Promise<StudySession> {
    if (this.session.index >= this.session.items.length) {
      return this.getSession();
    }
    const now = Date.now();
    await this.ensurePlan(now);
    const item = this.session.items[this.session.index];
    const previous = await this.repository.getProgress(item.word.id);
    const progress = scheduleReview(previous, result, now, responseMs);
    const next = this.getSession();
    next.items[next.index].type = previous.reviewCount === 0 ? 'new' : 'review';
    next.index += 1;
    next.completed += 1;
    await this.repository.record(previous, progress, result, responseMs, next, now, this.getSettings().dailyNewTarget + 5);
    this.session = next;
    this.undoAvailable = true;
    return this.getSession();
  }

  canUndo(): boolean { return this.undoAvailable; }

  invalidateUndo(): Promise<void> {
    this.undoAvailable = false;
    return this.serialize(() => this.repository.clearUndo());
  }

  undoLast(): Promise<StudySession> {
    return this.serialize(async () => {
      if (!this.undoAvailable) { throw new Error('没有可撤销的判断'); }
      const session = await this.repository.undoLast();
      this.undoAvailable = false;
      if (!session) { throw new Error('没有可撤销的判断'); }
      this.session = session;
      return this.getSession();
    });
  }

  getMistakes(offset: number = 0): Promise<MistakeWord[]> { return this.repository.getMistakes(offset); }

  clearSession(): Promise<void> {
    return this.serialize(() => this.clearSessionNow());
  }

  private async clearSessionNow(): Promise<void> {
    const next = new StudySession();
    this.undoAvailable = false;
    await this.repository.saveSession(next);
    this.session = next;
  }

  private validateWords(words: Word[]): void {
    if (!Array.isArray(words) || words.length === 0 || words.length > 50000) {
      throw new Error('词书需要包含 1～50000 个单词');
    }
    for (const word of words) {
      if (typeof word.word !== 'string' || typeof word.meaning !== 'string' ||
        word.word.trim().length === 0 || word.word.length > 120 || word.meaning.trim().length === 0 ||
        word.meaning.length > 4000 || typeof word.phonetic !== 'string' || typeof word.example !== 'string' ||
        typeof word.translation !== 'string' || word.example.length > 8000 || word.translation.length > 8000) {
        throw new Error('请检查单词和释义，例句等字段需要是文本');
      }
    }
  }

  importWords(bookName: string, words: Word[]): Promise<number> {
    return this.serialize(() => this.importWordsNow(bookName, words));
  }

  private async importWordsNow(bookName: string, words: Word[]): Promise<number> {
    this.validateWords(words);
    if (bookName.trim().length === 0 || bookName.length > 80) {
      throw new Error('词书名称需要为 1～80 个字');
    }
    const book = new DictionaryBook();
    book.id = `custom_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    book.name = bookName.trim();
    book.category = 'custom';
    book.description = '你导入的自定义词书，学习进度与已有词汇共享。';
    book.words = words;
    return this.repository.insertBook(book);
  }

  renameBook(bookId: string, name: string): Promise<void> {
    return this.serialize(() => this.renameBookNow(bookId, name));
  }

  private async renameBookNow(bookId: string, name: string): Promise<void> {
    if (name.trim().length === 0 || name.length > 80) {
      throw new Error('词书名称需要为 1～80 个字');
    }
    await this.repository.renameBook(bookId, name.trim());
  }

  getBookWord(bookId: string, wordId: number): Promise<Word> {
    return this.repository.getBookWord(bookId, wordId);
  }

  updateBookWord(bookId: string, wordId: number, edited: Word): Promise<Word> {
    return this.serialize(() => this.updateBookWordNow(bookId, wordId, edited));
  }

  private async updateBookWordNow(bookId: string, wordId: number, edited: Word): Promise<Word> {
    this.validateWords([edited]);
    const targetId = await this.repository.updateBookWord(bookId, wordId, edited);
    const saved = await this.repository.getBookWord(bookId, targetId);
    const session = this.getSession();
    let changed = false;
    for (let index = session.index; index < session.items.length; index++) {
      const item = session.items[index];
      if (item.word.id === wordId && (item.word.sourceBookId === bookId ||
        (this.getSettings().currentBookId === bookId && !item.word.sourceBookId))) {
        item.word = saved;
        changed = true;
      }
    }
    if (changed) {
      await this.repository.saveSession(session);
      this.session = session;
    }
    return saved;
  }

  exportBook(bookId: string): Promise<Word[]> {
    return this.repository.getWords(bookId, 'all', '', 50000);
  }

  async resolveImportWords(words: Word[]): Promise<Word[]> {
    if (!Array.isArray(words) || words.length === 0 || words.length > 50000) {
      throw new Error('词书需要包含 1～50000 个单词');
    }
    const dictionary = await this.repository.queryWords('SELECT * FROM word');
    const known = new Map<string, Word>();
    for (const word of dictionary) {
      known.set(word.word.trim().toLowerCase(), word);
    }
    const resolved: Word[] = [];
    for (const source of words) {
      const word = new Word();
      word.word = typeof source.word === 'string' ? source.word.trim() : '';
      word.meaning = typeof source.meaning === 'string' ? source.meaning.trim() : '';
      word.phonetic = typeof source.phonetic === 'string' ? source.phonetic : '';
      word.example = typeof source.example === 'string' ? source.example : '';
      word.translation = typeof source.translation === 'string' ? source.translation : '';
      const local = known.get(word.word.toLowerCase());
      if (word.meaning.length === 0 && local) {
        word.meaning = local.meaning;
        word.phonetic = word.phonetic || local.phonetic;
        word.example = word.example || local.example;
        word.translation = word.translation || local.translation;
      }
      resolved.push(word);
    }
    return resolved;
  }

  restoreData(data: DataExport): Promise<number> {
    return this.serialize(() => this.restoreDataNow(data));
  }

  private async restoreDataNow(data: DataExport): Promise<number> {
    // Validate again at the mutation boundary; callers cannot bypass preview validation.
    const backup = BackupService.parse(JSON.stringify(data));
    // Notification registration/permission belongs to this installation, never to the source device.
    const localSettings = this.getSettings();
    backup.settings.reminderEnabled = localSettings.reminderEnabled;
    backup.settings.reminderHour = localSettings.reminderHour;
    backup.settings.reminderMinute = localSettings.reminderMinute;
    const localBooks = await this.repository.getBooks();
    if (!localBooks.some((book: WordBook) => book.id === backup.settings.currentBookId) &&
      !backup.books.some((book: DictionaryBook) => book.id === backup.settings.currentBookId && book.category === 'custom')) {
      backup.settings.currentBookId = localBooks[0].id;
    }
    const skipped = await this.repository.restoreBackup(backup);
    this.undoAvailable = false;
    this.settingsStore.acceptCommitted(backup.settings);
    this.session = backup.session;
    // Enrichment is derived from bundled seeds; rebuilding cannot invalidate a committed restore.
    await this.repository.importEnrichmentSeeds().catch(() => {});
    return skipped;
  }

  exportData(): Promise<string> {
    return this.serialize(() => this.exportDataNow());
  }

  private async exportDataNow(): Promise<string> {
    const backup = new DataExport();
    backup.exportedAt = Date.now();
    backup.dictionaryVersion = await this.repository.dictionaryVersion();
    backup.compact = true;
    backup.masteredWords = await this.repository.allMasteredWords();
    backup.settings = this.getSettings();
    backup.progress = await this.repository.allProgress();
    backup.records = await this.repository.allRecords();
    backup.plans = await this.repository.allPlans();
    backup.days = await this.repository.getDays();
    backup.session = this.getSession();
    backup.practiceResults = await this.repository.getPracticeResults(100000);
    backup.glowRecords = await this.repository.getGlowRecords();
    const books = await this.repository.getBooks();
    for (const item of books) {
      const book = new DictionaryBook();
      book.id = item.id;
      book.name = item.name;
      book.category = item.category;
      book.description = item.description;
      book.words = item.category === 'custom' ? await this.repository.backupBookWords(item.id) : [];
      backup.books.push(book);
    }
    await new ExperienceRepository(this.database).exportInto(backup);
    const referenced = new Set<number>();
    backup.practiceAttempts.forEach((item) => { referenced.add(item.wordId); });
    backup.sentences.forEach((item) => { referenced.add(item.wordId); });
    backup.progress.forEach((p: WordProgress) => { referenced.add(p.wordId); });
    backup.records.forEach((r: ReviewRecord) => { referenced.add(r.wordId); });
    backup.masteredWords.forEach((m: MasteredWord) => { referenced.add(m.wordId); });
    backup.session.items.forEach((item: StudyItem) => { referenced.add(item.word.id); });
    backup.books.forEach((book: DictionaryBook) => { book.words.forEach((word: Word) => { referenced.add(word.id); }); });
    backup.words = (await this.repository.backupNonBuiltinWords()).filter((word: Word) => referenced.has(word.id));
    backup.wordIdentities = (await this.repository.allWords()).filter((word: Word) => referenced.has(word.id))
      .map((word: Word) => { const identity = new WordIdentity(); identity.id = word.id; identity.word = word.word; return identity; });
    return JSON.stringify(backup, null, 2);
  }
}
