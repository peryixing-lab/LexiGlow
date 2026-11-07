import { PracticeClock } from '../utils/PracticeClock';
import { DatabaseManager } from '../repository/DatabaseManager';
import { ExperienceRepository } from '../repository/ExperienceRepository';
import { PracticeAttempt, SentenceMemory, ReadingProgress, SentenceRecallAttempt } from '../model/ExperienceModels';
import { experienceId } from '../utils/ExperienceUtils';
import { recommendedSentenceMemories } from '../utils/SentenceRecallUtils';

export class ExperienceService {
  private static instance: ExperienceService = new ExperienceService();
  private repository: ExperienceRepository | undefined = undefined;
  static getInstance(): ExperienceService { return ExperienceService.instance; }
  initialize(database: DatabaseManager): void { this.repository = new ExperienceRepository(database); }
  private repo(): ExperienceRepository {
    if (!this.repository) { throw new Error('学习记录尚未载入'); } return this.repository;
  }
  attempts(wordId: number = 0): Promise<PracticeAttempt[]> { return this.repo().attempts(wordId); }
  saveAttempt(attempt: PracticeAttempt): Promise<void> { return this.repo().saveAttempt(attempt); }
  sentences(wordId: number = 0): Promise<SentenceMemory[]> { return this.repo().sentences(wordId); }
  saveSentence(sentence: SentenceMemory): Promise<void> { return this.repo().saveSentence(sentence); }
  removeSentence(id: string): Promise<void> { return this.repo().removeSentence(id); }
  recallAttempts(sentenceId: string = ''): Promise<SentenceRecallAttempt[]> { return this.repo().recallAttempts(sentenceId); }
  saveRecallAttempt(attempt: SentenceRecallAttempt, targetText: string = '', targetStart: number = -1): Promise<void> {
    return this.repo().saveRecallAttempt(attempt, targetText, targetStart);
  }
  async recallRecommendations(now: number = Date.now()): Promise<SentenceMemory[]> {
    const memories = await this.repo().sentences(); const attempts = await this.repo().recallAttempts();
    return recommendedSentenceMemories(memories, attempts, now);
  }
  reading(articleId: number): Promise<ReadingProgress> { return this.repo().reading(articleId); }
  savePosition(articleId: number, paragraphIndex: number): Promise<void> { return this.repo().savePosition(articleId, paragraphIndex); }
  saveReading(progress: ReadingProgress): Promise<void> { return this.repo().saveReading(progress); }
}

/** One stable attempt per question; failed writes can be retried without changing the answer. */
export class SentenceRecallJournal {
  private pending: SentenceRecallAttempt | undefined = undefined;
  private clock: PracticeClock = new PracticeClock();
  private targetText: string = '';
  private targetStart: number = -1;
  beginQuestion(): void { this.clock.reset(); this.clock.resume(); this.pending = undefined; }
  pause(): void { this.clock.pause(); }
  resume(): void { if (!this.pending) { this.clock.resume(); } }
  async record(sentenceId: string, correct: boolean, hinted: boolean, targetText: string = '', targetStart: number = -1): Promise<void> {
    if (!this.pending) {
      const attempt = new SentenceRecallAttempt(); attempt.id = experienceId('sentence_recall'); attempt.sentenceId = sentenceId;
      attempt.correct = correct; attempt.hinted = hinted; attempt.recordedAt = Date.now();
      this.clock.pause(); attempt.durationMs = this.clock.duration(); this.pending = attempt;
      this.targetText = targetText; this.targetStart = targetStart;
    }
    await ExperienceService.getInstance().saveRecallAttempt(this.pending, this.targetText, this.targetStart);
  }
}

/** Keeps one immutable answer for retries; a failed write never becomes a second attempt. */
export class PracticeJournal {
  private pending: PracticeAttempt | undefined = undefined;
  private clock: PracticeClock = new PracticeClock();
  beginQuestion(): void { this.clock.reset(); this.clock.resume(); this.pending = undefined; }
  pause(): void { this.clock.pause(); }
  resume(): void { if (!this.pending) { this.clock.resume(); } }
  async record(wordId: number, mode: string, correct: boolean, hinted: boolean): Promise<void> {
    if (!this.pending) {
      const attempt = new PracticeAttempt(); attempt.id = experienceId('attempt'); attempt.wordId = wordId;
      attempt.mode = mode; attempt.correct = correct; attempt.hinted = hinted;
      attempt.recordedAt = Date.now(); this.clock.pause(); attempt.durationMs = this.clock.duration();
      this.pending = attempt;
    }
    await ExperienceService.getInstance().saveAttempt(this.pending);
  }
}
