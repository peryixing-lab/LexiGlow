import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { LookupDictionaryEntry, LookupDictionaryPack } from '../model/LookupDictionaryModels';
import { articleWordCandidates } from '../utils/ArticleTokenizer';

/** The source's exchange index produces candidates, never a claim about a sentence's meaning. */
export class OfflineDictionaryService {
  private pack: LookupDictionaryPack | undefined = undefined;
  private aliases: Map<string, string[]> = new Map<string, string[]>();
  private lemmas: Map<string, string[]> = new Map<string, string[]>();
  private independentHeads: Set<string> = new Set<string>();

  async initialize(context: common.Context): Promise<LookupDictionaryPack> {
    if (this.pack) { return this.pack; }
    const bytes = await context.resourceManager.getRawFileContent('dictionary/lookup-v1.json');
    const pack = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes)) as LookupDictionaryPack;
    OfflineDictionaryService.validate(pack);
    this.index(pack);
    this.pack = pack;
    return pack;
  }

  static validate(pack: LookupDictionaryPack): void {
    if (pack.version !== 1 || !Array.isArray(pack.entries) || pack.entries.length === 0 || pack.entries.length > 50000) {
      throw new Error('离线查询词典格式不正确');
    }
    const heads = new Set<string>();
    for (const entry of pack.entries) {
      if (typeof entry.word !== 'string' || entry.word.length > 80 ||
        !/^[a-z]+(?:[-' ][a-z]+)*$/.test(entry.word) || heads.has(entry.word) ||
        typeof entry.meaning !== 'string' || !entry.meaning.trim() || entry.meaning.length > 4000 ||
        typeof entry.phonetic !== 'string' || entry.phonetic.length > 200 ||
        typeof entry.exchange !== 'string' || entry.exchange.length > 4000) {
        throw new Error('离线查询词条格式不正确');
      }
      heads.add(entry.word);
    }
  }

  private addAlias(form: string, head: string): void {
    if (!/^[a-z]+(?:[-' ][a-z]+)*$/.test(form) || form.length > 80) { return; }
    const heads = this.aliases.get(form) || [];
    if (heads.indexOf(head) < 0) { heads.push(head); this.aliases.set(form, heads); }
  }

  private index(pack: LookupDictionaryPack): void {
    this.aliases.clear(); this.lemmas.clear(); this.independentHeads.clear();
    const heads = new Set<string>(pack.entries.map((entry: LookupDictionaryEntry): string => entry.word));
    for (const entry of pack.entries) {
      // A homograph can be both an inflection and its own word: found (建立), saw (锯子), left (左边).
      if (/(^|\n)(?:n|v|vi|vt|a|adj|ad|adv|prep|pron|conj|aux|interj)\./i.test(entry.meaning)) {
        this.independentHeads.add(entry.word);
      }
      const roots: string[] = [];
      for (const part of entry.exchange.split('/')) {
        const colon = part.indexOf(':');
        if (colon < 0) { continue; }
        const kind = part.slice(0, colon);
        const forms = part.slice(colon + 1).split(',');
        for (const raw of forms) {
          const form = raw.trim().toLowerCase();
          if (kind === '0' && heads.has(form) && form !== entry.word) {
            if (roots.indexOf(form) < 0) { roots.push(form); }
            this.addAlias(entry.word, form);
          } else if (['p', 'd', 'i', '3', 'r', 't', 's'].indexOf(kind) >= 0) {
            this.addAlias(form, entry.word);
          }
        }
      }
      if (roots.length > 0) { this.lemmas.set(entry.word, roots); }
    }
    for (const entry of pack.entries) {
      if (!this.lemmas.has(entry.word) && !this.independentHeads.has(entry.word) &&
        /过去式|过去分词|现在分词|复数|比较级|最高级|第三人称/.test(entry.meaning)) {
        const roots = this.aliases.get(entry.word) || [];
        if (roots.length > 0) { this.lemmas.set(entry.word, roots); }
      }
    }
  }

  /** Canonical lemma IDs are used for surface forms; ambiguous base words stay selectable. */
  headwords(spelling: string): string[] {
    const normalized = spelling.trim().toLowerCase().replace(/’/g, "'");
    if (normalized.length > 80 || !/^[a-z]+(?:[-' ][a-z]+)*$/.test(normalized)) { return []; }
    const result: string[] = [];
    const add = (head: string): void => { if (result.indexOf(head) < 0) { result.push(head); } };
    const roots = this.lemmas.get(normalized);
    if (!roots || this.independentHeads.has(normalized)) { add(normalized); }
    if (roots) { roots.forEach((head: string): void => { add(head); }); }
    (this.aliases.get(normalized) || []).forEach((head: string): void => { add(head); });
    for (const candidate of articleWordCandidates(normalized)) {
      if (candidate === normalized) { continue; }
      const candidateRoots = this.lemmas.get(candidate);
      if (candidateRoots) { candidateRoots.forEach((head: string): void => { add(head); }); }
      else { add(candidate); }
    }
    return result.slice(0, 8);
  }
}
