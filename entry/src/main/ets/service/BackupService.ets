import { PracticeAttempt, SentenceMemory, ReadingProgress } from '../model/ExperienceModels';
import { Article } from '../model/ArticleModels';
import { curatedArticles } from '../data/CuratedArticles';
import { articleParagraphs } from '../utils/ArticleTokenizer';
import { DataExport, DictionaryBook, Word, WordProgress, ReviewRecord, DailyPlan, DaySummary,
  StudySession, StudyItem, UserSettings, PracticeResult, GlowRecord, MasteredWord, WordIdentity } from '../model/AppModels';

/** Validates the complete graph before any database write. Limits apply to file input and decoded data. */
export class BackupService {
  static readonly MAX_BYTES: number = 20 * 1024 * 1024;

  static parse(text: string): DataExport {
    if (text.length === 0 || text.length > BackupService.MAX_BYTES) {
      throw new Error('请选择不超过 20 MB 的词萤学习备份');
    }
    let input: DataExport;
    try { input = JSON.parse(text.replace(/^\uFEFF/, '')) as DataExport; }
    catch (_) { throw new Error('备份不是完整的 JSON 文件，请重新导出'); }
    BackupService.object(input, '备份');
    if (input.format !== 'ciying-learning-backup') {
      throw new Error('这不是词萤学习备份；词书文件请使用「导入自定义词书」');
    }
    if (![1, 2, 3, 4].includes(input.version)) { throw new Error('不支持此备份版本，请更新词萤后再恢复'); }
    const output = new DataExport();
    output.version = input.version;
    output.compact = input.version >= 3 && input.compact === true;
    output.exportedAt = BackupService.integer(input.exportedAt, '导出时间', 0, 8640000000000000);
    output.dictionaryVersion = input.version >= 3 ? BackupService.integer(input.dictionaryVersion, '词典版本') : 0;
    const byId = new Map<number, Word>();
    const byText = new Map<string, number>();
    const addWord = (word: Word): void => {
      const old = byId.get(word.id);
      const identity = word.word.trim().toLowerCase();
      if ((old && old.word.trim().toLowerCase() !== identity) ||
        (byText.has(identity) && byText.get(identity) !== word.id)) {
        throw new Error('备份的单词编号存在冲突');
      }
      if (!old || (old.meaning.length === 0 && word.meaning.length > 0)) {
        byId.set(word.id, word); byText.set(identity, word.id);
      }
    };
    if (output.compact) {
      output.wordIdentities = BackupService.array(input.wordIdentities, '单词身份', 100000).map((value: WordIdentity) => {
        BackupService.object(value, '单词身份');
        const identity = new WordIdentity();
        identity.id = BackupService.integer(value.id, '单词编号', 1);
        identity.word = BackupService.text(value.word, '词头', 120, true).trim();
        if (byId.has(identity.id)) { throw new Error('单词身份含重复编号'); }
        const word = new Word(); word.id = identity.id; word.word = identity.word;
        addWord(word);
        return identity;
      });
      const extraIds = new Set<number>();
      BackupService.array(input.words || [], '自定义单词', 100000).forEach((value: Word) => {
        BackupService.object(value, '自定义单词');
        const original = byId.get(value.id);
        if (!original || original.word.trim().toLowerCase() !== value.word.trim().toLowerCase()) {
          throw new Error('自定义单词与单词身份不一致');
        }
        BackupService.unique(extraIds, value.id, '自定义单词');
        // Normalized backups also contain empty identity placeholders; no dictionary entry is invented for them.
        if (value.meaning !== '') { addWord(BackupService.word(value)); }
      });
    } else if (input.version >= 3) {
      BackupService.array(input.words, '完整词典', 100000).forEach((word: Word) => {
        const normalized = BackupService.word(word);
        if (byId.has(normalized.id)) { throw new Error('完整词典含重复编号'); }
        addWord(normalized);
      });
    }
    const bookIds = new Set<string>();
    output.books = BackupService.array(input.books, '词书', 1000).map((book: DictionaryBook) => {
      BackupService.object(book, '词书');
      const next = new DictionaryBook();
      next.id = BackupService.text(book.id, '词书编号', 160, true);
      if (bookIds.has(next.id)) { throw new Error('备份含重复词书编号'); }
      bookIds.add(next.id);
      next.name = BackupService.text(book.name, '词书名称', 160, true);
      next.category = BackupService.text(book.category, '词书分类', 100, true);
      next.description = BackupService.text(book.description, '词书说明', 4000);
      const wordIds = new Set<number>();
      next.words = BackupService.array(book.words, '词书单词', 50000).map((word: Word) => {
        const normalized = BackupService.word(word);
        if (wordIds.has(normalized.id)) { throw new Error('词书中含重复单词编号'); }
        wordIds.add(normalized.id);
        if (input.version >= 3 && !byId.has(normalized.id)) { throw new Error('词书引用的单词不存在'); }
        addWord(normalized);
        normalized.sourceBookId = next.id;
        return normalized;
      });
      return next;
    });
    if (output.books.length === 0) { throw new Error('备份中没有词书'); }
    output.settings = BackupService.settings(input.settings);
    if (!bookIds.has(output.settings.currentBookId)) { throw new Error('备份当前词书不存在'); }
    output.session = new StudySession();
    if (input.session !== undefined) {
      BackupService.object(input.session, '学习会话');
      const session = input.session;
      output.session.index = BackupService.integer(session.index, '学习位置', 0, 250);
      output.session.completed = BackupService.integer(session.completed, '已完成数量', 0, 250);
      output.session.startedAt = BackupService.integer(session.startedAt, '开始时间', 0, 8640000000000000);
      output.session.mode = BackupService.choice(session.mode, ['', 'today', 'quick', 'review', 'new', 'onboarding', 'mistake'], '学习模式');
      output.session.items = BackupService.array(session.items, '学习会话单词', 250).map((item: StudyItem) => {
        BackupService.object(item, '会话单词');
        const next = new StudyItem();
        next.word = BackupService.word(item.word);
        if (input.version < 3) { addWord(next.word); }
        next.type = BackupService.choice(item.type, ['new', 'review'], '单词学习类型');
        return next;
      });
      if (output.session.completed !== output.session.index || output.session.index > output.session.items.length) {
        throw new Error('备份中的学习位置有误');
      }
    }
    const reference = (id: number): number => {
      BackupService.integer(id, '单词编号', 1);
      if (!byId.has(id)) { throw new Error('备份缺少学习记录对应的单词，无法完整恢复；请在原设备重新导出'); }
      return id;
    };
    output.words = Array.from(byId.values());
    if (output.words.length > 100000) { throw new Error('备份词典超过 100000 个单词'); }
    output.session.items.forEach((item: StudyItem) => {
      reference(item.word.id);
      const original = byId.get(item.word.id);
      if (original && original.word.trim().toLowerCase() !== item.word.word.trim().toLowerCase()) {
        throw new Error('学习会话单词与词典不一致');
      }
      if (item.word.sourceBookId && !bookIds.has(item.word.sourceBookId)) { throw new Error('学习会话引用的词书不存在'); }
    });
    const progressIds = new Set<number>();
    output.progress = BackupService.array(input.progress, '学习进度', 100000).map((value: WordProgress) => {
      BackupService.object(value, '学习进度');
      const next = new WordProgress();
      next.wordId = reference(value.wordId);
      BackupService.unique(progressIds, next.wordId, '学习进度');
      next.strength = BackupService.integer(value.strength, '记忆强度', 0, 100);
      next.level = BackupService.integer(value.level, '复习等级', 0, 100);
      next.nextReviewAt = BackupService.integer(value.nextReviewAt, '下次复习时间', 0, 8640000000000000);
      next.lastReviewAt = BackupService.integer(value.lastReviewAt, '上次复习时间', 0, 8640000000000000);
      next.reviewCount = BackupService.integer(value.reviewCount, '复习次数');
      next.wrongCount = BackupService.integer(value.wrongCount, '错误次数', 0, next.reviewCount);
      next.favorite = BackupService.boolean(value.favorite, '收藏');
      next.isNewWord = BackupService.boolean(value.isNewWord, '生词本');
      next.hesitationCount = BackupService.optionalInteger(value.hesitationCount, '犹豫次数');
      next.lastResponseMs = BackupService.optionalInteger(value.lastResponseMs, '作答耗时');
      next.consecutiveFailures = BackupService.optionalInteger(value.consecutiveFailures, '连续遗忘');
      next.consecutiveKnown = BackupService.optionalInteger(value.consecutiveKnown, '连续认识');
      return next;
    });
    const recordIds = new Set<number>();
    const legacyFirstWords = new Set<number>();
    output.records = BackupService.array(input.records, '回忆记录', 300000).slice()
      .sort((a: ReviewRecord, b: ReviewRecord) => a.id - b.id).map((value: ReviewRecord) => {
      BackupService.object(value, '回忆记录');
      const next = new ReviewRecord();
      next.id = BackupService.integer(value.id, '记录编号', 1);
      BackupService.unique(recordIds, next.id, '回忆记录');
      next.wordId = reference(value.wordId);
      next.result = BackupService.integer(value.result, '回忆结果', 0, 2);
      next.reviewAt = BackupService.integer(value.reviewAt, '回忆时间', 0, 8640000000000000);
      next.responseMs = BackupService.integer(value.responseMs, '回忆耗时');
      next.previousLevel = BackupService.integer(value.previousLevel, '原复习等级', 0, 100);
      next.nextLevel = BackupService.integer(value.nextLevel, '新复习等级', 0, 100);
      next.previousStrength = BackupService.integer(value.previousStrength, '原记忆强度', 0, 100);
      next.nextStrength = BackupService.integer(value.nextStrength, '新记忆强度', 0, 100);
      next.itemType = input.version >= 3 || value.itemType !== undefined ?
        BackupService.choice(value.itemType, ['new', 'review'], '记录类型') :
        (!legacyFirstWords.has(next.wordId) && next.previousLevel === 0 ? 'new' : 'review');
      legacyFirstWords.add(next.wordId);
      return next;
    });
    const planDates = new Set<string>();
    output.plans = BackupService.array(input.plans, '每日计划', 50000).map((value: DailyPlan) => {
      BackupService.object(value, '每日计划');
      const next = new DailyPlan();
      next.date = BackupService.date(value.date);
      BackupService.unique(planDates, next.date, '每日计划');
      next.newTarget = BackupService.integer(value.newTarget, '新词目标');
      next.reviewTarget = BackupService.integer(value.reviewTarget, '复习目标');
      next.newDone = BackupService.integer(value.newDone, '已学新词');
      next.reviewDone = BackupService.integer(value.reviewDone, '已完成复习');
      next.estimatedMinutes = BackupService.integer(value.estimatedMinutes, '预计时间');
      next.budget = BackupService.choice(value.budget, ['normal', 'busy', 'free'], '计划时间');
      next.backlogCount = BackupService.optionalInteger(value.backlogCount, '待复习量');
      return next;
    });
    const dayDates = new Set<string>();
    output.days = BackupService.array(input.days, '每日统计', 50000).map((value: DaySummary) => {
      BackupService.object(value, '每日统计');
      const next = new DaySummary();
      next.date = BackupService.date(value.date);
      BackupService.unique(dayDates, next.date, '每日统计');
      next.newCount = BackupService.integer(value.newCount, '每日新词数');
      next.reviewCount = BackupService.integer(value.reviewCount, '每日复习数');
      next.knownCount = BackupService.integer(value.knownCount, '每日认识数', 0, next.reviewCount);
      next.totalCount = next.newCount + next.reviewCount;
      next.durationMs = BackupService.integer(value.durationMs, '每日学习时间', 0, Number.MAX_SAFE_INTEGER);
      return next;
    });
    const practiceIds = new Set<number>();
    output.practiceResults = BackupService.array(input.practiceResults || [], '练习记录', 100000).map((value: PracticeResult) => {
      BackupService.object(value, '练习记录');
      const next = new PracticeResult();
      next.id = BackupService.integer(value.id, '练习编号', 1);
      BackupService.unique(practiceIds, next.id, '练习记录');
      next.mode = BackupService.text(value.mode, '练习模式', 60, true);
      next.total = BackupService.integer(value.total, '练习题数');
      next.correct = BackupService.integer(value.correct, '练习正确数', 0, next.total);
      next.durationMs = BackupService.integer(value.durationMs, '练习耗时');
      next.completedAt = BackupService.integer(value.completedAt, '练习完成时间', 0, 8640000000000000);
      return next;
    });
    if (input.version >= 4) {
      const attemptIds = new Set<string>();
      output.practiceAttempts = BackupService.array(input.practiceAttempts, '逐词练习', 300000).map((value: PracticeAttempt): PracticeAttempt => {
        BackupService.object(value, '逐词练习');
        const next = new PracticeAttempt(); next.id = BackupService.text(value.id, '逐词记录编号', 160, true);
        BackupService.unique(attemptIds, next.id, '逐词练习'); next.wordId = reference(value.wordId);
        next.mode = BackupService.choice(value.mode, ['meaning', 'spelling', 'dictation', 'cloze'], '练习类型');
        next.correct = BackupService.boolean(value.correct, '答题结果'); next.hinted = BackupService.boolean(value.hinted, '提示记录');
        next.durationMs = BackupService.integer(value.durationMs, '答题时间', 0, 3600000);
        next.recordedAt = BackupService.integer(value.recordedAt, '答题日期', 0, 8640000000000000); return next;
      });
      const articleIds = new Set<number>();
      const articleMap = new Map<number, Article>();
      curatedArticles().forEach((article: Article) => { articleMap.set(article.id, article); });
      output.articles = BackupService.array(input.articles, '文章', 20).map((value: Article): Article => {
        BackupService.object(value, '文章');
        const next = new Article(); next.id = BackupService.integer(value.id, '文章编号', 1);
        BackupService.unique(articleIds, next.id, '文章'); next.title = BackupService.text(value.title, '文章标题', 80, true);
        next.body = BackupService.text(value.body, '文章正文', 60000, true); next.characterCount = next.body.length;
        next.createdAt = BackupService.integer(value.createdAt, '文章日期', 0, 8640000000000000);
        articleMap.set(next.id, next); return next;
      });
      const sentenceIds = new Set<string>(); const sentenceKeys = new Set<string>();
      output.sentences = BackupService.array(input.sentences, '原句', 5000).map((value: SentenceMemory): SentenceMemory => {
        BackupService.object(value, '原句');
        const next = new SentenceMemory(); next.id = BackupService.text(value.id, '原句编号', 160, true);
        BackupService.unique(sentenceIds, next.id, '原句'); next.wordId = reference(value.wordId);
        next.articleId = BackupService.integer(value.articleId, '原句来源', -1000000);
        if (next.articleId !== 0 && !articleMap.has(next.articleId)) { throw new Error('原句来源文章不存在'); }
        next.articleTitle = BackupService.text(value.articleTitle, '原句标题', 80, true);
        next.paragraphKey = BackupService.text(value.paragraphKey, '原句位置', 80, true);
        next.sentence = BackupService.text(value.sentence, '收藏原句', 2000, true);
        next.note = BackupService.text(value.note, '原句备注', 500);
        next.createdAt = BackupService.integer(value.createdAt, '原句日期', 0, 8640000000000000);
        BackupService.unique(sentenceKeys, JSON.stringify([next.wordId, next.articleId, next.paragraphKey, next.sentence]), '原句来源');
        return next;
      });
      const readingIds = new Set<number>();
      output.readingProgress = BackupService.array(input.readingProgress, '阅读进度', 1000).map((value: ReadingProgress): ReadingProgress => {
        BackupService.object(value, '阅读进度');
        const next = new ReadingProgress(); next.articleId = BackupService.integer(value.articleId, '阅读文章', -1000000);
        const article = articleMap.get(next.articleId);
        if (!article) { throw new Error('阅读进度对应的文章不存在'); }
        BackupService.unique(readingIds, next.articleId, '阅读进度');
        next.paragraphIndex = BackupService.integer(value.paragraphIndex, '阅读位置', 0, Math.max(0, articleParagraphs(article.body).length - 1));
        next.completed = BackupService.boolean(value.completed, '阅读完成');
        next.answers = BackupService.array(value.answers, '读后答案', article.questions.length)
          .map((answer: number, index: number): number => BackupService.integer(answer, '读后答案', -1, article.questions[index].options.length - 1));
        next.updatedAt = BackupService.integer(value.updatedAt, '阅读日期', 0, 8640000000000000); return next;
      });
    }
    const glowDates = new Set<string>();
    output.glowRecords = BackupService.array(input.glowRecords || [], '星光记录', 50000).map((value: GlowRecord) => {
      BackupService.object(value, '星光记录');
      const next = new GlowRecord();
      next.date = BackupService.date(value.date);
      BackupService.unique(glowDates, next.date, '星光记录');
      next.earnedOn = BackupService.date(value.earnedOn);
      next.reason = BackupService.text(value.reason, '星光原因', 160, true);
      return next;
    });
    const masteredIds = new Set<number>();
    if (input.version >= 3) {
      output.masteredWords = BackupService.array(input.masteredWords, '掌握记录', 100000).map((value: MasteredWord) => {
        BackupService.object(value, '掌握记录');
        const next = new MasteredWord();
        next.wordId = reference(value.wordId);
        BackupService.unique(masteredIds, next.wordId, '掌握记录');
        next.firstMasteredAt = BackupService.integer(value.firstMasteredAt, '首次掌握时间', 0, 8640000000000000);
        return next;
      });
    } else {
      for (const record of output.records) {
        if (record.nextStrength >= 75 && !masteredIds.has(record.wordId)) {
          const mastered = new MasteredWord();
          mastered.wordId = record.wordId; mastered.firstMasteredAt = record.reviewAt;
          output.masteredWords.push(mastered); masteredIds.add(record.wordId);
        }
      }
      for (const progress of output.progress) {
        if (progress.strength >= 75 && !masteredIds.has(progress.wordId)) {
          const mastered = new MasteredWord();
          mastered.wordId = progress.wordId; mastered.firstMasteredAt = progress.lastReviewAt;
          output.masteredWords.push(mastered);
        }
      }
    }
    return output;
  }

