import { PracticeAttempt, SentenceMemory, ReadingProgress } from './ExperienceModels';
import { Article } from './ArticleModels';
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

export class LearnedDate {
  date: string = '';
  count: number = 0;
}

export class LearnedWord {
  word: Word = new Word();
  firstLearnedAt: number = 0;
  strength: number = 0;
  familyKey: string = '';
  nextReviewAt: number = 0;
}

export class MistakeWord {
  word: Word = new Word();
  wrongCount: number = 0;
  lastReviewAt: number = 0;
  strength: number = 0;
}

export class ReviewUndo {
  recordId: number = 0;
  sessionExists: boolean = false;
  wordId: number = 0;
  progress: WordProgress | undefined = undefined;
  plan: DailyPlan | undefined = undefined;
  day: DaySummary | undefined = undefined;
  date: string = '';
  glow: GlowRecord | undefined = undefined;
  glowDate: string = '';
  mastered: boolean = false;
  session: StudySession = new StudySession();
}

export class WordIdentity {
  id: number = 0;
  word: string = '';
}

export class WordRelation {
  word: Word = new Word();
  strength: number = 0;
  learned: boolean = false;
}

export class ConfusingWord {
  word: Word = new Word();
  note: string = '';
}

export class WordEnrichment {
  coreMeanings: string[] = [];
  collocations: string[] = [];
  root: string = '';
  prefix: string = '';
  suffix: string = '';
  analysis: string = '';
  familyWords: WordRelation[] = [];
  confusingWords: ConfusingWord[] = [];
  /** No badge is shown until a verifiable exam-frequency source is available. */
  examFrequency: string = '';
}

export class PracticeResult {
  id: number = 0;
  mode: string = 'spelling';
  correct: number = 0;
  total: number = 0;
  durationMs: number = 0;
  completedAt: number = 0;
}

export class GlowRecord {
  date: string = '';
  earnedOn: string = '';
  reason: string = '';
}

export class PlanAdvice {
  mode: string = 'stable';
  daysRemaining: number = -1;
  suggestedNewTarget: number = 0;
  message: string = '';
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
  hesitationCount: number = 0;
  lastResponseMs: number = 0;
  consecutiveFailures: number = 0;
  consecutiveKnown: number = 0;
}

export class MasteredWord {
  wordId: number = 0;
  firstMasteredAt: number = 0;
}

export class ReviewRecord {
  id: number = 0;
  wordId: number = 0;
  result: number = ReviewResult.FORGET;
  reviewAt: number = 0;
  responseMs: number = 0;
  itemType: string = 'review';
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
  /** Largest starting workload observed today; keeps the buffer from vanishing mid-session. */
  backlogCount: number = 0;
}

export class UserSettings {
  onboarded: boolean = false;
  currentBookId: string = 'cet4';
  dailyNewTarget: number = 20;
  autoPronounce: boolean = false;
  /** Distinguishes a user's choice from the former default-on behavior. */
  autoPronounceConfigured: boolean = false;
  reminderEnabled: boolean = false;
  reminderHour: number = 21;
  reminderMinute: number = 0;
  themeMode: string = 'system';
  learningMode: string = 'normal';
  foundation: string = 'beginner';
  examDate: string = '';
  spellingRecall: boolean = false;
  hapticsEnabled: boolean = true;
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
  /** Total learning judgments: newCount + reviewCount. */
  totalCount: number = 0;
  durationMs: number = 0;
  /** Visual restoration only; never counted as an actual learning day. */
  glowing: boolean = false;
}

export class Statistics {
  totalLearned: number = 0;
  mastered: number = 0;
  streak: number = 0;
  weekMastered: number = 0;
  successRate: number = 0;
  strengthCounts: number[] = [0, 0, 0, 0];
  days: DaySummary[] = [];
  glowDays: string[] = [];
}

export class AppSnapshot {
  mistakeCount: number = 0;
  settings: UserSettings = new UserSettings();
  books: WordBook[] = [];
  plan: DailyPlan = new DailyPlan();
  dueCount: number = 0;
  favoriteCount: number = 0;
  newWordCount: number = 0;
  stats: Statistics = new Statistics();
  dailyWord: Word = new Word();
  advice: PlanAdvice = new PlanAdvice();
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
  version: number = 4;
  dictionaryVersion: number = 0;
  compact: boolean = false;
  wordIdentities: WordIdentity[] = [];
  words: Word[] = [];
  masteredWords: MasteredWord[] = [];
  exportedAt: number = 0;
  settings: UserSettings = new UserSettings();
  books: DictionaryBook[] = [];
  progress: WordProgress[] = [];
  records: ReviewRecord[] = [];
  plans: DailyPlan[] = [];
  days: DaySummary[] = [];
  session: StudySession = new StudySession();
  practiceResults: PracticeResult[] = [];
  glowRecords: GlowRecord[] = [];
  practiceAttempts: PracticeAttempt[] = [];
  sentences: SentenceMemory[] = [];
  articles: Article[] = [];
  readingProgress: ReadingProgress[] = [];
}
