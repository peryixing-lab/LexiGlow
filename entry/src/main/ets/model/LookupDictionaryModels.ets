/** Query-only words never become a learning book or a daily task by being bundled. */
export class LookupDictionaryEntry {
  word: string = '';
  phonetic: string = '';
  meaning: string = '';
  exchange: string = '';
}

export class LookupDictionaryPack {
  version: number = 1;
  sourceCommit: string = '';
  entries: LookupDictionaryEntry[] = [];
}
