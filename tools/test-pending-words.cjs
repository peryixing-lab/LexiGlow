/* Exercises actual Schema 6/PendingWordService/BackupService against SQLite, without native UI mocks. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const root = path.resolve(__dirname, '..', 'entry/src/main/ets');
let activeStore;
class PendingRows {
  constructor(rows) { this.rows = rows; this.index = -1; this.columns = Object.keys(rows[0] || {}); }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { this.index++; return this.index < this.rows.length; }
  getLong(index) { return Number(this.rows[this.index][this.columns[index]] || 0); }
  getString(index) { return String(this.rows[this.index][this.columns[index]] || ''); }
  close() {}
}
class PendingStore {
  constructor() { this.db = new DatabaseSync(':memory:'); this.failSentenceInsert = false; }
  get version() { return this.db.prepare('PRAGMA user_version').get().user_version; }
  async executeSql(sql, args = []) {
    if (this.failSentenceInsert && /^INSERT INTO sentence_memory/.test(sql)) throw Error('simulated sentence write failure');
    this.db.prepare(sql).run(...args);
  }
  async querySql(sql, args = []) { return new PendingRows(this.db.prepare(sql).all(...args)); }
  async batchInsert(table, rows) {
    for (const row of rows) {
      const columns = Object.keys(row);
      this.db.prepare(`INSERT INTO ${table}(${columns.join(',')}) VALUES(${columns.map(() => '?').join(',')})`).run(...columns.map(key => row[key]));
    }
    return rows.length;
  }
  async createTransaction() {
    this.db.exec('BEGIN');
    return {execute: (sql, args) => this.executeSql(sql, args), querySql: (sql, args) => this.querySql(sql, args),
      batchInsert: (table, rows) => this.batchInsert(table, rows), commit: async () => this.db.exec('COMMIT'), rollback: async () => this.db.exec('ROLLBACK')};
  }
}
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.AbilityKit') return {};
  if (name === '@kit.ArkData') return {relationalStore: {SecurityLevel: {S1: 1}, getRdbStore: async () => activeStore}};
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename});
  module._compile(output.outputText, filename);
};
const {DatabaseManager} = require(path.join(root, 'repository/DatabaseManager.ets'));
const {PendingWordService} = require(path.join(root, 'service/PendingWordService.ets'));
const {ArticleRepository} = require(path.join(root, 'repository/ArticleRepository.ets'));
const {BackupService} = require(path.join(root, 'service/BackupService.ets'));
const {PendingWordDraft} = require(path.join(root, 'model/PendingWordModels.ets'));
const {DataExport, Word, DictionaryBook} = require(path.join(root, 'model/AppModels.ets'));
const now = new Date(2026, 10, 7, 12).getTime();
const draft = (id = 'draft-1', articleId = 1) => Object.assign(new PendingWordDraft(), {
  id, spelling: 'quux', sentence: 'A quux shines.', articleId, articleTitle: 'An article', paragraphKey: '0:0',
  targetText: 'quux', targetStart: 2, createdAt: now
});
const fixture = () => {
  const backup = new DataExport(); backup.exportedAt = now; backup.dictionaryVersion = 2;
  const word = Object.assign(new Word(), {id: 1, word: 'known', meaning: 'adj. 已知的'});
  const book = Object.assign(new DictionaryBook(), {id: 'cet4', name: '四级', category: 'exam', words: [word]});
  backup.words = [word]; backup.books = [book];
  backup.articles = [{id: 1, title: 'An article', body: 'A quux shines.', createdAt: now}];
  return backup;
};
const copy = value => JSON.parse(JSON.stringify(value));
const learningState = store => Object.fromEntries(['word_book_item', 'word_progress', 'daily_plan', 'daily_summary', 'review_record', 'mastered_word', 'study_session']
  .map(table => [table, store.db.prepare(`SELECT * FROM ${table} ORDER BY 1`).all()]));
const withDatabase = async action => {
  const store = new PendingStore(); activeStore = store;
  const database = new DatabaseManager(); await database.initialize({});
  store.db.exec("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('known','','adj. 已知的','',''); INSERT INTO word_book VALUES('cet4','四级','exam',''); INSERT INTO word_book_item(book_id,word_id,order_index) VALUES('cet4',1,0); INSERT INTO word_progress(word_id,strength,review_count) VALUES(1,40,3); INSERT INTO daily_plan(date,new_target,review_target,estimated_minutes,budget) VALUES('2026-11-07',20,5,10,'normal'); INSERT INTO daily_summary(date,new_count,review_count,total_count) VALUES('2026-11-07',1,2,3); INSERT INTO study_session VALUES(1,'saved-session'); INSERT INTO article(id,title,body,created_at) VALUES(1,'An article','A quux shines.',1);");
  const service = PendingWordService.getInstance(); service.initialize(database);
  try { await action(service, store, database); } finally { store.db.close(); }
};
let checks = 0;
const check = async (name, action) => { await action(); checks++; console.log(`PASS ${name}`); };
(async () => {
  await check('Schema 6 initializes pending drafts and save deduplicates case-insensitive same-source text', () => withDatabase(async (service, store) => {
    assert.equal(store.version, 6); await service.save(draft());
    const duplicate = draft('another-id'); duplicate.spelling = 'QUUX'; await service.save(duplicate);
    assert.equal((await service.list()).length, 1); assert.equal((await service.list())[0].spelling, 'quux');
  }));
  await check('500-draft limit rejects an additional item while existing duplicate stays harmless', () => withDatabase(async (service, store) => {
    const insert = store.db.prepare('INSERT INTO pending_word VALUES(?,?,?,?,?,?,?,?,?)');
    for (let i = 0; i < 500; i++) insert.run(`seed-${i}`, 'quux', 'A quux shines.', 1, 'An article', `${i}:0`, 'quux', 2, now);
    await service.save(draft('duplicate'));
    const additional = draft('overflow'); additional.paragraphKey = '501:0';
    await assert.rejects(service.save(additional), /500/); assert.equal((await service.list()).length, 500);
  }));
  await check('completing a draft atomically creates a word and exact-target sentence without changing learning tasks', () => withDatabase(async (service, store) => {
    const before = learningState(store); await service.save(draft()); await service.complete('draft-1', '  n. 测试词  ');
    assert.equal((await service.list()).length, 0);
    const word = store.db.prepare("SELECT * FROM word WHERE word='quux'").get(); assert.equal(word.meaning, 'n. 测试词');
    const sentence = store.db.prepare('SELECT * FROM sentence_memory').get();
    assert.equal(sentence.word_id, word.id); assert.equal(sentence.target_text, 'quux'); assert.equal(sentence.target_start, 2); assert.equal(sentence.recall_enabled, 1);
    assert.deepEqual(learningState(store), before);
    await service.complete('draft-1', 'n. 重复点击'); assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM sentence_memory').get().n, 1);
  }));
  await check('blank or oversized meanings are rejected before any mutation', () => withDatabase(async (service, store) => {
    await service.save(draft()); await assert.rejects(service.complete('draft-1', '  '), /释义/);
    await assert.rejects(service.complete('draft-1', '字'.repeat(4001)), /4000/);
    assert.equal((await service.list()).length, 1); assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM word WHERE word='quux'").get().n, 0);
  }));
  await check('a failed sentence write rolls back the new word and retains the draft and learning state', () => withDatabase(async (service, store) => {
    await service.save(draft()); const before = learningState(store); store.failSentenceInsert = true;
    await assert.rejects(service.complete('draft-1', 'n. 测试词'), /simulated sentence write failure/);
    assert.equal((await service.list()).length, 1); assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM word WHERE word='quux'").get().n, 0);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM sentence_memory').get().n, 0); assert.deepEqual(learningState(store), before);
    store.failSentenceInsert = false; await service.complete('draft-1', 'n. 测试词'); assert.equal((await service.list()).length, 0);
  }));
  await check('deleting the source article retains drafts and completion preserves a detached original sentence', () => withDatabase(async (service, store, database) => {
    await service.save(draft()); await new ArticleRepository(database).remove(1);
    const saved = (await service.list())[0]; assert.equal(saved.articleId, 0); assert.ok(saved.paragraphKey.includes('@deleted:1'));
    await service.complete(saved.id, 'n. 测试词'); const sentence = store.db.prepare('SELECT * FROM sentence_memory').get();
    assert.equal(sentence.article_id, 0); assert.equal(sentence.sentence, 'A quux shines.');
  }));
  await check('v5 export, complete validation and transaction restore preserve every pending field', () => withDatabase(async (service, store, database) => {
    await service.save(draft()); const backup = fixture();
    await database.transaction(async transaction => PendingWordService.exportInside(transaction, backup));
    const normalized = BackupService.parse(JSON.stringify(backup)); assert.equal(normalized.pendingWords.length, 1);
    await service.remove('draft-1'); assert.equal((await service.list()).length, 0);
    await database.transaction(async transaction => PendingWordService.restoreInside(transaction, normalized));
    assert.deepEqual((await service.list()).map(copy), normalized.pendingWords.map(copy));
  }));
  await check('v5 validation rejects invalid targets, orphan sources and duplicate draft identity or content', () => {
    const backup = fixture(); backup.pendingWords = [draft()];
    for (const mutate of [
      bad => {bad.pendingWords[0].targetStart = 3;},
      bad => {bad.pendingWords[0].targetText = '';},
      bad => {bad.pendingWords[0].spelling = 'different';},
      bad => {bad.pendingWords[0].articleId = 999;},
      bad => {bad.pendingWords.push(copy(bad.pendingWords[0]));},
      bad => {const duplicate = copy(bad.pendingWords[0]); duplicate.id = 'different-id'; bad.pendingWords.push(duplicate);}
    ]) { const bad = copy(backup); mutate(bad); assert.throws(() => BackupService.parse(JSON.stringify(bad))); }
  });
  await check('v4 restore preserves local drafts but detaches their old user-article references', () => withDatabase(async (service, store, database) => {
    await service.save(draft()); const backup = fixture(); backup.version = 4;
    await database.transaction(async transaction => PendingWordService.restoreInside(transaction, backup));
    const saved = (await service.list())[0]; assert.equal(saved.articleId, 0); assert.ok(saved.paragraphKey.includes('@restored:1'));
    assert.equal(saved.id, 'draft-1'); assert.equal(saved.targetText, 'quux');
  }));
  await check('v1-v3 restore preserves both drafts and their source references', () => withDatabase(async (service, store, database) => {
    await service.save(draft());
    for (const version of [1, 2, 3]) {
      const backup = fixture(); backup.version = version;
      await database.transaction(async transaction => PendingWordService.restoreInside(transaction, backup));
      assert.equal((await service.list())[0].articleId, 1);
    }
  }));
  await check('invalid target spans cannot enter the draft store through save', () => withDatabase(async service => {
    for (const mutate of [
      row => {row.targetText = '';}, row => {row.spelling = 'different';},
      row => {row.targetStart = 2.5;}, row => {row.sentence = 'A quuxes shines.';}
    ]) { const invalid = draft(); mutate(invalid); await assert.rejects(service.save(invalid)); }
    assert.equal((await service.list()).length, 0);
  }));
  await check('saving after an article deletion detaches the draft before it can produce an invalid backup', () => withDatabase(async (service, store, database) => {
    await new ArticleRepository(database).remove(1); await service.save(draft());
    assert.equal((await service.list())[0].articleId, 0);
  }));
  console.log(`${checks} pending-word checks passed.`);
})().catch(error => {console.error(error); process.exitCode = 1;});
