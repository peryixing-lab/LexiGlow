/* Runs the actual ArkTS lookup/index/import code; SQLite protects the ID and task invariants. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const root = path.resolve(__dirname, '..');
class LookupRows {
  constructor(rows) { this.rows = rows; this.index = -1; this.columnNames = Object.keys(rows[0] || {}); }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { return ++this.index < this.rows.length; }
  getColumnIndex(name) { const i = this.columnNames.indexOf(name); assert.ok(i >= 0, name); return i; }
  getLong(i) { return Number(this.rows[this.index][this.columnNames[i]] || 0); }
  getDouble(i) { return this.getLong(i); }
  getString(i) { return String(this.rows[this.index][this.columnNames[i]] || ''); }
  close() {}
}
class LookupStore {
  constructor() { this.db = new DatabaseSync(':memory:'); }
  get version() { return this.db.prepare('PRAGMA user_version').get().user_version; }
  async executeSql(sql, args = []) { this.db.prepare(sql).run(...args); }
  async querySql(sql, args = []) { return new LookupRows(this.db.prepare(sql).all(...args)); }
  async batchInsert(table, rows) {
    if (!rows.length) return 0;
    const columns = Object.keys(rows[0]);
    const insert = this.db.prepare(`INSERT INTO ${table}(${columns}) VALUES(${columns.map(() => '?')})`);
    for (const row of rows) insert.run(...columns.map(name => row[name]));
    return rows.length;
  }
  async createTransaction() {
    this.db.exec('BEGIN');
    return { execute: (sql, args) => this.executeSql(sql, args), querySql: (sql, args) => this.querySql(sql, args),
      batchInsert: (table, rows) => this.batchInsert(table, rows), commit: async () => this.db.exec('COMMIT'),
      rollback: async () => this.db.exec('ROLLBACK') };
  }
}
const store = new LookupStore();
let activeStore = store;
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.AbilityKit') return {};
  if (name === '@kit.ArkTS') return { util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } };
  if (name === '@kit.ArkData') return { relationalStore: { SecurityLevel: { S1: 1 }, getRdbStore: async () => activeStore } };
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: filename
}).outputText, filename);
const domain = file => require(path.join(root, 'entry/src/main/ets', file));
const { OfflineDictionaryService } = domain('service/OfflineDictionaryService.ets');
const { DatabaseManager } = domain('repository/DatabaseManager.ets');
const { LearningRepository } = domain('repository/LearningRepository.ets');
const entry = (word, meaning, exchange = '') => ({ word, phonetic: '', meaning, exchange });
const pack = { version: 1, sourceCommit: 'fixture', entries: [
  entry('blue', 'adj. 蓝色的'), entry('child', 'n. 孩子', 's:children'),
  entry('find', 'v. 找到\n发现', 'p:found/d:found/3:finds/i:finding'),
  entry('found', 'v. 建立', 'p:founded/d:founded'), entry('go', 'v. 去', 'p:went/d:gone/3:goes/i:going'),
  entry('may', 'aux. 可以\n可能\nn. 五月'), entry('might', 'aux. 可能\nn. 力量'),
  entry('went', 'go 的过去式', '0:go/1:p')
] };
const context = { resourceManager: { getRawFileContent: async () => new TextEncoder().encode(JSON.stringify(pack)) } };
let checks = 0;
const check = async (label, run) => { await run(); checks++; console.log('PASS ' + label); };
(async () => {
  const lookup = new OfflineDictionaryService();
  await lookup.initialize(context);
  await check('exchange candidates preserve found/find ambiguity and canonical irregular IDs', () => {
    assert.deepEqual(lookup.headwords('found').slice(0, 2), ['found', 'find']);
    assert.deepEqual(lookup.headwords('went'), ['go']);
    assert.ok(lookup.headwords('children').includes('child'));
    assert.ok(lookup.headwords('GOING').includes('go'));
    assert.equal(lookup.headwords('bad\0input').length, 0);
  });
  await check('corrupt or duplicate pack entries are rejected before import', () => {
    assert.throws(() => OfflineDictionaryService.validate({ ...pack, entries: [pack.entries[0], pack.entries[0]] }));
    assert.throws(() => OfflineDictionaryService.validate({ ...pack, entries: [entry('blue', 'x'.repeat(4001))] }));
  });
  const database = new DatabaseManager(); await database.initialize(context);
  const repo = new LearningRepository(database);
  const word = (word, meaning) => ({ word, meaning, phonetic: '', example: '', translation: '' });
  await repo.importCatalog({ version: 1, books: [{ id: 'cet4', name: '四级', category: '考试词书', description: '', words: [word('find', 'v. 找到'), word('found', 'v. 建立')] }] });
  await repo.insertBook({ id: 'custom_test', name: '我的词书', category: 'custom', description: '', words: [word('find', '用户自己的辨析'), word('blue', '我的蓝色备注')] });
  const before = await repo.findWordBySpelling('find');
  await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count) VALUES(?,60,2,123456,123,2)', [before.id]);
  const progress = await repo.getProgress(before.id);
  const books = await repo.getBooks();
  const unlearned = await repo.countUnlearned('cet4');
  await repo.importLookupDictionary(pack);
  await check('query import preserves IDs, progress, book sizes and daily learning eligibility', async () => {
    assert.equal((await repo.findWordBySpelling('find')).id, before.id);
    assert.deepEqual(await repo.getProgress(before.id), progress);
    assert.deepEqual(await repo.getBooks(), books);
    assert.equal(await repo.countUnlearned('cet4'), unlearned);
    assert.equal((await repo.getWord(before.id)).meaning, 'v. 找到\n发现');
    const go = await repo.findWordBySpelling('go'); assert.ok(go.id > 0);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM word_book_item WHERE word_id=?', [go.id]), 0);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM word_progress WHERE word_id=?', [go.id]), 0);
  });
  await check('custom overrides and custom-only global definitions survive the upgrade', async () => {
    assert.equal((await repo.getBookWord('custom_test', before.id)).meaning, '用户自己的辨析');
    assert.equal((await repo.findWordBySpelling('blue')).meaning, '我的蓝色备注');
  });
  await check('re-import is idempotent and lookup words retain fallback backup content', async () => {
    const count = await repo.scalar('SELECT COUNT(*) FROM word');
    await repo.importLookupDictionary(pack);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM word'), count);
    assert.ok((await repo.backupNonBuiltinWords()).some(word => word.word === 'go' && word.meaning === 'v. 去'));
  });
  await check('failure after meaning UPDATE rolls back definitions, IDs and import marker', async () => {
    const snapshot = () => ({
      words: store.db.prepare('SELECT * FROM word ORDER BY id').all(),
      progress: store.db.prepare('SELECT * FROM word_progress ORDER BY word_id').all(),
      books: store.db.prepare('SELECT * FROM word_book_item ORDER BY book_id,word_id').all(),
      meta: store.db.prepare('SELECT * FROM app_meta ORDER BY key').all()
    });
    const before = snapshot();
    const originalExecute = store.executeSql.bind(store);
    store.executeSql = async (sql, args) => {
      if (sql.startsWith('INSERT INTO word(word,phonetic,meaning,example,translation) SELECT')) {
        throw new Error('injected failure after definitions update');
      }
      return originalExecute(sql, args);
    };
    try {
      const changed = { ...pack, sourceCommit: 'rollback_fixture', entries: pack.entries.map(item =>
        item.word === 'find' ? { ...item, meaning: '这条定义不能提交' } : item) };
      await assert.rejects(repo.importLookupDictionary(changed), /injected failure/);
    } finally { store.executeSql = originalExecute; }
    assert.deepEqual(snapshot(), before);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS count FROM sqlite_temp_master WHERE name='lookup_import_stage'").get().count, 0);
  });
  const resourcePath = path.join(root, 'entry/src/main/resources/rawfile/dictionary/lookup-v1.json');
  if (fs.existsSync(resourcePath)) {
    const production = JSON.parse(fs.readFileSync(resourcePath, 'utf8'));
    await check('shipped dictionary is valid, complete for fixed common-word cases and full senses', async () => {
      OfflineDictionaryService.validate(production);
      const dictionary = new OfflineDictionaryService();
      await dictionary.initialize({ resourceManager: { getRawFileContent: async () => new TextEncoder().encode(JSON.stringify(production)) } });
      const words = new Map(production.entries.map(entry => [entry.word, entry]));
      for (const head of ['blue', 'umbrella', 'find', 'be', 'go', 'cat', 'dog']) assert.ok(words.has(head), head);
      assert.ok(dictionary.headwords('found').includes('find'));
      assert.ok(dictionary.headwords('found').includes('found'));
      assert.ok(dictionary.headwords('went').includes('go'));
      assert.ok(dictionary.headwords('children').includes('child'));
      assert.match(words.get('may').meaning, /可以|可能/);
      assert.match(words.get('might').meaning, /可能|也许|或许/);
      const manifest = JSON.parse(fs.readFileSync(path.join(root, 'docs/LOOKUP_DICTIONARY_SOURCE.json'), 'utf8'));
      assert.equal(production.entries.length, manifest.entries);
      assert.equal(manifest.articleCount, 18);
    });
    await check('production-scale first install uses one indexed ID set and preserves book membership', async () => {
      const productionStore = new LookupStore();
      activeStore = productionStore;
      try {
        const productionDatabase = new DatabaseManager(); await productionDatabase.initialize(context);
        const productionRepo = new LearningRepository(productionDatabase);
        const catalog = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/wordbooks/catalog.json'), 'utf8'));
        await productionRepo.importCatalog(catalog);
        const beforeIds = productionStore.db.prepare('SELECT id,word FROM word ORDER BY id').all();
        const bookItems = productionStore.db.prepare('SELECT * FROM word_book_item ORDER BY book_id,word_id').all();
        let plan = [];
        const originalExecute = productionStore.executeSql.bind(productionStore);
        productionStore.executeSql = async (sql, args = []) => {
          if (sql.startsWith('UPDATE word SET meaning=')) {
            plan = productionStore.db.prepare('EXPLAIN QUERY PLAN ' + sql).all(...args);
            assert.ok(plan.some(row => /SEARCH word USING INTEGER PRIMARY KEY \(rowid=\?\)/.test(row.detail)),
              'Drive production UPDATE by its primary-key ID set; two independent IN sets cause O(word count × ID count) probes');
            assert.ok(!plan.some(row => /SCAN s(?:\s|$)/.test(row.detail)), 'Every stage definition probe must use its NOCASE index');
          }
          return originalExecute(sql, args);
        };
        const started = performance.now();
        await productionRepo.importLookupDictionary(production);
        console.log(`INFO production lookup import: ${production.entries.length} entries, ${(performance.now() - started).toFixed(1)} ms`);
        assert.ok(plan.length > 0, 'The production-scale test must execute the UPDATE');
        const afterIds = productionStore.db.prepare('SELECT id,word FROM word ORDER BY id').all();
        assert.deepEqual(afterIds.filter(row => row.id <= beforeIds.at(-1).id), beforeIds);
        assert.deepEqual(productionStore.db.prepare('SELECT * FROM word_book_item ORDER BY book_id,word_id').all(), bookItems);
        assert.equal(await productionRepo.scalar('SELECT COUNT(*) FROM word_progress'), 0);
        assert.equal(bookItems.length, catalog.books.reduce((sum, book) => sum + book.words.length, 0));
      } finally { activeStore = store; productionStore.db.close(); }
    });
  }
  console.log(`${checks} lookup dictionary checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => store.db.close());
