import { Word } from '../model/AppModels';

/** Read one dictionary sense, omitting abbreviated part-of-speech labels. */
export function audioCoreMeaning(meaning: string): string {
  const first = meaning.split(/[；;\n]/)[0].trim()
    .replace(/^(?:[a-z]+\.\s*)+/i, '').split(/[，,]/)[0].trim();
  return first.length <= 120 ? first : first.substring(0, 120);
}

/** A blank or translated example must not be sent to the English voice engine. */
export function audioEnglishExample(example: string): string {
  const text = example.trim();
  return text.length <= 500 && /[a-zA-Z]/.test(text) && !/[\u3400-\u9fff]/.test(text) ? text : '';
}

export function copyAudioWord(value: Word): Word {
  const word = new Word();
  word.id = value.id;
  word.word = value.word;
  word.phonetic = value.phonetic;
  word.meaning = value.meaning;
  word.example = value.example;
  word.translation = value.translation;
  word.sourceBookId = value.sourceBookId;
  return word;
}

export function audioFlowQueue(words: Word[]): Word[] {
  return words.filter((word: Word) => word.word.trim().length > 0 && word.word.trim().length <= 120 &&
    /[a-zA-Z]/.test(word.word) && audioCoreMeaning(word.meaning).length > 0)
    .map((word: Word) => copyAudioWord(word));
}
