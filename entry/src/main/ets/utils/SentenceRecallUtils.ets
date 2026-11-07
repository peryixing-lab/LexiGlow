import { SentenceMemory, SentenceRecallAttempt } from '../model/ExperienceModels';
import { dayStart } from './TimeUtils';

export class SentenceRecallTarget {
  text: string = '';
  start: number = -1;
  constructor(text: string, start: number) { this.text = text; this.start = start; }
}

export class OriginalSentenceSelection {
  sentence: string = '';
  targetText: string = '';
  targetStart: number = -1;
}

/** UTF-16 offsets match ArticleToken.start and string.slice, including repeated words. */
export function originalSentenceSelection(body: string, paragraphKey: string, tokenStart: number): OriginalSentenceSelection {
  const selection = new OriginalSentenceSelection();
  const line = body.split('\n')[Number(paragraphKey.split(':')[0])] || '';
  const position = Math.max(0, Math.min(tokenStart, line.length));
  let start = position; let end = position;
  while (start > 0 && !/[.!?。！？]/.test(line[start - 1])) { start--; }
  while (end < line.length && !/[.!?。！？]/.test(line[end])) { end++; }
  const last = Math.min(line.length, end + 1);
  if (last - start <= 2000) {
    const raw = line.slice(start, last);
    const leading = raw.length - raw.trimStart().length;
    selection.sentence = raw.trim();
    selection.targetStart = position - start - leading;
  } else {
    const clipStart = Math.max(start, position - 800);
    const clipEnd = Math.min(last, clipStart + 1998);
    const prefix = clipStart > start ? '…' : '';
    selection.sentence = `${prefix}${line.slice(clipStart, clipEnd).trim()}${clipEnd < last ? '…' : ''}`;
    const leading = line.slice(clipStart, clipEnd).length - line.slice(clipStart, clipEnd).trimStart().length;
    selection.targetStart = prefix.length + position - clipStart - leading;
  }
  const token = /^[A-Za-z]+(?:['’][A-Za-z]+)*/.exec(line.slice(position));
  selection.targetText = token ? token[0] : '';
  if (!selection.targetText || selection.sentence.slice(selection.targetStart,
    selection.targetStart + selection.targetText.length) !== selection.targetText) {
    selection.targetText = ''; selection.targetStart = -1;
  }
  return selection;
}

export function sentenceTargetChoices(sentence: string): SentenceRecallTarget[] {
  const result: SentenceRecallTarget[] = [];
  const pattern = /[A-Za-z]+(?:['’][A-Za-z]+)*/g;
  let match = pattern.exec(sentence);
  while (match !== null) {
    if (match[0].length <= 80) { result.push(new SentenceRecallTarget(match[0], match.index)); }
    match = pattern.exec(sentence);
  }
  return result;
}

export function hasSentenceTarget(item: SentenceMemory): boolean {
  if (!Number.isInteger(item.targetStart) || item.targetStart < 0 ||
    !/^[A-Za-z]+(?:['’][A-Za-z]+)*$/.test(item.targetText) || item.targetText.length > 80) { return false; }
  const target = sentenceTargetChoices(item.sentence).find((choice: SentenceRecallTarget): boolean =>
    choice.start === item.targetStart && choice.text === item.targetText);
  return target !== undefined;
}

/** Hide all identical answer forms so a repeated occurrence cannot reveal the answer. */
export function maskedMemorySentence(item: SentenceMemory): string {
  if (!hasSentenceTarget(item)) { return item.sentence; }
  let result = ''; let offset = 0;
  for (const choice of sentenceTargetChoices(item.sentence)) {
    if (choice.text.toLowerCase().replace(/’/g, "'") !== item.targetText.toLowerCase().replace(/’/g, "'")) { continue; }
    result += item.sentence.slice(offset, choice.start) + '_____';
    offset = choice.start + choice.text.length;
  }
  return result + item.sentence.slice(offset);
}

export function sentenceRecallMatches(target: string, answer: string): boolean {
  return target.toLowerCase().replace(/’/g, "'") === answer.trim().toLowerCase().replace(/’/g, "'");
}

/** No same-day collection or repeat; independent success waits longer than a hinted answer. */
export function recommendedSentenceMemories(memories: SentenceMemory[], attempts: SentenceRecallAttempt[],
  now: number = Date.now(), limit: number = 5): SentenceMemory[] {
  const today = dayStart(now);
  const practicedToday = new Set<string>();
  const latest = new Map<string, SentenceRecallAttempt>();
  for (const attempt of attempts) {
    if (attempt.recordedAt >= today && attempt.recordedAt <= now) { practicedToday.add(attempt.sentenceId); }
    const previous = latest.get(attempt.sentenceId);
    if (attempt.recordedAt <= now && (!previous || previous.recordedAt < attempt.recordedAt)) {
      latest.set(attempt.sentenceId, attempt);
    }
  }
  const afterDays = (timestamp: number, days: number): number => {
    const date = new Date(dayStart(timestamp)); date.setDate(date.getDate() + days); return date.getTime();
  };
  const due = (item: SentenceMemory): number => {
    const lastAttempt = latest.get(item.id);
    if (!lastAttempt) { return afterDays(item.createdAt, 1); }
    const days = lastAttempt.correct ? (lastAttempt.hinted ? 3 : 7) : 1;
    return afterDays(lastAttempt.recordedAt, days);
  };
  return memories.filter((item: SentenceMemory): boolean => item.recallEnabled && hasSentenceTarget(item) &&
    item.createdAt < today && due(item) <= today)
    .sort((a: SentenceMemory, b: SentenceMemory): number => due(a) - due(b) || a.createdAt - b.createdAt || a.id.localeCompare(b.id))
    .slice(0, Math.max(0, Math.min(5 - practicedToday.size, Math.floor(limit))));
}
