export enum ReviewResult {
  FORGET = 0,
  FUZZY = 1,
  KNOW = 2
}

export class Word {
  id: number = 0;
  word: string = '';
  phonetic: string = '';
  meaning: string = '';
  example: string = '';
  translation: string = '';
  sourceBookId: string = '';
}

export class WordBook {
  id: string = '';
  name: string = '';
  category: string = '';
  description: string = '';
  totalCount: number = 0;
  learnedCount: number = 0;
}

export class WordProgress {
  wordId: number = 0;
  strength: number = 0;
  level: number = 0;
  nextReviewAt: number = 0;
  lastReviewAt: number = 0;
  reviewCount: number = 0;
  wrongCount: number = 0;
  favorite: boolean = false;
  isNewWord: boolean = false;
}

export class ReviewRecord {
  id: number = 0;
  wordId: number = 0;
  result: number = ReviewResult.FORGET;
  reviewAt: number = 0;
  responseMs: number = 0;
  previousLevel: number = 0;
  nextLevel: number = 0;
  previousStrength: number = 0;
  nextStrength: number = 0;
}

export class DailyPlan {
  date: string = '';
  newTarget: number = 20;
  reviewTarget: number = 0;
  newDone: number = 0;
  reviewDone: number = 0;
  estimatedMinutes: number = 10;
  budget: string = 'normal';
}

export class UserSettings {
  onboarded: boolean = false;
  currentBookId: string = 'cet4';
  dailyNewTarget: number = 20;
  autoPronounce: boolean = true;
  reminderEnabled: boolean = false;
  reminderHour: number = 21;
  reminderMinute: number = 0;
  themeMode: string = 'system';
  learningMode: string = 'normal';
  foundation: string = 'beginner';
  examDate: string = '';
}

export class StudyItem {
  word: Word = new Word();
  type: string = 'new';
}

export class StudySession {
  items: StudyItem[] = [];
  index: number = 0;
  mode: string = '';
  startedAt: number = 0;
  completed: number = 0;
}

export class DaySummary {
  date: string = '';
  newCount: number = 0;
  reviewCount: number = 0;
  knownCount: number = 0;
  totalCount: number = 0;
  durationMs: number = 0;
}

export class Statistics {
  totalLearned: number = 0;
  mastered: number = 0;
  streak: number = 0;
  weekMastered: number = 0;
  successRate: number = 0;
  strengthCounts: number[] = [0, 0, 0, 0];
  days: DaySummary[] = [];
}

export class AppSnapshot {
  settings: UserSettings = new UserSettings();
  books: WordBook[] = [];
  plan: DailyPlan = new DailyPlan();
  dueCount: number = 0;
  favoriteCount: number = 0;
  newWordCount: number = 0;
  stats: Statistics = new Statistics();
  dailyWord: Word = new Word();
}

export class DictionaryBook {
  id: string = '';
  name: string = '';
  category: string = '';
  description: string = '';
  words: Word[] = [];
}

export class DictionaryCatalog {
  version: number = 1;
  books: DictionaryBook[] = [];
}

export class DataExport {
  format: string = 'ciying-learning-backup';
  version: number = 1;
  exportedAt: number = 0;
  settings: UserSettings = new UserSettings();
  books: DictionaryBook[] = [];
  progress: WordProgress[] = [];
  records: ReviewRecord[] = [];
  plans: DailyPlan[] = [];
  days: DaySummary[] = [];
  session: StudySession = new StudySession();
}
