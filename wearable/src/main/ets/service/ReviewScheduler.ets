import { ReviewResult, WordProgress } from '../model/AppModels';
import { strengthAfterResult } from '../utils/MemoryUtils';

/** Fixed intervals from the product plan. Timestamps always use milliseconds. */
export function baseIntervalMinutes(level: number): number {
  const intervals: number[] = [10, 1440, 4320, 10080, 20160, 43200, 86400];
  return intervals[Math.max(0, Math.min(6, Math.floor(level)))];
}

export function scheduleReview(previous: WordProgress, result: ReviewResult, now: number): WordProgress {
  const next = new WordProgress();
  next.wordId = previous.wordId;
  next.level = previous.level;
  next.strength = strengthAfterResult(previous.strength, result);
  next.favorite = previous.favorite;
  next.isNewWord = previous.isNewWord;
  let intervalMinutes = 10;
  if (result === ReviewResult.FORGET) {
    next.level = Math.max(0, next.level - 1);
    intervalMinutes = next.level === 0 ? 10 : 720;
  } else if (result === ReviewResult.FUZZY) {
    intervalMinutes = Math.round(baseIntervalMinutes(next.level) * 0.6);
  } else if (result === ReviewResult.KNOW) {
    next.level += 1;
    intervalMinutes = baseIntervalMinutes(next.level);
  } else {
    throw new Error('无效的记忆判断');
  }
  next.lastReviewAt = now;
  next.nextReviewAt = now + intervalMinutes * 60000;
  next.reviewCount = previous.reviewCount + 1;
  next.wrongCount = previous.wrongCount + (result === ReviewResult.FORGET ? 1 : 0);
  return next;
}

/** Backlog is deliberately capped instead of making hundreds of overdue words a daily obligation. */
export function adjustedNewTarget(target: number, dueCount: number): number {
  if (dueCount >= 100) {
    return 0;
  }
  return dueCount > 60 ? Math.floor(target * 0.3) : target;
}