  private static settings(value: UserSettings): UserSettings {
    BackupService.object(value, '学习设置');
    const next = new UserSettings();
    next.onboarded = BackupService.boolean(value.onboarded, '引导状态');
    next.currentBookId = BackupService.text(value.currentBookId, '当前词书', 160, true);
    next.dailyNewTarget = BackupService.integer(value.dailyNewTarget, '每日单词目标', 1, 100);
    next.autoPronounceConfigured = value.autoPronounceConfigured === undefined ? false :
      BackupService.boolean(value.autoPronounceConfigured, '朗读设置');
    next.autoPronounce = next.autoPronounceConfigured ? BackupService.boolean(value.autoPronounce, '自动朗读') : false;
    next.reminderEnabled = BackupService.boolean(value.reminderEnabled, '提醒设置');
    next.reminderHour = BackupService.integer(value.reminderHour, '提醒小时', 0, 23);
    next.reminderMinute = BackupService.integer(value.reminderMinute, '提醒分钟', 0, 59);
    next.themeMode = BackupService.choice(value.themeMode, ['system', 'light', 'dark'], '外观');
    next.learningMode = BackupService.choice(value.learningMode, ['normal', 'exam'], '学习偏好');
    next.foundation = BackupService.text(value.foundation, '英语基础', 60);
    next.examDate = BackupService.text(value.examDate, '考试日期', 20);
    next.spellingRecall = value.spellingRecall === undefined ? false : BackupService.boolean(value.spellingRecall, '拼写设置');
    next.hapticsEnabled = value.hapticsEnabled === undefined ? true : BackupService.boolean(value.hapticsEnabled, '振动设置');
    return next;
  }

