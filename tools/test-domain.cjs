/* Executes the actual ArkTS services against SQLite. Native HarmonyOS/device validation remains separate. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
process.env.TZ = 'Asia/Shanghai';
const root = path.resolve(__dirname, '..');
const testDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'ciying-domain-'));
const stores = new Map();
const settingsFiles = new Map();
class ResultSet {
  constructor(rows) { this.rows = rows; this.index = -1; this.columns = Object.keys(rows[0] || {}); }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { this.index++; return this.index < this.rows.length; }
  getColumnIndex(name) {
    const index = this.columns.indexOf(name);
    if (index < 0) throw new Error(`Column index is out of bounds: ${name}`);
    return index;
  }
  get columnNames() { return this.columns; }
  getLong(index) { return Number(this.rows[this.index][this.columns[index]] || 0); }
  getDouble(index) { return this.getLong(index); }
  getString(index) { return String(this.rows[this.index][this.columns[index]] || ''); }
  close() {}
}
class RdbStore {
  constructor(databasePath = path.join(testDirectory, 'ciying.db')) {
    this.databasePath = databasePath; this.db = new DatabaseSync(databasePath);
  }
  get version() { return this.db.prepare('PRAGMA user_version').get().user_version; }
  set version(value) { this.db.exec(`PRAGMA user_version=${Number(value)}`); }
  async executeSql(sql, args = []) { this.db.prepare(sql).run(...args); }
  async batchInsert(table, values) {
    if (values.length === 0) return 0;
    const columns = Object.keys(values[0]);
    const statement = this.db.prepare(`INSERT INTO ${table}(${columns.join(',')}) VALUES(${columns.map(() => '?').join(',')})`);
    for (const value of values) statement.run(...columns.map(column => value[column]));
    return values.length;
  }
  async createTransaction() {
    const write = this.databasePath === ':memory:' ? this : new RdbStore(this.databasePath);
    write.beginTransaction();
    return { execute: (sql, args) => write.executeSql(sql, args), querySql: (sql, args) => write.querySql(sql, args),
      batchInsert: (table, values) => write.batchInsert(table, values),
      commit: async () => { write.commit(); if (write !== this) write.db.close(); },
      rollback: async () => { write.rollBack(); if (write !== this) write.db.close(); } };
  }
  async querySql(sql, args = []) { return new ResultSet(this.db.prepare(sql).all(...args)); }
  beginTransaction() { this.db.exec('BEGIN'); }
  commit() { this.db.exec('COMMIT'); }
  rollBack() { this.db.exec('ROLLBACK'); }
}
const arkData = {
  relationalStore: { SecurityLevel: { S1: 1 }, async getRdbStore(context, config) {
    if (!stores.has(config.name)) stores.set(config.name, new RdbStore());
    return stores.get(config.name);
  } },
  preferences: { async getPreferences(context, options) {
    if (!settingsFiles.has(options.name)) settingsFiles.set(options.name, new Map());
    const values = settingsFiles.get(options.name);
    return { async get(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
      async put(key, value) { values.set(key, value); }, async flush() {} };
  } }
};
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.ArkData') return arkData;
  if (name === '@kit.AbilityKit') return {};
  if (name === '@kit.ArkTS') return { util: { TextDecoder: {
    create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) })
  } } };
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = function(module, filename) {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const domain = name => require(path.join(root, 'entry/src/main/ets', name));
const models = domain('model/AppModels.ets');
const { LearningService } = domain('service/LearningService.ets');
const { scheduleReview, adjustedNewTarget } = domain('service/ReviewScheduler.ets');
const { DatabaseManager } = domain('repository/DatabaseManager.ets');
const { LearningRepository } = domain('repository/LearningRepository.ets');
let checks = 0;
const check = async (label, action) => { await action(); checks++; console.log(`PASS ${label}`); };
const word = (word, meaning) => ({ word, meaning, phonetic: '', example: 'A short example.', translation: '简短例句。' });
const catalog = { version: 1, books: [
  { id: 'cet4', name: '四级', category: 'exam', description: 'test', words: [
    word('resilient', 'adj. 有韧性的'), word('retain', 'v. 保留') ] },
  { id: 'cet6', name: '六级', category: 'exam', description: 'test', words: [
    word(' Resilient ', 'adj. 有韧性的'), word('maintain', 'v. 保持') ] }
] };
const contextFor = catalog => ({ resourceManager: { async getRawFileContent() {
  return new TextEncoder().encode(JSON.stringify(catalog));
} } });
(async () => {
  let now = new Date(2026, 9, 6, 23, 59, 30).getTime();
  const actualNow = Date.now;
  Date.now = () => now;
  let service = new LearningService();
  await check('result intervals, strength bounds and immutable input', async () => {
    const p = new models.WordProgress();
    assert.equal(scheduleReview(p, models.ReviewResult.FORGET, now).nextReviewAt - now, 600000);
    assert.equal(scheduleReview(p, models.ReviewResult.FUZZY, now).nextReviewAt - now, 360000);
    assert.equal(scheduleReview(p, models.ReviewResult.KNOW, now).nextReviewAt - now, 86400000);
    p.level = 5; p.strength = 80;
    const forgotten = scheduleReview(p, models.ReviewResult.FORGET, now);
    assert.equal(forgotten.level, 4); assert.equal(forgotten.strength, 60);
    assert.equal(forgotten.nextReviewAt - now, 43200000); assert.equal(p.strength, 80);
    p.strength = 98;
    assert.equal(scheduleReview(p, models.ReviewResult.KNOW, now).strength, 100);
    assert.equal(adjustedNewTarget(20, 61), 6); assert.equal(adjustedNewTarget(20, 100), 0);
  });
  await service.initialize(contextFor(catalog));
  let db = new DatabaseManager();
  await db.initialize(contextFor(catalog));
  let repo = new LearningRepository(db);
  let store = db.getStore();
  const words = await service.getWords('', 'all', '');
  const firstId = words.find(word => word.word === 'resilient').id;
  const thirdId = words.find(word => word.word === 'maintain').id;
  await check('transaction reads see pending writes while the store read connection is isolated', async () => {
    const transaction = await store.createTransaction();
    await transaction.execute('INSERT INTO app_meta(key,value) VALUES(?,?)', ['pending_probe', '1']);
    const inside = await transaction.querySql("SELECT COUNT(*) FROM app_meta WHERE key='pending_probe'");
    inside.goToFirstRow(); assert.equal(inside.getLong(0), 1);
    assert.equal(await repo.scalar("SELECT COUNT(*) FROM app_meta WHERE key='pending_probe'"), 0);
    await transaction.rollback();
  });
  await check('shared identity, flags-only progress and literal offline search', async () => {
    assert.equal(words.length, 3);
    assert.deepEqual((await service.getSnapshot()).books.map(book => book.totalCount), [2, 2]);
    await service.setFavorite(firstId, true);
    await service.setNewWord(thirdId, true);
    assert.equal((await service.getSnapshot()).stats.totalLearned, 0);
    assert.equal((await repo.getUnlearned('cet4', 10)).length, 3);
    assert.equal((await repo.getUnlearned('cet4', 10))[0].id, thirdId);
    assert.equal((await service.getWords('', 'all', '韧性'))[0].id, firstId);
    assert.equal((await service.getWords('', 'all', 'res'))[0].id, firstId);
    assert.equal((await service.getWords('', 'all', '%')).length, 0);
  });
  await check('simultaneous taps commit once and interrupted cursor resumes', async () => {
    assert.equal((await service.startSession('onboarding')).items.length, 3);
    const results = await Promise.all([service.record(models.ReviewResult.KNOW, 10000),
      service.record(models.ReviewResult.KNOW, 10000)]);
    assert.equal(results[0].index, 1); assert.equal(results[1].index, 1);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM review_record'), 1);
    stores.get('ciying.db').db.close(); stores.delete('ciying.db');
    service = new LearningService();
    await service.initialize(contextFor(catalog));
    db = new DatabaseManager(); await db.initialize(contextFor(catalog));
    repo = new LearningRepository(db); store = db.getStore();
    assert.equal((await service.startSession('onboarding')).index, 1);
    assert.equal((await service.getProgress(thirdId)).reviewCount, 1);
    assert.equal((await service.getSnapshot()).plan.newDone, 1);
    assert.equal((await service.getSnapshot()).stats.days.find(day => day.date === '2026-10-06').durationMs, 10000);
  });
  await check('midnight resets budget/counters and retains pending session', async () => {
    await service.setBudget('busy');
    assert.equal((await service.getSnapshot()).plan.budget, 'busy');
    now += 60000;
    const snapshot = await service.getSnapshot();
    assert.equal(snapshot.plan.date, '2026-10-07'); assert.equal(snapshot.plan.budget, 'normal');
    assert.equal(snapshot.plan.newDone, 0); assert.equal(service.getSession().index, 1);
    await service.record(models.ReviewResult.FUZZY, 15000);
    assert.equal((await service.getSnapshot()).plan.newDone, 1);
    assert.equal((await repo.getPlan('2026-10-06')).newDone, 1);
  });
  await check('failed cursor save rolls back answer, daily counters and statistics', async () => {
    const before = service.getSession();
    const wordId = before.items[before.index].word.id;
    const count = await repo.scalar('SELECT COUNT(*) FROM review_record');
    const done = (await service.getSnapshot()).plan.newDone;
    await store.executeSql("CREATE TRIGGER reject_session BEFORE INSERT ON study_session BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END");
    await assert.rejects(service.record(models.ReviewResult.FORGET, 7000));
    assert.equal((await service.getProgress(wordId)).reviewCount, 0);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM review_record'), count);
    assert.equal((await service.getSnapshot()).plan.newDone, done);
    assert.equal(service.getSession().index, before.index);
    assert.equal((await repo.loadSession()).index, before.index);
    await store.executeSql('DROP TRIGGER reject_session');
    await service.record(models.ReviewResult.FORGET, 7000);
    assert.equal(service.getSession().index, before.index + 1);
  });
  await check('future words are excluded from due queue and success rate uses reviews', async () => {
    assert.equal((await service.startSession('review')).items.length, 0);
    assert.equal((await service.startSession('quick')).items.length, 0);
    now += 11 * 60000;
    const review = await service.startSession('review');
    assert.equal(review.items.length, 2); assert.equal(review.items[0].word.id, firstId);
    await service.record(models.ReviewResult.KNOW, 5000);
    assert.equal((await service.getSnapshot()).plan.reviewDone, 1);
    assert.equal((await service.getSnapshot()).stats.successRate, 100);
  });
  await check('first mastery counts once and a concurrent favorite survives answer save', async () => {
    let p = await service.getProgress(firstId);
    while (p.strength < 75) {
      const next = scheduleReview(p, models.ReviewResult.KNOW, now);
      await repo.record(p, next, models.ReviewResult.KNOW, 1000, service.getSession(), now); p = next;
    }
    assert.equal((await repo.getStatistics(now)).weekMastered, 1);
    const forgotten = scheduleReview(p, models.ReviewResult.FORGET, now);
    await repo.record(p, forgotten, models.ReviewResult.FORGET, 1000, service.getSession(), now);
    await repo.record(forgotten, scheduleReview(forgotten, models.ReviewResult.KNOW, now),
      models.ReviewResult.KNOW, 1000, service.getSession(), now);
    assert.equal((await repo.getStatistics(now)).weekMastered, 1);
    await repo.setFlag(firstId, true, false);
    const stale = await repo.getProgress(firstId);
    await repo.setFlag(firstId, true, true);
    await repo.record(stale, scheduleReview(stale, models.ReviewResult.KNOW, now),
      models.ReviewResult.KNOW, 1000, service.getSession(), now);
    assert.equal((await repo.getProgress(firstId)).favorite, true);
  });
  await check('book switching retains progress and export contains real events', async () => {
    const settings = service.getSettings(); settings.currentBookId = 'cet6';
    await service.updateSettings(settings);
    assert.equal((await service.getSnapshot()).books.find(book => book.id === 'cet6').learnedCount, 2);
    const backup = JSON.parse(await service.exportData());
    assert.equal(backup.records.length, await repo.scalar('SELECT COUNT(*) FROM review_record'));
    assert.equal(backup.progress.length, 3); assert.equal(backup.days.length, 2);
  });
  await check('an interrupted dictionary upgrade retries without losing progress', async () => {
    const upgrade = JSON.parse(JSON.stringify(catalog)); upgrade.version = 2;
    upgrade.books[0].words.push(word('focus', 'v. 专注'));
    upgrade.books[1].words.push(word('adapt', 'v. 适应'));
    const count = await repo.scalar('SELECT COUNT(*) FROM review_record');
    await store.executeSql("CREATE TRIGGER reject_book BEFORE INSERT ON word_book_item WHEN NEW.book_id='cet6' BEGIN SELECT RAISE(ABORT,'interrupted import'); END");
    await assert.rejects(repo.importCatalog(upgrade));
    assert.equal(await repo.dictionaryVersion(), 1);
    await store.executeSql('DROP TRIGGER reject_book'); await repo.importCatalog(upgrade);
    assert.equal(await repo.dictionaryVersion(), 2);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM review_record'), count);
    assert.equal((await repo.getProgress(firstId)).favorite, true);
    assert.equal((await repo.getBooks())[0].totalCount, 3);
  });
  await check('custom book edits and headword changes preserve dictionary and shared progress', async () => {
    const known = new models.Word(); known.word = 'resilient';
    const missing = new models.Word(); missing.word = 'unlisted_lexiglow_word';
    const resolved = await service.resolveImportWords([known, missing]);
    assert.equal(resolved[0].meaning, 'adj. 有韧性的'); assert.equal(resolved[1].meaning, '');
    await assert.rejects(service.importWords('needs definition', resolved));
    const definition = word('resilient', '自定义词书释义');
    await service.importWords('我的词书', [definition]);
    const custom = (await service.getSnapshot()).books.find(book => book.category === 'custom');
    await service.renameBook(custom.id, '阅读积累');
    assert.equal((await service.getSnapshot()).books.find(book => book.id === custom.id).name, '阅读积累');
    assert.equal((await service.getBookWord(custom.id, firstId)).meaning, '自定义词书释义');
    assert.equal((await service.getWord(firstId)).meaning, 'adj. 有韧性的');
    const originalProgress = await service.getProgress(firstId);
    const edited = word('resilient', '第二份自定义词义');
    edited.phonetic = '/custom/'; edited.example = 'Edited example.';
    const saved = await service.updateBookWord(custom.id, firstId, edited);
    assert.equal(saved.id, firstId); assert.equal(saved.phonetic, '/custom/');
    assert.equal((await service.getWords(custom.id, 'all', '第二份'))[0].meaning, edited.meaning);
    const settings = service.getSettings(); settings.currentBookId = custom.id; await service.updateSettings(settings);
    now += 70 * 86400000;
    await service.clearSession(); const review = await service.startSession('review');
    assert.equal(review.items.find(item => item.word.id === firstId).word.meaning, edited.meaning);
    edited.word = 'new_lexiglow_headword';
    const renamed = await service.updateBookWord(custom.id, firstId, edited);
    assert.notEqual(renamed.id, firstId);
    assert.equal((await service.getProgress(firstId)).reviewCount, originalProgress.reviewCount);
    assert.equal((await service.getProgress(renamed.id)).reviewCount, 0);
    assert.equal((await service.getBookWord('cet4', firstId)).meaning, 'adj. 有韧性的');
    assert.equal((await service.exportBook(custom.id))[0].word, edited.word);
    assert.equal(service.getSession().items.find(item => item.word.id === renamed.id).word.meaning, edited.meaning);
    await assert.rejects(service.renameBook('cet4', '不能改内置'));
    await assert.rejects(service.updateBookWord('cet4', firstId, edited));
    now -= 70 * 86400000;
  });
  await check('a duplicate headword edit rejects without changing either definition or membership', async () => {
    await service.importWords('碰撞保护', [word('retain', '自定义保留释义'), word('maintain', '自定义保持释义')]);
    const custom = (await service.getSnapshot()).books.find(book => book.name === '碰撞保护');
    const before = await service.exportBook(custom.id);
    const retained = before.find(entry => entry.word === 'retain');
    const maintained = before.find(entry => entry.word === 'maintain');
    const progressBefore = await service.getProgress(retained.id);
    const edited = word(' MAINTAIN ', '不应覆盖的释义');
    await assert.rejects(service.updateBookWord(custom.id, retained.id, edited), /已经有这个单词/);
    assert.deepEqual(await service.exportBook(custom.id), before);
    assert.equal(await repo.scalar('SELECT COUNT(*) FROM word_book_item WHERE book_id=?', [custom.id]), 2);
    assert.equal((await service.getBookWord(custom.id, retained.id)).meaning, '自定义保留释义');
    assert.equal((await service.getBookWord(custom.id, maintained.id)).meaning, '自定义保持释义');
    assert.deepEqual(await service.getProgress(retained.id), progressBefore);
  });
  const actualCatalog = JSON.parse(fs.readFileSync(path.join(root,
    'entry/src/main/resources/rawfile/wordbooks/catalog.json'), 'utf8'));
  await check('schema 1 and same-version empty memberships repair without deleting learned progress', async () => {
    const original = stores.get('ciying.db');
    const legacy = new RdbStore(':memory:'); stores.set('ciying.db', legacy); settingsFiles.clear();
    const source = ts.createSourceFile('schema.ts', fs.readFileSync(path.join(root,
      'entry/src/main/ets/repository/DatabaseManager.ets'), 'utf8'), ts.ScriptTarget.Latest);
    const statements = [];
    function visit(node) {
      if (ts.isVariableDeclaration(node) && node.name.getText(source) === 'SCHEMA') {
        for (const element of node.initializer.elements) {
          statements.push(element.text.replace(/, override_(word|phonetic|meaning|example|translation) TEXT/g, ''));
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(source);
    for (const sql of statements) await legacy.executeSql(sql);
    legacy.version = 1;
    await legacy.executeSql("INSERT INTO word(id,word,phonetic,meaning,example,translation) VALUES(1,'resilient','','有韧性的','','')");
    await legacy.executeSql("INSERT INTO word_book(id,name,category,description) VALUES('cet4','旧词书','exam','')");
    await legacy.executeSql('INSERT INTO app_meta(key,value) VALUES(?,?)', ['dictionary_version', `${actualCatalog.version}`]);
    await legacy.executeSql('INSERT INTO word_progress(word_id,review_count,strength,level) VALUES(1,7,84,7)');
    const recovered = new LearningService(); await recovered.initialize(contextFor(actualCatalog));
    const snapshot = await recovered.getSnapshot();
    assert.equal(legacy.version, 2);
    assert.equal(snapshot.books.length, 5);
    assert.equal(snapshot.books[0].totalCount, actualCatalog.books[0].words.length);
    assert.equal(snapshot.stats.totalLearned, 1); assert.equal(snapshot.stats.mastered, 1);
    assert.equal((await recovered.getProgress(1)).reviewCount, 7);
    legacy.db.close(); stores.set('ciying.db', original);
  });
  await check('bundled wordbooks import under the actual schema', async () => {
    const original = stores.get('ciying.db'); stores.set('ciying.db', new RdbStore(':memory:')); settingsFiles.clear();
    const full = new LearningService(); await full.initialize(contextFor(actualCatalog));
    const snapshot = await full.getSnapshot();
    assert.equal(snapshot.books.length, 5);
    assert.equal(snapshot.books[0].totalCount, actualCatalog.books[0].words.length);
    assert.equal(snapshot.stats.totalLearned, 0); assert.equal(snapshot.dailyWord.word.length > 0, true);
    assert.equal((await full.startSession('onboarding')).items.length, 3);
    const fullDb = new DatabaseManager(); await fullDb.initialize(contextFor(actualCatalog));
    const fullRepo = new LearningRepository(fullDb);
    const all = await full.getWords('', 'all', '');
    await check('quick mode uses five due plus three fresh and backlog scales once', async () => {
      for (const entry of all.slice(0, 65)) {
        await fullDb.getStore().executeSql('INSERT INTO word_progress(word_id,review_count,strength,next_review_at) VALUES(?,1,30,?)', [entry.id, now - 1000]);
      }
      let plan = (await full.getSnapshot()).plan;
      assert.equal(plan.newTarget, 6); assert.equal(plan.reviewTarget, 60);
      await fullDb.getStore().executeSql('UPDATE word_progress SET next_review_at=? WHERE word_id=?', [now + 10000000, all[0].id]);
      assert.equal((await full.getSnapshot()).plan.newTarget, 6);
      const quick = await full.startSession('quick');
      assert.equal(quick.items.filter(item => item.type === 'review').length, 5);
      assert.equal(quick.items.filter(item => item.type === 'new').length, 3);
      const settings = full.getSettings(); settings.learningMode = 'exam'; await full.updateSettings(settings);
      assert.equal((await full.getSnapshot()).plan.newTarget, 3);
      await fullDb.getStore().executeSql('UPDATE word_progress SET wrong_count=99 WHERE word_id=?', [all[64].id]);
      assert.equal((await fullRepo.getDue(now, 5, true))[0].id, all[64].id);
      const untouched = await fullRepo.queryWords('SELECT * FROM word WHERE id NOT IN(SELECT word_id FROM word_progress) LIMIT 36');
      for (const entry of untouched) {
        await fullDb.getStore().executeSql('INSERT INTO word_progress(word_id,review_count,next_review_at) VALUES(?,1,?)', [entry.id, now - 1000]);
      }
      assert.equal((await full.getSnapshot()).dueCount, 100);
      assert.equal((await full.getSnapshot()).plan.newTarget, 0);
    });
    stores.get('ciying.db').db.close(); stores.set('ciying.db', original);
  });
  Date.now = actualNow;
  for (const store of stores.values()) store.db.close();
  fs.rmSync(testDirectory, { recursive: true, force: true });
  console.log(`${checks} domain and SQLite behavior checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
