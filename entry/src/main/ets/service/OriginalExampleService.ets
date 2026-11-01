import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Word } from '../model/AppModels';
import { clozeContainsWord } from '../utils/ClozeBuilder';

export class OriginalExample {
  headword: string = '';
  example: string = '';
  translation: string = '';
}

class OriginalExamplePack {
  version: number = 1;
  license: string = '';
  examples: OriginalExample[] = [];
}

/** Authored local material supplements missing examples without overwriting imported content. */
export class OriginalExampleService {
  private static examples?: Map<string, OriginalExample>;
  private static loading?: Promise<Map<string, OriginalExample>>;

  private static async load(context: common.Context): Promise<Map<string, OriginalExample>> {
    if (OriginalExampleService.examples) { return OriginalExampleService.examples; }
    if (OriginalExampleService.loading) { return OriginalExampleService.loading; }
    const loading = OriginalExampleService.read(context);
    OriginalExampleService.loading = loading;
    try {
      const examples = await loading;
      OriginalExampleService.examples = examples;
      return examples;
    } finally { OriginalExampleService.loading = undefined; }
  }

  private static async read(context: common.Context): Promise<Map<string, OriginalExample>> {
    const bytes = await context.resourceManager.getRawFileContent('examples/original-examples-v1.json');
    const pack = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes)) as OriginalExamplePack;
    if (pack.version !== 1 || !Array.isArray(pack.examples)) { throw new Error('原创例句包格式错误'); }
    const examples = new Map<string, OriginalExample>();
    for (const example of pack.examples) {
      if (typeof example.headword !== 'string' || typeof example.example !== 'string' ||
        typeof example.translation !== 'string' || example.translation.trim().length === 0 ||
        !clozeContainsWord(example.headword, example.example)) { continue; }
      examples.set(example.headword.toLowerCase(), example);
    }
    return examples;
  }

  static async supplement(context: common.Context, words: Word[]): Promise<Word[]> {
    const examples = await OriginalExampleService.load(context);
    return words.map((source: Word) => {
      if (source.example.trim().length > 0 && source.translation.trim().length > 0 &&
        clozeContainsWord(source.word, source.example)) { return source; }
      const example = examples.get(source.word.trim().toLowerCase());
      if (!example) { return source; }
      const word = new Word();
      word.id = source.id; word.word = source.word; word.meaning = source.meaning;
      word.phonetic = source.phonetic; word.sourceBookId = source.sourceBookId;
      word.example = example.example; word.translation = example.translation;
      return word;
    });
  }
}