  private static word(value: Word): Word {
    BackupService.object(value, '单词');
    const next = new Word();
    next.id = BackupService.integer(value.id, '单词编号', 1);
    next.word = BackupService.text(value.word, '单词', 120, true);
    next.phonetic = BackupService.text(value.phonetic, '音标', 1000);
    next.meaning = BackupService.text(value.meaning, '释义', 4000, true);
    next.example = BackupService.text(value.example, '例句', 8000);
    next.translation = BackupService.text(value.translation, '例句翻译', 8000);
    next.sourceBookId = value.sourceBookId === undefined ? '' : BackupService.text(value.sourceBookId, '来源词书', 160);
    return next;
  }

  private static object(value: Object, label: string): void {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error(`${label}格式不正确`); }
  }
  private static array<T>(value: T[], label: string, max: number): T[] {
    if (!Array.isArray(value) || value.length > max) { throw new Error(`${label}缺失或数量过多`); }
    return value;
  }
  private static text(value: string, label: string, max: number, required: boolean = false): string {
    if (typeof value !== 'string' || value.length > max || (required && !value.trim()) ||
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(value)) { throw new Error(`${label}文本不正确`); }
    return value;
  }
  private static integer(value: number, label: string, min: number = 0, max: number = Number.MAX_SAFE_INTEGER): number {
    if (!Number.isSafeInteger(value) || value < min || value > max) { throw new Error(`${label}数值不正确`); }
    return value;
  }
  private static optionalInteger(value: number, label: string): number {
    return value === undefined ? 0 : BackupService.integer(value, label);
  }
  private static boolean(value: boolean, label: string): boolean {
    if (typeof value !== 'boolean') { throw new Error(`${label}格式不正确`); }
    return value;
  }
  private static choice(value: string, allowed: string[], label: string): string {
    if (!allowed.includes(value)) { throw new Error(`${label}不支持`); }
    return value;
  }
  private static date(value: string): string {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
      !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) {
      throw new Error('备份日期格式不正确');
    }
    return value;
  }
  private static unique<T>(seen: Set<T>, value: T, label: string): void {
    if (seen.has(value)) { throw new Error(`${label}有重复项`); }
    seen.add(value);
  }
}
