import { PlanAdvice, ReviewResult, WordProgress } from '../model/AppModels';
import { strengthAfterResult } from '../utils/MemoryUtils';
import { dayStart } from '../utils/TimeUtils';

/** The deterministic interval baseline remains in use; FSRS needs calibrated historical data. */
export function baseIntervalMinutes(level: number): number {
  const intervals: number[] = [10, 1440, 4320, 10080, 20160, 43200, 86400];
  return intervals[Math.max(0, Math.min(6, Math.floor(level)))];
}

export function scheduleReview(previous: WordProgress, result: ReviewResult, now: number,
  responseMs: number = 0): WordProgress {
  const next = new WordProgress();
  next.wordId = previous.wordId;
  next.level = previous.level;
  next.strength = strengthAfterResult(previous.strength, result);
  next.favorite = previous.favorite;
  next.isNewWord = previous.isNewWord;
  next.lastResponseMs = Math.max(0, Math.min(300000, Math.floor(Number.isFinite(responseMs) ? responseMs : 0)));
  next.consecutiveFailures = result === ReviewResult.KNOW ? 0 : previous.consecutiveFailures + 1;
  next.consecutiveKnown = result === ReviewResult.KNOW ? previous.consecutiveKnown + 1 : 0;
  const hesitant = next.lastResponseMs > 3500 || next.consecutiveFailures >= 2;
  next.hesitationCount = previous.hesitationCount + (hesitant ? 1 : 0);
  let intervalMinutes = 10;
  if (result === ReviewResult.FORGET) {
    next.level = Math.max(0, next.level - 1);
    intervalMinutes = next.level === 0 ? 10 : 720;
  } else if (result === ReviewResult.FUZZY) {
    intervalMinutes = Math.round(baseIntervalMinutes(next.level) * 0.6);
  } else if (result === ReviewResult.KNOW) {
    next.level += 1;
    intervalMinutes = baseIntervalMinutes(next.level);
    if (next.lastResponseMs > 4000) {
      next.strength = Math.min(100, previous.strength + 8);
      intervalMinutes = Math.round(intervalMinutes * 0.8);
    } else if (next.consecutiveKnown >= 3 && previous.lastReviewAt > 0 &&
      now - previous.lastReviewAt >= 14 * 86400000) {
      intervalMinutes = Math.round(intervalMinutes * 1.2);
    }
  } else {
    throw new Error('无效的记忆判断');
  }
  next.lastReviewAt = now;
  next.nextReviewAt = now + intervalMinutes * 60000;
  next.reviewCount = previous.reviewCount + 1;
  next.wrongCount = previous.wrongCount + (result === ReviewResult.FORGET ? 1 : 0);
  return next;
}


export function dailyReviewQuota(backlog: number, budget: string): number {
  const cap = budget === 'busy' ? 15 : (budget === 'free' ? 100 : 60);
  return Math.min(cap, backlog > 100 ? Math.ceil(backlog * 0.2) : backlog);
}

/** Advice is visible and optional: a countdown never silently increases the saved daily target. */
export function examPlanAdvice(examDate: string, remainingWords: number, dailyTarget: number,
  now: number = Date.now()): PlanAdvice {
  const advice = new PlanAdvice();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(examDate);
  if (!match) {
    return advice;
  }
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  if (date.getFullYear() !== Number(match[1]) || date.getMonth() !== Number(match[2]) - 1 ||
    date.getDate() !== Number(match[3])) {
    return advice;
  }
  const days = Math.round((date.getTime() - dayStart(now)) / 86400000);
  advice.daysRemaining = days;
  if (days < 0) {
    advice.message = '目标日期已过，可以按自己的节奏继续巩固。';
    return advice;
  }
  const needed = Math.ceil(Math.max(0, remainingWords) / Math.max(1, days));
  advice.suggestedNewTarget = Math.max(0, Math.min(100, needed));
  advice.mode = needed > dailyTarget * 1.5 || days <= 14 ? 'sprint' :
    (needed > dailyTarget || days <= 45 ? 'accelerated' : 'stable');
  advice.message = advice.mode === 'sprint' ? '冲刺建议：优先巩固弱词，再安排可承受的新词量。' :
    (advice.mode === 'accelerated' ? '加速建议：有空时适当增加新词，并保留复习时间。' : '平稳建议：保持当前节奏，逐日巩固。');
  return advice;
}
