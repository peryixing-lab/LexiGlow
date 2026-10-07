import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AppSnapshot, DailyPlan, DataExport, DictionaryBook, DictionaryCatalog, ReviewRecord, ReviewResult,
  StudyItem, StudySession, UserSettings, Word, WordProgress } from '../model/AppModels';
import { DatabaseManager } from '../repository/DatabaseManager';
import { LearningRepository } from '../repository/LearningRepository';
import { UserSettingsStore } from '../store/UserSettingsStore';
import { dateKey, dayStart } from '../utils/TimeUtils';
import { adjustedNewTarget, scheduleReview } from './ReviewScheduler';

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
    await this.settingsStore.initialize(context);
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
    const settings = this.getSettings();
    const books = await this.repository.getBooks();
    if (books.length === 0) {
      throw new Error('没有可学习的词书');
    }
    if (!books.some((book) => book.id === settings.currentBookId)) {
      settings.currentBookId = books[0].id;
      await this.settingsStore.save(settings);
    }
    this.session = await this.repository.loadSession();
    await this.ensurePlan();
    this.ready = true;
  }

  getSettings(): UserSettings {
    return this.settingsStore.getSettings();
  }

  async updateSettings(settings: UserSettings): Promise<void> {
    const books = await this.repository.getBooks();
    if (!books.some((book) => book.id === settings.currentBookId)) {
      throw new Error('请选择一个已有词书');
    }
    await this.settingsStore.save(settings);
    const current = await this.ensurePlan();
    await this.refreshPlan(current.budget);
  }

  async setBudget(budget: string): Promise<void> {
    if (['busy', 'normal', 'free'].indexOf(budget) < 0) {
      throw new Error('请选择很忙、正常或有空');
    }
    await this.ensurePlan();
    await this.refreshPlan(budget);
  }

  private async ensurePlan(now: number = Date.now()): Promise<DailyPlan> {
    const key = dateKey(now);
    const plan = await this.repository.getPlan(key);
    if (!plan) {
      return this.refreshPlan('normal', now);
    }
    // The due queue can grow while the app is open (including a forgotten word after ten minutes).
    const due = await this.repository.countDue(now);
    const cap = plan.budget === 'busy' ? 15 : (plan.budget === 'free' ? 100 : 60);
    const target = Math.max(plan.reviewDone, Math.min(cap, due + plan.reviewDone));
    const settings = this.getSettings();
    const base = this.newTargetFor(settings, plan.budget);
    const available = await this.repository.countUnlearned(settings.currentBookId);
    const newTarget = Math.max(plan.newDone, Math.min(plan.newDone + available, adjustedNewTarget(base, due)));
    const minutes = Math.ceil((Math.max(0, newTarget - plan.newDone) * 30 +
      Math.max(0, target - plan.reviewDone) * 12) / 60);
    if (target !== plan.reviewTarget || newTarget !== plan.newTarget || minutes !== plan.estimatedMinutes) {
      plan.reviewTarget = target;
      plan.newTarget = newTarget;
      plan.estimatedMinutes = minutes;
      await this.repository.savePlan(plan);
    }
    return plan;
  }

  private async refreshPlan(budget: string, now: number = Date.now()): Promise<DailyPlan> {
    const settings = this.getSettings();
    const key = dateKey(now);
    const existing = await this.repository.getPlan(key);
    const plan = existing || new DailyPlan();
    plan.date = key;
    plan.budget = budget;
    const due = await this.repository.countDue(now);
    const available = await this.repository.countUnlearned(settings.currentBookId);
    const base = this.newTargetFor(settings, budget);
    plan.newTarget = Math.max(plan.newDone, Math.min(plan.newDone + available, adjustedNewTarget(base, due)));
    const cap = budget === 'busy' ? 15 : (budget === 'free' ? 100 : 60);
    plan.reviewTarget = Math.max(plan.reviewDone, Math.min(cap, due + plan.reviewDone));
    plan.estimatedMinutes = this.estimateMinutes(plan);
    await this.repository.savePlan(plan);
    return plan;
  }

  private estimateMinutes(plan: DailyPlan): number {
    return Math.ceil((Math.max(0, plan.newTarget - plan.newDone) * 30 +
      Math.max(0, plan.reviewTarget - plan.reviewDone) * 12) / 60);
  }

  private newTargetFor(settings: UserSettings, budget: string): number {
    const base = budget === 'busy' ? Math.min(5, settings.dailyNewTarget) :
      (budget === 'free' ? Math.min(100, Math.round(settings.dailyNewTarget * 1.5)) : settings.dailyNewTarget);
    return settings.learningMode === 'exam' ? Math.floor(base * 0.5) : base;
  }

  async getSnapshot(): Promise<AppSnapshot> {
    const now = Date.now();
    const snapshot = new AppSnapshot();
    snapshot.settings = this.getSettings();
    snapshot.plan = await this.ensurePlan(now);
    snapshot.books = await this.repository.getBooks();
    snapshot.dueCount = await this.repository.countDue(now);
    snapshot.favoriteCount = await this.repository.scalar('SELECT COUNT(*) FROM word_progress WHERE favorite=1');
    snapshot.newWordCount = await this.repository.scalar('SELECT COUNT(*) FROM word_progress WHERE is_new_word=1');
    snapshot.stats = await this.repository.getStatistics(now);
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

  setFavorite(id: number, value: boolean): Promise<void> {
    return this.repository.setFlag(id, true, value);
  }

  setNewWord(id: number, value: boolean): Promise<void> {
    return this.repository.setFlag(id, false, value);
  }

  async startSession(mode: string): Promise<StudySession> {
    if (this.answering) {
      await this.answering;
    }
    if (['today', 'review', 'quick', 'onboarding'].indexOf(mode) < 0) {
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
      reviewLimit = Math.min(100, await this.repository.countDue(now));
      newLimit = 0;
    } else if (mode === 'quick') {
      reviewLimit = 5;
      newLimit = await this.repository.countDue(now) > 0 ? 3 : 6;
    } else if (mode === 'onboarding') {
      reviewLimit = 0;
      newLimit = 3;
    }
    const due = await this.repository.getDue(now, reviewLimit, settings.learningMode === 'exam', settings.currentBookId);
    const fresh = await this.repository.getUnlearned(settings.currentBookId, newLimit);
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
      this.answering = this.submit(result, responseMs);
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
    const progress = scheduleReview(previous, result, now);
    const next = this.getSession();
    next.index += 1;
    next.completed += 1;
    await this.repository.record(previous, progress, result, responseMs, next, now);
    this.session = next;
    return this.getSession();
  }

  async clearSession(): Promise<void> {
    if (this.answering) {
      await this.answering;
    }
    const next = new StudySession();
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

  async importWords(bookName: string, words: Word[]): Promise<number> {
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

  async renameBook(bookId: string, name: string): Promise<void> {
    if (name.trim().length === 0 || name.length > 80) {
      throw new Error('词书名称需要为 1～80 个字');
    }
    await this.repository.renameBook(bookId, name.trim());
  }

  getBookWord(bookId: string, wordId: number): Promise<Word> {
    return this.repository.getBookWord(bookId, wordId);
  }

  async updateBookWord(bookId: string, wordId: number, edited: Word): Promise<Word> {
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

  async exportData(): Promise<string> {
    const backup = new DataExport();
    backup.exportedAt = Date.now();
    backup.settings = this.getSettings();
    backup.progress = await this.repository.allProgress();
    backup.records = await this.repository.allRecords();
    backup.plans = await this.repository.allPlans();
    backup.days = await this.repository.getDays();
    backup.session = this.getSession();
    const books = await this.repository.getBooks();
    for (const item of books) {
      const book = new DictionaryBook();
      book.id = item.id;
      book.name = item.name;
      book.category = item.category;
      book.description = item.description;
      book.words = await this.repository.getWords(item.id, 'all', '', 50000);
      backup.books.push(book);
    }
    return JSON.stringify(backup, null, 2);
  }
}
