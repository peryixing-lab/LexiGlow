import { Word } from '../model/AppModels';

export class ClozeOption {
  wordId: number = 0;
  text: string = '';
}

export class ClozeQuestion {
  word: Word = new Word();
  sentence: string = '';
  originalSentence: string = '';
  translation: string = '';
  options: ClozeOption[] = [];
  correctId: number = 0;
}

class WordForm {
  text: string = '';
  kind: string = '';
  constructor(text: string, kind: string) { this.text = text; this.kind = kind; }
}

function inflect(word: string, kind: string): string {
  if (kind === 'plural') {
    if (/[^aeiou]y$/i.test(word)) { return `${word.slice(0, -1)}ies`; }
    return /(?:s|x|z|ch|sh)$/i.test(word) ? `${word}es` : `${word}s`;
  }
  const doubleLast = word.length <= 4 && /[^aeiou][aeiou][^aeiouwxy]$/i.test(word);
  if (kind === 'past') {
    if (/e$/i.test(word)) { return `${word}d`; }
    if (/[^aeiou]y$/i.test(word)) { return `${word.slice(0, -1)}ied`; }
    return `${word}${doubleLast ? word.slice(-1) : ''}ed`;
  }
  if (kind === 'continuous') {
    if (/ie$/i.test(word)) { return `${word.slice(0, -2)}ying`; }
    if (/[^e]e$/i.test(word)) { return `${word.slice(0, -1)}ing`; }
    return `${word}${doubleLast ? word.slice(-1) : ''}ing`;
  }
  return word;
}

function forms(word: string): WordForm[] {
  const headword = word.trim().toLowerCase();
  return [new WordForm(headword, 'base'), new WordForm(inflect(headword, 'plural'), 'plural'),
    new WordForm(inflect(headword, 'past'), 'past'), new WordForm(inflect(headword, 'continuous'), 'continuous')];
}

function escaped(word: string): string { return word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

function formPattern(word: string): RegExp {
  return new RegExp(`(^|[^A-Za-z'-])(${escaped(word)})(?=$|[^A-Za-z'-])`, 'gi');
}

/** Exact lexical boundaries prevent, for example, art being found inside cartoon. */
export function clozeContainsWord(headword: string, sentence: string): boolean {
  if (!/^[a-z][a-z'-]{1,29}$/i.test(headword.trim())) { return false; }
  return forms(headword).some((form: WordForm) => formPattern(form.text).test(sentence));
}

function partsOfSpeech(meaning: string): string[] {
  const matches = meaning.toLowerCase().match(/\b(?:adj|adv|vt|vi|v|n|a)\./g) || [];
  return matches.map((part: string) => part === 'a.' ? 'adj.' : part === 'vt.' || part === 'vi.' ? 'v.' : part);
}

function shuffle<T>(items: T[]): T[] {
  const result = items.slice();
  for (let index = result.length - 1; index > 0; index--) {
    const other = Math.floor(Math.random() * (index + 1));
    const value = result[index]; result[index] = result[other]; result[other] = value;
  }
  return result;
}

function priority(target: Word, candidate: Word): number {
  const targetParts = partsOfSpeech(target.meaning);
  const samePart = partsOfSpeech(candidate.meaning).some((part: string) => targetParts.indexOf(part) >= 0);
  const closeLength = Math.abs(target.word.length - candidate.word.length) <= 3;
  return samePart && closeLength ? 0 : samePart ? 1 : closeLength ? 2 : 3;
}

/** Creates four distinct learned-word choices. Missing/invalid examples never become questions. */
export function buildClozeQuestion(target: Word, learnedWords: Word[]): ClozeQuestion | undefined {
  if (!Number.isInteger(target.id) || target.id < 1 || !clozeContainsWord(target.word, target.example) ||
    target.translation.trim().length === 0) { return undefined; }
  const matchedForms = forms(target.word).filter((form: WordForm) => formPattern(form.text).test(target.example));
  // A single choice cannot fill both "help" and "helped" in the same sentence.
  if (new Set<string>(matchedForms.map((form: WordForm) => form.text)).size !== 1) { return undefined; }
  const matched = matchedForms[0];
  if (!matched) { return undefined; }
  const answer = matched.text;
  const candidates = shuffle(learnedWords.filter((word: Word) => word.id > 0 && word.id !== target.id &&
    /^[a-z][a-z'-]{1,29}$/i.test(word.word.trim()) && word.word.toLowerCase() !== target.word.toLowerCase()));
  candidates.sort((left: Word, right: Word) => priority(target, left) - priority(target, right));
  const options: ClozeOption[] = [];
  const spellings = new Set<string>([answer]);
  const optionIds = new Set<number>([target.id]);
  for (const word of candidates) {
    const text = inflect(word.word.trim().toLowerCase(), matched.kind);
    if (spellings.has(text) || optionIds.has(word.id)) { continue; }
    spellings.add(text);
    optionIds.add(word.id);
    const option = new ClozeOption(); option.wordId = word.id; option.text = text;
    options.push(option);
    if (options.length === 3) { break; }
  }
  if (options.length < 3) { return undefined; }
  const correct = new ClozeOption(); correct.wordId = target.id; correct.text = answer;
  options.push(correct);
  const question = new ClozeQuestion();
  question.word = target; question.correctId = target.id;
  question.originalSentence = target.example; question.translation = target.translation;
  question.options = shuffle(options);
  let sentence = target.example;
  for (const form of forms(target.word)) {
    sentence = sentence.replace(formPattern(form.text), (_match: string, prefix: string) => `${prefix}_____`);
  }
  question.sentence = sentence;
  return question;
}

export function buildClozeRound(learnedWords: Word[], limit: number = 10, preferredIds: number[] = []): ClozeQuestion[] {
  const questions: ClozeQuestion[] = [];
  const ids = new Set<number>();
  const headwords = new Set<string>();
  for (const word of shuffle(learnedWords).filter((item: Word) => preferredIds.length === 0 || preferredIds.indexOf(item.id) >= 0)) {
    const headword = word.word.trim().toLowerCase();
    if (ids.has(word.id) || headwords.has(headword)) { continue; }
    const question = buildClozeQuestion(word, learnedWords);
    if (!question) { continue; }
    ids.add(word.id); headwords.add(headword); questions.push(question);
    if (questions.length >= Math.max(1, Math.min(20, Math.floor(limit)))) { break; }
  }
  return questions;
}
