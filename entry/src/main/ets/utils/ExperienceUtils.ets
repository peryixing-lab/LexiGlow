import { PracticeAttempt, PracticeRecommendation, SkillEvidence } from '../model/ExperienceModels';
import { dayStart } from './TimeUtils';
import { StudySession, ReviewRecord, StudyItem } from '../model/AppModels';

export function experienceId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
}

export function practiceLabel(mode: string): string {
  if (mode === 'meaning') { return '认义'; }
  if (mode === 'dictation') { return '听音写词'; }
  if (mode === 'spelling') { return '拼写'; }
  return '语境';
}

/** Only scored attempts count; hearing TTS or opening an answer is not proof of mastery. */
export function skillEvidence(attempts: PracticeAttempt[]): SkillEvidence[] {
  return ['meaning', 'dictation', 'spelling', 'cloze'].map((mode: string): SkillEvidence => {
    const evidence = new SkillEvidence(); evidence.mode = mode; evidence.label = practiceLabel(mode);
    const recent = attempts.filter((attempt: PracticeAttempt) => attempt.mode === mode).slice(0, 10);
    evidence.total = recent.length;
    evidence.correct = recent.filter((attempt: PracticeAttempt) => attempt.correct).length;
    evidence.hinted = recent.filter((attempt: PracticeAttempt) => attempt.hinted).length;
    return evidence;
  });
}

export function recommendPractice(attempts: PracticeAttempt[], session: StudySession,
  records: ReviewRecord[], now: number = Date.now()): PracticeRecommendation {
  const recommendation = new PracticeRecommendation();
  const completedIds = session.items.slice(0, session.index).map((item: StudyItem) => item.word.id);
  const weak = records.filter((record: ReviewRecord) => record.reviewAt >= Math.max(dayStart(now), session.startedAt) &&
    record.reviewAt <= now && completedIds.indexOf(record.wordId) >= 0 && (record.result < 2 || record.responseMs > 3500));
  if (weak.length > 0) {
    recommendation.wordIds = Array.from(new Set<number>(weak.map((record: ReviewRecord) => record.wordId))).slice(0, 5);
    recommendation.mode = 'meaning'; recommendation.title = '把刚才犹豫的词，再回忆一次';
    recommendation.reason = `本轮有 ${recommendation.wordIds.length} 个词需要再巩固，试着写出一个中文意思。`;
    return recommendation;
  }
  // Require two recent errors in the same mode. A later independent success resolves that word.
  const recent = attempts.filter((attempt: PracticeAttempt) => now - attempt.recordedAt <= 7 * 86400000);
  for (const mode of ['dictation', 'spelling', 'cloze', 'meaning']) {
    const latest = new Map<number, PracticeAttempt>();
    recent.filter((attempt: PracticeAttempt) => attempt.mode === mode).forEach((attempt: PracticeAttempt) => {
      if (!latest.has(attempt.wordId)) { latest.set(attempt.wordId, attempt); }
    });
    const weakIds = Array.from(latest.values()).filter((attempt: PracticeAttempt) => !attempt.correct || attempt.hinted)
      .filter((attempt: PracticeAttempt) => recent.filter((item: PracticeAttempt) => item.wordId === attempt.wordId &&
        item.mode === mode && !item.correct).length >= 2).map((attempt: PracticeAttempt) => attempt.wordId).slice(0, 5);
    if (weakIds.length > 0) {
      recommendation.mode = mode; recommendation.wordIds = weakIds;
      recommendation.title = `再练一下${practiceLabel(mode)}`;
      recommendation.reason = `这 ${weakIds.length} 个词近 7 天在这类练习中至少答错过两次。练习可随时跳过。`;
      return recommendation;
    }
  }
  return recommendation;
}

/** Locate the clicked occurrence in its original line, including repeated words. */
export function originalSentence(body: string, paragraphKey: string, tokenStart: number): string {
  const line = body.split('\n')[Number(paragraphKey.split(':')[0])] || '';
  const position = Math.max(0, Math.min(tokenStart, line.length));
  let start = position; let end = position;
  while (start > 0 && !/[.!?。！？]/.test(line[start - 1])) { start--; }
  while (end < line.length && !/[.!?。！？]/.test(line[end])) { end++; }
  const last = Math.min(line.length, end + 1);
  if (last - start <= 2000) { return line.slice(start, last).trim(); }
  const clipStart = Math.max(start, position - 800);
  const clipEnd = Math.min(last, clipStart + 1998);
  return `${clipStart > start ? '…' : ''}${line.slice(clipStart, clipEnd).trim()}${clipEnd < last ? '…' : ''}`;
}
