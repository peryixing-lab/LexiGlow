import { Word } from '../model/AppModels';
import { matchesMeaning, meaningAnswers } from '../utils/MeaningMatcher';

/** An independent recall exercise. It never writes progress, review history, or daily counts. */
export class ChallengeService {
  private words: Word[] = [];
  private index: number = 0;
  private correctCount: number = 0;
  private answered: boolean = false;
  private lastResult: boolean = false;

  start(words: Word[]): void {
    const candidates: Word[] = [];
    const ids = new Set<number>();
    for (const word of words) {
      if (!Number.isInteger(word.id) || word.id < 1 || ids.has(word.id) ||
        word.word.trim().length === 0 || meaningAnswers(word.meaning).length === 0) {
        continue;
      }
      ids.add(word.id);
      candidates.push(this.copyWord(word));
    }
    for (let index = candidates.length - 1; index > 0; index--) {
      const other = Math.floor(Math.random() * (index + 1));
      const previous = candidates[index];
      candidates[index] = candidates[other];
      candidates[other] = previous;
    }
    this.words = candidates;
    this.index = 0;
    this.correctCount = 0;
    this.answered = false;
    this.lastResult = false;
  }

  currentWord(): Word | undefined {
    return this.index < this.words.length ? this.copyWord(this.words[this.index]) : undefined;
  }

  getIndex(): number {
    return this.index;
  }

  getTotal(): number {
    return this.words.length;
  }

  getCorrectCount(): number {
    return this.correctCount;
  }

  isAnswered(): boolean {
    return this.answered;
  }

  submit(answer: string): boolean {
    if (this.answered) {
      return this.lastResult;
    }
    if (answer.trim().length === 0) {
      throw new Error('请输入一个中文意思');
    }
    if (this.isComplete()) {
      throw new Error('本轮挑战已结束');
    }
    this.lastResult = matchesMeaning(answer, this.words[this.index].meaning);
    this.answered = true;
    if (this.lastResult) {
      this.correctCount++;
    }
    return this.lastResult;
  }

  next(): void {
    if (this.isComplete()) {
      return;
    }
    if (!this.answered) {
      throw new Error('请先提交答案');
    }
    this.index++;
    this.answered = false;
    this.lastResult = false;
  }

  isComplete(): boolean {
    return this.index >= this.words.length;
  }

  getLastResult(): boolean {
    return this.lastResult;
  }

  private copyWord(source: Word): Word {
    const word = new Word();
    word.id = source.id;
    word.word = source.word;
    word.phonetic = source.phonetic;
    word.meaning = source.meaning;
    word.example = source.example;
    word.translation = source.translation;
    word.sourceBookId = source.sourceBookId;
    return word;
  }
}
