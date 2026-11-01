import { Word } from '../model/AppModels';

export const WORD_ALPHABET: string[] = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

export class AlphabetWordRow {
  key: string = '';
  letter: string = '';
  firstInLetter: boolean = false;
  words: Word[] = [];
}

export class AlphabetWordIndex {
  rows: AlphabetWordRow[] = [];
  firstRows: Map<string, number> = new Map<string, number>();
  letters: string[] = WORD_ALPHABET.slice();
}

export function wordInitial(spelling: string): string {
  const initial = spelling.trim().charAt(0).toUpperCase();
  return /^[A-Z]$/.test(initial) ? initial : '#';
}

function wordOrder(first: Word, second: Word): number {
  const firstInitial = wordInitial(first.word);
  const secondInitial = wordInitial(second.word);
  const firstRank = firstInitial === '#' ? 26 : firstInitial.charCodeAt(0) - 65;
  const secondRank = secondInitial === '#' ? 26 : secondInitial.charCodeAt(0) - 65;
  if (firstRank !== secondRank) { return firstRank - secondRank; }
  const a = first.word.trim().toLowerCase();
  const b = second.word.trim().toLowerCase();
  return a < b ? -1 : a > b ? 1 : first.id - second.id;
}

/** Each row belongs to one letter, including multi-column tablet layouts. Never truncates results. */
export function buildWordAlphabet(words: Word[], columns: number = 1): AlphabetWordIndex {
  const index = new AlphabetWordIndex();
  const width = Number.isFinite(columns) ? Math.max(1, Math.min(3, Math.floor(columns))) : 1;
  const sorted = words.slice().sort(wordOrder);
  for (let offset = 0; offset < sorted.length;) {
    const row = new AlphabetWordRow();
    row.letter = wordInitial(sorted[offset].word);
    row.firstInLetter = !index.firstRows.has(row.letter);
    if (row.firstInLetter) { index.firstRows.set(row.letter, index.rows.length); }
    while (offset < sorted.length && row.words.length < width && wordInitial(sorted[offset].word) === row.letter) {
      row.words.push(sorted[offset++]);
    }
    row.key = `${row.letter}:${row.words.map((word: Word) => word.id.toString()).join('-')}`;
    index.rows.push(row);
  }
  if (index.firstRows.has('#')) { index.letters.push('#'); }
  return index;
}

/** A missing letter jumps forward to the nearest present group, or to the final group. */
export function alphabetRowForLetter(index: AlphabetWordIndex, letter: string): number {
  const selected = index.letters.indexOf(letter);
  if (selected < 0 || index.rows.length === 0) { return -1; }
  for (let position = selected; position < index.letters.length; position++) {
    const row = index.firstRows.get(index.letters[position]);
    if (row !== undefined) { return row; }
  }
  for (let position = selected - 1; position >= 0; position--) {
    const row = index.firstRows.get(index.letters[position]);
    if (row !== undefined) { return row; }
  }
  return -1;
}
