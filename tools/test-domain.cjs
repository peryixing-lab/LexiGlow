/* Executes the actual ArkTS services against SQLite. Native HarmonyOS/device validation remains separate. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const Module = require('node:module');
const { DatabaseSync, backup: sqliteBackup } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
process.env.TZ = 'Asia/Shanghai';
const root = path.resolve(__dirname, '..');
const testDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'ciying-domain-'));
const stores = new Map();
const settingsFiles = new Map();
let storeNumber = 0;
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
    this.number = ++storeNumber; this.backups = new Map(); this.restores = 0;
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
  async backup(name) {
    const destination = path.join(testDirectory, `safety-${this.number}-${path.basename(name)}`);
    if (fs.existsSync(destination)) { fs.unlinkSync(destination); }
    await sqliteBackup(this.db, destination);
    this.backups.set(name, destination);
  }
  async restore(name) {
    const snapshot = this.backups.get(name);
    assert.ok(snapshot && fs.existsSync(snapshot), 'restore requires a completed safety backup');
    const restored = path.join(testDirectory, `restored-${this.number}-${++this.restores}.db`);
    fs.copyFileSync(snapshot, restored);
    this.db.close(); this.databasePath = restored; this.db = new DatabaseSync(restored);
    this.db.exec('PRAGMA foreign_keys=ON');
  }
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
const { BackupService } = domain('service/BackupService.ets');
const { scheduleReview } = domain('service/ReviewScheduler.ets');
const { strengthAfterResult, strengthName } = domain('utils/MemoryUtils.ets');
const { dailyPlanProgress, isDailyPlanComplete } = domain('utils/DailyPlanUtils.ets');
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
const contextFor = catalog => ({ resourceManager: { async getRawFileContent(name) {
  const entries = [...new Map(catalog.books.flatMap(book => book.words)
    .filter(item => /^[a-z]+(?:[-' ][a-z]+)*$/.test(item.word.trim().toLowerCase()))
    .map(item => [item.word.trim().toLowerCase(), { word: item.word.trim().toLowerCase(), phonetic: item.phonetic,
      meaning: item.meaning, exchange: '' }])).values()];
  const payload = name === 'dictionary/lookup-v1.json' ? { version: 1, sourceCommit: 'test', entries } : catalog;
  return new TextEncoder().encode(JSON.stringify(payload));
} } });
const withIsolatedRepository = async action => {
  const previousStore = stores.get('ciying.db');
  const previousSettings = new Map(settingsFiles);
  const isolatedStore = new RdbStore(':memory:');
  stores.set('ciying.db', isolatedStore); settingsFiles.clear();
  try {
    const database = new DatabaseManager();
    await database.initialize(contextFor(catalog));
    const repository = new LearningRepository(database);
    await repository.importCatalog(catalog);
    await action(repository, isolatedStore, database);
  } finally {
    isolatedStore.db.close();
    if (previousStore) stores.set('ciying.db', previousStore); else stores.delete('ciying.db');
    settingsFiles.clear();
    for (const [name, values] of previousSettings) settingsFiles.set(name, values);
  }
};
const persistedLearningState = store => ({
  progress: store.db.prepare('SELECT * FROM word_progress ORDER BY word_id').all(),
  records: store.db.prepare('SELECT * FROM review_record ORDER BY id').all(),
  plans: store.db.prepare('SELECT * FROM daily_plan ORDER BY date').all(),
  days: store.db.prepare('SELECT * FROM daily_summary ORDER BY date').all(),
  mastered: store.db.prepare('SELECT * FROM mastered_word ORDER BY word_id').all(),
  session: store.db.prepare('SELECT * FROM study_session ORDER BY id').all(),
  meta: store.db.prepare('SELECT * FROM app_meta ORDER BY key').all()
});
const seedLearnedWord = async (store, wordId, firstLearnedAt, strength = 50) => {
  await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count) VALUES(?,?,?,?,?,1)',
    [wordId, strength, 1, (firstLearnedAt || 0) + 86400000, firstLearnedAt || 0]);
  if (firstLearnedAt !== undefined) {
    await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
      [wordId, models.ReviewResult.KNOW, firstLearnedAt, 1000, 0, 1, 0, strength, 'new']);
  }
};
const seedLegacyLearningState = async (repo, store, now) => {
  const entries = await repo.getWords('', 'all', '');
  const recalled = entries[0].id;
  const retained = entries[1].id;
  const fuzzy = entries[2].id;
  await store.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('partial_history','','部分历史','','')");
  const partial = await repo.scalar("SELECT id FROM word WHERE word='partial_history'");
  await store.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('broken_history','','断开的历史','','')");
  const broken = await repo.scalar("SELECT id FROM word WHERE word='broken_history'");
  for (const values of [[recalled, 48, 4, now + 3000000, now - 1000, 4, 1, 1, 1],
    [retained, 96, 8, now + 6000000, now - 2000, 8, 3, 1, 0],
    [fuzzy, 25, 2, now + 60000, now - 3000, 2, 1, 0, 1],
    [partial, 36, 3, now + 2000000, now - 1000, 3, 0, 1, 1],
    [broken, 24, 2, now + 1000000, now - 1000, 2, 0, 0, 0]]) {
    await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count,wrong_count,favorite,is_new_word) VALUES(?,?,?,?,?,?,?,?,?)', values);
  }
  for (let index = 0; index < 4; index++) {
    await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
      [recalled, models.ReviewResult.KNOW, now - (4 - index) * 1000, (index + 1) * 100, index, index + 1,
        index * 12, (index + 1) * 12, index === 0 ? 'new' : 'review']);
  }
  // A retained history starts from its stored baseline. Equal event times still replay by record ID.
  await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
    [fuzzy, models.ReviewResult.FUZZY, now - 3000, 700, 3, 3, 40, 45, 'review']);
  await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
    [fuzzy, models.ReviewResult.FORGET, now - 3000, 800, 3, 2, 45, 25, 'review']);
  await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
    [partial, models.ReviewResult.KNOW, now - 1000, 900, 2, 3, 24, 36, 'review']);
  for (const values of [[broken, models.ReviewResult.KNOW, now - 2000, 400, 0, 1, 0, 12, 'new'],
    [broken, models.ReviewResult.KNOW, now - 1000, 500, 1, 2, 10, 24, 'review']]) {
    await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)', values);
  }
  await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)', [retained, now - 86400000]);
  await store.executeSql('INSERT INTO daily_plan(date,new_target,review_target,new_done,review_done,estimated_minutes,budget) VALUES(?,?,?,?,?,?,?)',
    ['2026-10-07', 20, 6, 2, 6, 8, 'normal']);
  await store.executeSql('INSERT INTO daily_summary(date,new_count,review_count,known_count,total_count,duration_ms) VALUES(?,?,?,?,?,?)',
    ['2026-10-07', 2, 6, 4, 8, 2500]);
  const session = new models.StudySession();
  session.items = [{ word: entries[0], type: 'review' }, { word: entries[2], type: 'new' }];
  session.mode = 'quick'; session.startedAt = now - 10000; session.index = 1; session.completed = 1;
  await repo.saveSession(session);
  return { recalled, retained, fuzzy, partial, broken };
};
const seedVersionOneLearningState = async (repo, store, now) => {
  const ids = await seedLegacyLearningState(repo, store, now);
  const recalledRecords = store.db.prepare('SELECT id FROM review_record WHERE word_id=? ORDER BY id').all(ids.recalled);
  for (let index = 0; index < recalledRecords.length; index++) {
    await store.executeSql('UPDATE review_record SET previous_strength=?,next_strength=? WHERE id=?',
      [index === 0 ? 0 : 50 + (index - 1) * 12, 50 + index * 12, recalledRecords[index].id]);
  }
  await store.executeSql('UPDATE word_progress SET strength=86 WHERE word_id=?', [ids.recalled]);
  await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)', [ids.recalled, now - 1000]);
  await store.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('mastery_v1_history','','历史掌握词','','')");
  const mastery = await repo.scalar("SELECT id FROM word WHERE word='mastery_v1_history'");
  await store.executeSql('INSERT INTO word_progress(word_id,strength,level,next_review_at,last_review_at,review_count,wrong_count,favorite,is_new_word) VALUES(?,?,?,?,?,?,?,?,?)',
    [mastery, 100, 8, now + 9000000, now - 1000, 8, 0, 1, 0]);
  const strengths = [0, 50, 62, 74, 86, 98, 100, 100, 100];
  for (let index = 0; index < 8; index++) {
    await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
      [mastery, models.ReviewResult.KNOW, now - (8 - index) * 1000, 200 + index, index, index + 1,
        strengths[index], strengths[index + 1], index === 0 ? 'new' : 'review']);
  }
  await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)', [mastery, now - 5000]);
  await store.executeSql('UPDATE daily_summary SET total_count=new_count');
  await store.executeSql('INSERT INTO app_meta(key,value) VALUES(?,?)', ['learning_semantics_version', '1']);
  return { ...ids, mastery };
};
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
  });
  await check('response-time thresholds, stable intervals and failure counters remain deterministic', async () => {
    const p = new models.WordProgress(); p.wordId = 5; p.strength = 50; p.level = 4;
    p.lastReviewAt = now - 14 * 86400000; p.consecutiveKnown = 2;
    const before = JSON.stringify(p);
    const hesitant = scheduleReview(p, models.ReviewResult.KNOW, now, 4001);
    assert.equal(hesitant.strength, 58); assert.equal(hesitant.hesitationCount, 1);
    assert.equal(hesitant.consecutiveKnown, 3); assert.equal(hesitant.lastResponseMs, 4001);
    assert.equal(hesitant.nextReviewAt - now, 43200 * 0.8 * 60000);
    const stable = scheduleReview(p, models.ReviewResult.KNOW, now, 3500);
    assert.equal(stable.strength, 62); assert.equal(stable.hesitationCount, 0);
    assert.equal(stable.nextReviewAt - now, 43200 * 1.2 * 60000);
    p.lastReviewAt += 1;
    assert.equal(scheduleReview(p, models.ReviewResult.KNOW, now, 4000).nextReviewAt - now, 43200 * 60000);
    p.lastReviewAt -= 1;
    assert.equal(JSON.stringify(p), before);
    const fuzzy = scheduleReview(p, models.ReviewResult.FUZZY, now, 3501);
    assert.equal(fuzzy.consecutiveFailures, 1); assert.equal(fuzzy.consecutiveKnown, 0);
    const failed = scheduleReview(fuzzy, models.ReviewResult.FORGET, now + 1, 1000);
    assert.equal(failed.consecutiveFailures, 2); assert.equal(failed.hesitationCount, 2);
    const recovered = scheduleReview(failed, models.ReviewResult.KNOW, now + 2, NaN);
    assert.equal(recovered.consecutiveFailures, 0); assert.equal(recovered.lastResponseMs, 0);
    assert.equal(recovered.wrongCount, 1);
  });
  await check('exam advice validates calendar dates and does not mutate daily targets', async () => {
    const { examPlanAdvice, dailyReviewQuota } = domain('service/ReviewScheduler.ets');
    const instant = new Date(2026, 9, 10, 21).getTime();
    assert.equal(examPlanAdvice('2026-02-30', 1000, 20, instant).daysRemaining, -1);
    assert.equal(examPlanAdvice('', 1000, 20, instant).message, '');
    assert.equal(examPlanAdvice('2026-12-10', 600, 20, instant).mode, 'stable');
    assert.equal(examPlanAdvice('2026-11-10', 600, 20, instant).mode, 'accelerated');
    assert.equal(examPlanAdvice('2026-10-20', 600, 20, instant).mode, 'sprint');
    assert.equal(examPlanAdvice('2026-10-10', 600, 20, instant).suggestedNewTarget, 100);
    assert.equal(dailyReviewQuota(101, 'normal'), 21);
    assert.equal(dailyReviewQuota(1000, 'normal'), 60);
    assert.equal(dailyReviewQuota(101, 'busy'), 15);
    assert.equal(dailyReviewQuota(1000, 'free'), 100);
  });
  await check('schema 2 upgrades atomically to 5 and a failed DDL transaction retries without losing history', async () => {
    const previousStore = stores.get('ciying.db');
    const legacy = new RdbStore(':memory:'); stores.set('ciying.db', legacy);
    try {
      const source = ts.createSourceFile('schema.ts', fs.readFileSync(path.join(root,
        'entry/src/main/ets/repository/DatabaseManager.ets'), 'utf8'), ts.ScriptTarget.Latest);
      const statements = [];
      function visit(node) {
        if (ts.isVariableDeclaration(node) && node.name.getText(source) === 'SCHEMA') {
          for (const element of node.initializer.elements) statements.push(element.text);
        }
        ts.forEachChild(node, visit);
      }
      visit(source);
      for (const sql of statements) await legacy.executeSql(sql);
      legacy.version = 2;
      await legacy.executeSql("INSERT INTO word(id,word,phonetic,meaning,example,translation) VALUES(1,'adapt','','适应','','')");
      await legacy.executeSql('INSERT INTO word_progress(word_id,review_count,strength,level,next_review_at) VALUES(1,7,84,7,123456)');
      const originalTransaction = legacy.createTransaction.bind(legacy);
      legacy.createTransaction = async () => {
        const transaction = await originalTransaction();
        const originalExecute = transaction.execute;
        transaction.execute = (sql, args) => {
          if (sql.includes('CREATE TABLE IF NOT EXISTS practice_result')) throw new Error('DDL interrupted');
          return originalExecute(sql, args);
        };
        return transaction;
      };
      const manager = new DatabaseManager();
      await assert.rejects(manager.initialize(contextFor(catalog)), /DDL interrupted/);
      assert.equal(legacy.version, 2);
      assert.equal(legacy.db.prepare('PRAGMA table_info(word_progress)').all().some(row => row.name === 'hesitation_count'), false);
      assert.equal(legacy.db.prepare('SELECT strength FROM word_progress').get().strength, 84);
      legacy.createTransaction = originalTransaction;
      await manager.initialize(contextFor(catalog));
      assert.equal(legacy.version, 6);
      const progress = await new LearningRepository(manager).getProgress(1);
      assert.equal(progress.reviewCount, 7); assert.equal(progress.strength, 84);
      assert.equal(progress.nextReviewAt, 123456); assert.equal(progress.consecutiveKnown, 0);
    } finally {
      legacy.db.close();
      if (previousStore) stores.set('ciying.db', previousStore); else stores.delete('ciying.db');
    }
  });
  await check('adaptive metric backfill is idempotent and preserves response-aware strengths and raw history', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const entries = await repo.getWords('', 'all', '');
      const id = entries[0].id;
      await store.executeSql('INSERT INTO word_progress(word_id,review_count,strength,level,next_review_at) VALUES(?,3,18,1,123456)', [id]);
      for (const [result, ms, before, after] of [[1, 1000, 0, 5], [1, 3501, 5, 10], [2, 4001, 10, 18]]) {
        await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,0,1,?,?,?)', [id, result, now, ms, before, after, 'review']);
      }
      const raw = store.db.prepare('SELECT * FROM review_record ORDER BY id').all();
      await repo.migrateLearningSemantics();
      assert.equal((await repo.getProgress(id)).strength, 18);
      await repo.migrateAdaptiveMetrics();
      const progress = await repo.getProgress(id);
      assert.equal(progress.hesitationCount, 2); assert.equal(progress.consecutiveFailures, 0);
      assert.equal(progress.consecutiveKnown, 1); assert.equal(progress.lastResponseMs, 4001);
      assert.equal(progress.nextReviewAt, 123456);
      await repo.migrateAdaptiveMetrics();
      assert.deepEqual(await repo.getProgress(id), progress);
      assert.deepEqual(store.db.prepare('SELECT * FROM review_record ORDER BY id').all(), raw);
    });
  });
  await check('legacy preferences retain saved choices with defaults for new optional settings', async () => {
    const { UserSettingsStore } = domain('store/UserSettingsStore.ets');
    const saved = new models.UserSettings(); saved.dailyNewTarget = 7; saved.themeMode = 'dark';
    delete saved.spellingRecall; delete saved.hapticsEnabled;
    const previous = new Map(settingsFiles);
    settingsFiles.set('ciying_settings', new Map([['settings', JSON.stringify(saved)]]));
    try {
      const settings = new UserSettingsStore(); await settings.initialize(contextFor(catalog));
      assert.equal(settings.getSettings().dailyNewTarget, 7);
      assert.equal(settings.getSettings().themeMode, 'dark');
      assert.equal(settings.getSettings().spellingRecall, false);
      assert.equal(settings.getSettings().hapticsEnabled, true);
      const next = settings.getSettings(); next.spellingRecall = true; next.hapticsEnabled = false;
      await settings.save(next);
      const reopened = new UserSettingsStore(); await reopened.initialize(contextFor(catalog));
      assert.equal(reopened.getSettings().spellingRecall, true);
      assert.equal(reopened.getSettings().hapticsEnabled, false);
    } finally {
      settingsFiles.clear(); for (const [key, value] of previous) settingsFiles.set(key, value);
    }
  });
  await check('curated enrichment is symmetric, family links use real identities and repeat startup skips seed rewrites', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const book = { id: 'lexical', name: 'lexical', category: 'custom', description: '', words:
        ['adapt', 'adopt', 'adept', 'distract', 'attract', 'extract'].map(headword => word(headword, headword)) };
      await repo.insertBook(book); await repo.importEnrichmentSeeds();
      const adapt = await repo.findWordBySpelling(' ADAPT ');
      const adopt = await repo.findWordBySpelling('adopt');
      assert.equal((await repo.findWordBySpelling('ada')), undefined);
      const notes = await repo.getWordEnrichment(adapt.id);
      assert.equal(notes.examFrequency, ''); assert.equal(notes.collocations.length, 2);
      assert.equal(notes.confusingWords.length, 2);
      assert.equal((await repo.getWordEnrichment(adopt.id)).confusingWords.some(pair => pair.word.id === adapt.id), true);
      const distract = await repo.findWordBySpelling('distract');
      const family = await repo.getWordEnrichment(distract.id);
      assert.equal(family.root, 'tract');
      assert.deepEqual(family.familyWords.map(item => item.word.word), ['attract', 'extract']);
      assert.equal(family.familyWords.every(item => item.learned === false), true);
      await store.executeSql("CREATE TRIGGER reject_seed_update BEFORE INSERT ON word_enrichment BEGIN SELECT RAISE(ABORT,'seed rewrite'); END");
      await repo.importEnrichmentSeeds();
      assert.equal((await repo.getWordEnrichment(adapt.id)).coreMeanings.length, 1);
    });
  });
  await check('night, audio, spelling and constellation queries exclude unlearned flags-only words and leave progress untouched', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const entries = await repo.getWords('', 'all', '');
      await seedLearnedWord(store, entries[0].id, now - 1000, 80);
      await seedLearnedWord(store, entries[1].id, now - 86400000, 20);
      await repo.setFlag(entries[2].id, false, true);
      await store.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,1,?,1000,1,1,80,85,?)', [entries[0].id, now, 'review']);
      const before = persistedLearningState(store);
      assert.deepEqual((await repo.getNightWords(now, 100)).map(item => item.id), [entries[0].id]);
      assert.deepEqual((await repo.getAudioWords(now)).map(item => item.id), [entries[1].id, entries[0].id]);
      assert.equal((await repo.getSpellingWords(1))[0].id, entries[0].id);
      assert.equal((await repo.getConstellationWords(999)).length, 2);
      assert.deepEqual(persistedLearningState(store), before);
      const score = await repo.savePracticeResult('spelling', 3, 5, 90000, now);
      assert.equal(score.correct, 3); assert.equal(score.completedAt, now); assert.ok(score.id > 0);
      assert.equal((await repo.getPracticeResults())[0].total, 5);
      await assert.rejects(repo.savePracticeResult('spelling', 6, 5, 100, now));
      assert.deepEqual(persistedLearningState(store), before);
    });
  });
  await check('glow restoration shares the answer transaction while the calendar and streak retain real activity', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const entries = await repo.getWords('', 'all', '');
      await seedLearnedWord(store, entries[0].id, now - 2 * 86400000, 30);
      const plan = new models.DailyPlan(); plan.date = '2026-10-06'; plan.reviewTarget = 1;
      await repo.savePlan(plan);
      const previous = await repo.getProgress(entries[0].id);
      const next = scheduleReview(previous, models.ReviewResult.KNOW, now, 5000);
      await store.executeSql("CREATE TRIGGER reject_glow_cursor BEFORE INSERT ON study_session BEGIN SELECT RAISE(ABORT,'cursor failure'); END");
      await assert.rejects(repo.record(previous, next, models.ReviewResult.KNOW, 5000, new models.StudySession(), now), /cursor failure/);
      assert.equal((await repo.getGlowRecords()).length, 0);
      assert.equal((await repo.getProgress(entries[0].id)).strength, 30);
      await store.executeSql('DROP TRIGGER reject_glow_cursor');
      await repo.record(previous, next, models.ReviewResult.KNOW, 5000, new models.StudySession(), now);
      const glow = await repo.getGlowRecords();
      assert.equal(glow.length, 1); assert.equal(glow[0].date, '2026-10-05');
      assert.equal(glow[0].reason, 'review_complete');
      const stats = await repo.getStatistics(now);
      assert.equal(stats.streak, 1);
      const yesterday = stats.days.find(day => day.date === '2026-10-05');
      assert.equal(yesterday.glowing, true); assert.equal(yesterday.totalCount, 0);
      assert.equal((await repo.getProgress(entries[0].id)).lastResponseMs, 5000);
    });
  });
  await check('document ratings use bounded +5 and +12 increments and strength labels change only at their thresholds', async () => {
    const progress = new models.WordProgress();
    const results = [[models.ReviewResult.FORGET, 0, '陌生'], [models.ReviewResult.FUZZY, 5, '陌生'],
      [models.ReviewResult.KNOW, 12, '陌生']];
    for (const [result, strength, label] of results) {
      const next = scheduleReview(progress, result, now);
      assert.equal(next.strength, strength); assert.equal(strengthName(next.strength), label);
      assert.equal(strengthAfterResult(0, result), strength);
      assert.equal(progress.strength, 0); assert.equal(progress.reviewCount, 0);
    }
    let next = progress;
    for (const [strength, label] of [[12, '陌生'], [24, '陌生'], [36, '模糊'], [48, '模糊'],
      [60, '熟悉'], [72, '熟悉'], [84, '掌握'], [96, '掌握'], [100, '掌握']]) {
      next = scheduleReview(next, models.ReviewResult.KNOW, now);
      assert.equal(next.strength, strength);
      assert.equal(strengthName(next.strength), label);
    }
    for (const [strength, label] of [[0, '陌生'], [24, '陌生'], [25, '模糊'], [49, '模糊'],
      [50, '熟悉'], [74, '熟悉'], [75, '掌握'], [100, '掌握']]) {
      assert.equal(strengthName(strength), label);
    }
    assert.equal(strengthAfterResult(24, models.ReviewResult.FUZZY), 29);
    assert.equal(strengthAfterResult(24, models.ReviewResult.KNOW), 36);
    assert.equal(strengthAfterResult(3, models.ReviewResult.FORGET), 0);
    assert.equal(strengthAfterResult(98, models.ReviewResult.FUZZY), 100);
    const forgotten = scheduleReview(next, models.ReviewResult.FORGET, now);
    assert.equal(forgotten.strength, 80); assert.equal(forgotten.level, next.level - 1);
    assert.equal(forgotten.reviewCount, next.reviewCount + 1);
    assert.equal(forgotten.wrongCount, next.wrongCount + 1);
    assert.equal(forgotten.lastReviewAt, now);
    assert.equal(forgotten.nextReviewAt - now, 12 * 60 * 60000);
  });
  await check('document intervals follow the fixed level table for fuzzy, known and forgotten results', async () => {
    const minutes = [10, 1440, 4320, 10080, 20160, 43200, 86400, 86400];
    for (let level = 0; level < 7; level++) {
      const progress = new models.WordProgress(); progress.level = level; progress.strength = 40;
      const fuzzy = scheduleReview(progress, models.ReviewResult.FUZZY, now);
      assert.equal(fuzzy.level, level); assert.equal(fuzzy.strength, 45);
      assert.equal(fuzzy.nextReviewAt, now + Math.round(minutes[level] * 0.6) * 60000);
      const known = scheduleReview(progress, models.ReviewResult.KNOW, now);
      assert.equal(known.level, level + 1); assert.equal(known.strength, 52);
      assert.equal(known.nextReviewAt, now + minutes[level + 1] * 60000);
      const forgotten = scheduleReview(progress, models.ReviewResult.FORGET, now);
      assert.equal(forgotten.level, Math.max(0, level - 1)); assert.equal(forgotten.strength, 20);
      assert.equal(forgotten.nextReviewAt, now + (level <= 1 ? 10 : 720) * 60000);
      assert.equal(progress.level, level); assert.equal(progress.strength, 40);
    }
  });
  await check('daily plan progress includes new and review counts while completion still requires both separate goals', async () => {
    const plan = new models.DailyPlan();
    plan.newTarget = 20; plan.newDone = 10; plan.reviewTarget = 2; plan.reviewDone = 1;
    assert.equal(dailyPlanProgress(plan), 50); assert.equal(isDailyPlanComplete(plan), false);
    plan.newDone = 20; plan.reviewDone = 0;
    assert.equal(dailyPlanProgress(plan), 20 / 22 * 100); assert.equal(isDailyPlanComplete(plan), false);
    plan.reviewDone = 1; assert.equal(dailyPlanProgress(plan), 21 / 22 * 100); assert.equal(isDailyPlanComplete(plan), false);
    plan.reviewDone = 2; assert.equal(dailyPlanProgress(plan), 100); assert.equal(isDailyPlanComplete(plan), true);
    plan.newDone = 25; plan.reviewDone = 0;
    assert.equal(dailyPlanProgress(plan), 100); assert.equal(isDailyPlanComplete(plan), false);
    plan.newDone = 0; plan.reviewDone = 25;
    assert.equal(dailyPlanProgress(plan), 100); assert.equal(isDailyPlanComplete(plan), false);
    plan.newDone = -1; plan.reviewDone = 0; assert.equal(dailyPlanProgress(plan), 0);
    plan.newTarget = 0; plan.newDone = 0; plan.reviewDone = 0;
    assert.equal(dailyPlanProgress(plan), 0); assert.equal(isDailyPlanComplete(plan), false);
    plan.reviewDone = 1; assert.equal(dailyPlanProgress(plan), 50); assert.equal(isDailyPlanComplete(plan), false);
    plan.reviewDone = 2; assert.equal(dailyPlanProgress(plan), 100); assert.equal(isDailyPlanComplete(plan), true);
    plan.reviewTarget = 0; plan.reviewDone = 0;
    assert.equal(dailyPlanProgress(plan), 100); assert.equal(isDailyPlanComplete(plan), true);
  });
  await check('new words and repeated reviews keep independent daily counts and review-only days retain streak', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const savedNow = now;
      try {
        now = new Date(2026, 9, 7, 12).getTime();
        const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
        extended.books[0].words.push(...Array.from({ length: 18 }, (_, index) => word(`counter_fixture_${index}`, '统计测试词')));
        await isolatedRepo.importCatalog(extended);
        const isolatedService = new LearningService();
        await isolatedService.initialize(contextFor(catalog));
        await isolatedService.getSnapshot();
        const entries = await isolatedRepo.getWords('', 'all', '');
        const session = new models.StudySession();
        const answer = async (wordId, result) => {
          const previous = await isolatedRepo.getProgress(wordId);
          await isolatedRepo.record(previous, scheduleReview(previous, result, now), result, 1000, session, now);
        };
        for (const entry of entries.slice(0, 20)) await answer(entry.id, models.ReviewResult.KNOW);
        await answer(entries[0].id, models.ReviewResult.KNOW);
        await answer(entries[0].id, models.ReviewResult.FUZZY);
        const snapshot = await isolatedService.getSnapshot();
        assert.equal(snapshot.stats.totalLearned, 20); assert.equal(snapshot.stats.mastered, 0);
        assert.equal(snapshot.plan.newDone, 20); assert.equal(snapshot.plan.reviewDone, 2);
        assert.equal(dailyPlanProgress(snapshot.plan), 100);
        assert.deepEqual(snapshot.stats.strengthCounts, [19, 1, 0, 0]);
        const today = snapshot.stats.days.find(day => day.date === '2026-10-07');
        assert.deepEqual([today.newCount, today.reviewCount, today.totalCount, today.knownCount, today.durationMs],
          [20, 2, 22, 1, 22000]);
        assert.equal(snapshot.stats.successRate, 50);
        assert.deepEqual(isolatedStore.db.prepare('SELECT item_type,COUNT(*) AS count FROM review_record GROUP BY item_type ORDER BY item_type').all()
          .map(row => [row.item_type, row.count]), [['new', 20], ['review', 2]]);
        now += 86400000;
        await isolatedService.getSnapshot();
        await answer(entries[0].id, models.ReviewResult.KNOW);
        const reviewOnly = await isolatedService.getSnapshot();
        assert.equal(reviewOnly.stats.totalLearned, 20); assert.equal(reviewOnly.plan.newDone, 0);
        assert.equal(reviewOnly.plan.reviewDone, 1); assert.equal(reviewOnly.stats.streak, 2);
        const nextDay = reviewOnly.stats.days.find(day => day.date === '2026-10-08');
        assert.deepEqual([nextDay.newCount, nextDay.reviewCount, nextDay.totalCount, nextDay.knownCount, nextDay.durationMs],
          [0, 1, 1, 1, 1000]);
        assert.equal((await isolatedRepo.getPlan('2026-10-07')).newDone, 20);
        assert.equal((await isolatedRepo.getPlan('2026-10-07')).reviewDone, 2);
      } finally { now = savedNow; }
    });
  });
  await check('version 2 migration restores document ratings, totals and first mastery while preserving learning schedules and saved state', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const ids = await seedVersionOneLearningState(isolatedRepo, isolatedStore, now);
      const before = persistedLearningState(isolatedStore);
      await isolatedRepo.migrateLearningSemantics();
      const after = persistedLearningState(isolatedStore);
      assert.equal((await isolatedRepo.getProgress(ids.recalled)).strength, 48);
      assert.equal((await isolatedRepo.getProgress(ids.mastery)).strength, 96);
      assert.equal((await isolatedRepo.getProgress(ids.fuzzy)).strength, 25);
      assert.deepEqual(await isolatedRepo.getProgress(ids.retained), Object.assign(new models.WordProgress(), {
        wordId: ids.retained, strength: 96, level: 8, nextReviewAt: now + 6000000,
        lastReviewAt: now - 2000, reviewCount: 8, wrongCount: 3, favorite: true, isNewWord: false
      }));
      const withoutStrength = rows => rows.map(({ strength, ...rest }) => rest);
      const withoutRating = rows => rows.map(({ previous_strength, next_strength, ...rest }) => rest);
      assert.deepEqual(withoutStrength(after.progress), withoutStrength(before.progress));
      assert.deepEqual(withoutRating(after.records), withoutRating(before.records));
      for (const id of [ids.retained, ids.fuzzy, ids.partial, ids.broken]) {
        assert.deepEqual(after.progress.find(row => row.word_id === id), before.progress.find(row => row.word_id === id));
        assert.deepEqual(after.records.filter(row => row.word_id === id), before.records.filter(row => row.word_id === id));
      }
      assert.deepEqual(after.records.slice(0, 4).map(row => [row.previous_strength, row.next_strength]),
        [[0, 12], [12, 24], [24, 36], [36, 48]]);
      assert.deepEqual(after.records.filter(row => row.word_id === ids.mastery)
        .map(row => [row.previous_strength, row.next_strength]),
        [[0, 12], [12, 24], [24, 36], [36, 48], [48, 60], [60, 72], [72, 84], [84, 96]]);
      assert.deepEqual(after.plans, before.plans); assert.deepEqual(after.session, before.session);
      assert.deepEqual(after.days.map(row => [row.new_count, row.review_count, row.known_count, row.total_count, row.duration_ms]),
        [[2, 6, 4, 8, 2500]]);
      assert.equal(after.mastered.some(row => row.word_id === ids.recalled), false);
      assert.equal(after.mastered.find(row => row.word_id === ids.mastery).first_mastered_at, now - 2000);
      assert.equal(after.mastered.find(row => row.word_id === ids.retained).first_mastered_at, now - 86400000);
      assert.equal(await isolatedRepo.scalar("SELECT CAST(value AS INTEGER) FROM app_meta WHERE key='learning_semantics_version'"), 2);
      assert.equal(await isolatedRepo.dictionaryVersion(), catalog.version);
      await isolatedRepo.migrateLearningSemantics();
      assert.deepEqual(persistedLearningState(isolatedStore), after);
    });
  });
  await check('document-era histories without a migration marker retain their ratings and historical mastery dates', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const ids = await seedLegacyLearningState(isolatedRepo, isolatedStore, now);
      const before = persistedLearningState(isolatedStore);
      await isolatedRepo.migrateLearningSemantics();
      const after = persistedLearningState(isolatedStore);
      assert.deepEqual(after.progress, before.progress); assert.deepEqual(after.records, before.records);
      assert.deepEqual(after.plans, before.plans); assert.deepEqual(after.days, before.days);
      assert.deepEqual(after.mastered, before.mastered); assert.deepEqual(after.session, before.session);
      assert.equal((await isolatedRepo.getProgress(ids.recalled)).strength, 48);
      assert.equal(after.mastered.find(row => row.word_id === ids.retained).first_mastered_at, now - 86400000);
      assert.equal(await isolatedRepo.scalar("SELECT CAST(value AS INTEGER) FROM app_meta WHERE key='learning_semantics_version'"), 2);
      await isolatedRepo.migrateLearningSemantics();
      assert.deepEqual(persistedLearningState(isolatedStore), after);
    });
  });
  await check('failed version 2 migration rolls back document ratings, mastery, totals and its version marker before retry', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const ids = await seedVersionOneLearningState(isolatedRepo, isolatedStore, now);
      const before = persistedLearningState(isolatedStore);
      await isolatedStore.executeSql("CREATE TRIGGER reject_learning_migration BEFORE INSERT ON app_meta WHEN NEW.key='learning_semantics_version' AND NEW.value='2' BEGIN SELECT RAISE(ABORT,'simulated migration failure'); END");
      await assert.rejects(isolatedRepo.migrateLearningSemantics(), /simulated migration failure/);
      assert.deepEqual(persistedLearningState(isolatedStore), before);
      assert.equal(await isolatedRepo.scalar("SELECT CAST(value AS INTEGER) FROM app_meta WHERE key='learning_semantics_version'"), 1);
      await isolatedStore.executeSql('DROP TRIGGER reject_learning_migration');
      await isolatedRepo.migrateLearningSemantics();
      assert.equal((await isolatedRepo.getProgress(ids.recalled)).strength, 48);
      assert.equal((await isolatedRepo.getProgress(ids.mastery)).strength, 96);
      assert.equal((await isolatedRepo.getDays())[0].totalCount, 8);
      assert.equal(await isolatedRepo.scalar("SELECT CAST(value AS INTEGER) FROM app_meta WHERE key='learning_semantics_version'"), 2);
      assert.equal((await isolatedRepo.getStatistics(now)).mastered, 2);
    });
  });
  await check('document due queue includes words exactly at their review time and prioritizes overdue time before strength', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const entries = await isolatedRepo.getWords('', 'all', '');
      for (const [entry, dueAt, strength] of [[entries[0], now - 600000, 90], [entries[1], now, 0],
        [entries[2], now + 1, 0]]) {
        await isolatedStore.executeSql('INSERT INTO word_progress(word_id,review_count,strength,next_review_at) VALUES(?,1,?,?)',
          [entry.id, strength, dueAt]);
      }
      const before = persistedLearningState(isolatedStore);
      assert.deepEqual((await isolatedRepo.getDue(now, 10)).map(entry => entry.id), [entries[0].id, entries[1].id]);
      assert.deepEqual((await isolatedRepo.getDue(now - 1, 10)).map(entry => entry.id), [entries[0].id]);
      await isolatedStore.executeSql('UPDATE word_progress SET next_review_at=? WHERE word_id=?', [now, entries[2].id]);
      assert.deepEqual((await isolatedRepo.getDue(now, 10)).map(entry => entry.id), [entries[0].id, entries[1].id, entries[2].id]);
      await isolatedStore.executeSql('UPDATE word_progress SET strength=25 WHERE word_id=?', [entries[1].id]);
      assert.deepEqual((await isolatedRepo.getDue(now, 10)).map(entry => entry.id), [entries[0].id, entries[2].id, entries[1].id]);
      assert.deepEqual(persistedLearningState(isolatedStore).records, before.records);
      assert.deepEqual(persistedLearningState(isolatedStore).days, before.days);
    });
  });
  await check('learned dates use first new-word events across local midnight and keep shared identities in one group', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      assert.deepEqual(await isolatedRepo.getLearnedDates(), []);
      assert.deepEqual(await isolatedRepo.getLearnedWords(''), []);
      assert.deepEqual(await isolatedRepo.getChallengeWords(), []);
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(word('midnight_edge', '午夜边界'), word('favorite_only', '仅收藏'));
      await isolatedRepo.importCatalog(extended);
      const entries = await isolatedRepo.getWords('', 'all', '');
      const byWord = new Map(entries.map(entry => [entry.word, entry.id]));
      const beforeMidnight = new Date(2026, 9, 5, 23, 59, 59, 999).getTime();
      const midnight = new Date(2026, 9, 6).getTime();
      const nextMidnight = new Date(2026, 9, 6, 23, 59, 59, 999).getTime();
      await seedLearnedWord(isolatedStore, byWord.get('resilient'), beforeMidnight, 62);
      await seedLearnedWord(isolatedStore, byWord.get('retain'), midnight, 25);
      await seedLearnedWord(isolatedStore, byWord.get('midnight_edge'), nextMidnight, 75);
      await seedLearnedWord(isolatedStore, byWord.get('maintain'), undefined, 50);
      await isolatedRepo.setFlag(byWord.get('favorite_only'), true, true);
      const laterReview = new Date(2026, 9, 7, 12).getTime();
      const repeatedNew = new Date(2026, 9, 8, 12).getTime();
      for (const [id, at, type] of [[byWord.get('resilient'), laterReview, 'review'],
        [byWord.get('resilient'), repeatedNew, 'new'], [byWord.get('maintain'), laterReview, 'review']]) {
        await isolatedStore.executeSql('INSERT INTO review_record(word_id,result,review_at,response_ms,previous_level,next_level,previous_strength,next_strength,item_type) VALUES(?,?,?,?,?,?,?,?,?)',
          [id, models.ReviewResult.KNOW, at, 1000, 1, 2, 50, 62, type]);
      }
      await isolatedStore.executeSql('UPDATE word_progress SET last_review_at=?,review_count=3 WHERE word_id=?',
        [repeatedNew, byWord.get('resilient')]);
      const before = persistedLearningState(isolatedStore);
      assert.deepEqual((await isolatedRepo.getLearnedDates()).map(group => [group.date, group.count]),
        [['2026-10-06', 2], ['2026-10-05', 1], ['', 1]]);
      const previousDay = await isolatedRepo.getLearnedWords('2026-10-05');
      assert.deepEqual(previousDay.map(item => [item.word.id, item.firstLearnedAt, item.strength]),
        [[byWord.get('resilient'), beforeMidnight, 62]]);
      const day = await isolatedRepo.getLearnedWords('2026-10-06');
      assert.deepEqual(new Set(day.map(item => item.word.id)),
        new Set([byWord.get('retain'), byWord.get('midnight_edge')]));
      assert.equal(day.find(item => item.word.id === byWord.get('retain')).firstLearnedAt, midnight);
      assert.equal(day.find(item => item.word.id === byWord.get('midnight_edge')).firstLearnedAt, nextMidnight);
      assert.deepEqual((await isolatedRepo.getLearnedWords('')).map(item => [item.word.id, item.firstLearnedAt]),
        [[byWord.get('maintain'), 0]]);
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-07'), []);
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-08'), []);
      assert.equal(new Set([...previousDay, ...day, ...await isolatedRepo.getLearnedWords('')]
        .map(item => item.word.id)).size, 4);
      assert.deepEqual(persistedLearningState(isolatedStore), before);
    });
  });
  await check('learned date lookup rejects invalid dates without substituting another day or unknown history', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const entry = (await isolatedRepo.getWords('', 'all', ''))[0];
      await seedLearnedWord(isolatedStore, entry.id, undefined);
      const before = persistedLearningState(isolatedStore);
      for (const date of ['2026-02-30', '2026-13-01', '2026-10-32', '2026-1-06', 'not-a-date', "2026-10-06' OR 1=1--"]) {
        await assert.rejects(isolatedRepo.getLearnedWords(date));
      }
      assert.deepEqual(await isolatedRepo.getLearnedWords('2024-02-29'), []);
      assert.equal((await isolatedRepo.getLearnedWords('')).length, 1);
      assert.deepEqual(persistedLearningState(isolatedStore), before);
    });
  });
  await check('learned date pagination retrieves more than 80 words without gaps or repeats and challenge candidate sampling is bounded', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const fixtures = Array.from({ length: 83 }, (_, index) => word(`learned_page_${String(index).padStart(3, '0')}`, `分页测试释义 ${index}`));
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(...fixtures);
      await isolatedRepo.importCatalog(extended);
      const entries = (await isolatedRepo.getWords('', 'all', '', 500)).filter(entry => entry.word.startsWith('learned_page_'));
      assert.equal(entries.length, 83);
      const firstAt = new Date(2026, 9, 9, 12).getTime();
      for (let index = 0; index < entries.length; index++) {
        await seedLearnedWord(isolatedStore, entries[index].id, firstAt + index);
      }
      const before = persistedLearningState(isolatedStore);
      assert.deepEqual((await isolatedRepo.getLearnedDates()).map(group => [group.date, group.count]), [['2026-10-09', 83]]);
      const firstPage = await isolatedRepo.getLearnedWords('2026-10-09');
      const secondPage = await isolatedRepo.getLearnedWords('2026-10-09', '', 50, 50);
      assert.equal(firstPage.length, 50); assert.equal(secondPage.length, 33);
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-09', '', 0, 50), firstPage);
      const pagedIds = [...firstPage, ...secondPage].map(item => item.word.id);
      assert.equal(new Set(pagedIds).size, 83);
      assert.deepEqual(new Set(pagedIds), new Set(entries.map(entry => entry.id)));
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-09', '', 80, 50), secondPage.slice(30));
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-09', '', 83, 50), []);
      const eligibleIds = new Set(entries.map(entry => entry.id));
      assert.equal((await isolatedRepo.getChallengeWords()).length, 10);
      for (const limit of [1, 10, 500, 5000]) {
        const challenge = await isolatedRepo.getChallengeWords(limit, 'cet6');
        assert.equal(challenge.length, Math.min(limit, 1000, entries.length));
        assert.equal(new Set(challenge.map(entry => entry.id)).size, challenge.length);
        assert.equal(challenge.every(entry => eligibleIds.has(entry.id) && entry.meaning.trim().length > 0), true);
      }
      assert.deepEqual(persistedLearningState(isolatedStore), before);
    });
  });
  await check('learned word search supports English prefixes, Chinese meanings and literal LIKE metacharacters', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const fixtures = [word('glow', 'n. 光亮；亮度'), word('gloom', 'n. 阴暗'), word('afterglow', 'n. 余辉'),
        word('%literal', '百分号词条'), word('_literal', '下划线词条'), word('\\literal', '反斜线词条'),
        word('percent_meaning', '比例为 50%'), word('underscore_meaning', '符号为 _'), word('slash_meaning', '路径为 \\')];
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(...fixtures);
      await isolatedRepo.importCatalog(extended);
      const fixtureNames = new Set(fixtures.map(entry => entry.word));
      const entries = (await isolatedRepo.getWords('', 'all', '')).filter(entry => fixtureNames.has(entry.word));
      for (const entry of entries) await seedLearnedWord(isolatedStore, entry.id, new Date(2026, 9, 10, 12).getTime());
      const before = persistedLearningState(isolatedStore);
      const find = async query => new Set((await isolatedRepo.getLearnedWords('2026-10-10', query)).map(item => item.word.word));
      assert.deepEqual(await find(' GLO '), new Set(['glow', 'gloom']));
      assert.deepEqual(await find('glow'), new Set(['glow']));
      assert.deepEqual(await find('亮度'), new Set(['glow']));
      assert.deepEqual(await find('余辉'), new Set(['afterglow']));
      assert.deepEqual(await find('%'), new Set(['%literal', 'percent_meaning']));
      assert.deepEqual(await find('_'), new Set(['_literal', 'underscore_meaning']));
      assert.deepEqual(await find('\\'), new Set(['\\literal', 'slash_meaning']));
      assert.deepEqual(await find("' OR 1=1--"), new Set());
      assert.deepEqual(persistedLearningState(isolatedStore), before);
    });
  });
  await check('learned lists and challenges use current-book definitions without restricting shared learned candidates or changing data', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const entries = await isolatedRepo.getWords('', 'all', '');
      const learnedAt = new Date(2026, 9, 11, 12).getTime();
      for (const entry of entries) await seedLearnedWord(isolatedStore, entry.id, learnedAt);
      const shared = entries.find(entry => entry.word === 'resilient');
      const override = word('Resilient', '自定义义一；自定义义二'); override.phonetic = '/custom/';
      await isolatedRepo.insertBook({ id: 'custom_learned', name: '自定义已学', category: 'custom', description: '', words: [override] });
      await isolatedStore.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('empty_meaning','','   ','','')");
      const emptyMeaning = await isolatedRepo.scalar("SELECT id FROM word WHERE word='empty_meaning'");
      await seedLearnedWord(isolatedStore, emptyMeaning, learnedAt);
      await isolatedStore.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('flagged_unlearned','','未学词义','','')");
      const flagged = await isolatedRepo.scalar("SELECT id FROM word WHERE word='flagged_unlearned'");
      await isolatedRepo.setFlag(flagged, true, true);
      const before = persistedLearningState(isolatedStore);
      const definitionsBefore = isolatedStore.db.prepare('SELECT * FROM word ORDER BY id').all();
      const membershipsBefore = isolatedStore.db.prepare('SELECT * FROM word_book_item ORDER BY book_id,word_id').all();
      const list = await isolatedRepo.getLearnedWords('2026-10-11', '', 0, 50, 'custom_learned');
      assert.equal(list.length, 4); assert.equal(new Set(list.map(item => item.word.id)).size, 4);
      const custom = list.find(item => item.word.id === shared.id).word;
      assert.equal(custom.meaning, override.meaning); assert.equal(custom.phonetic, override.phonetic);
      assert.equal(custom.sourceBookId, 'custom_learned');
      assert.deepEqual((await isolatedRepo.getLearnedWords('2026-10-11', '自定义义二', 0, 50, 'custom_learned'))
        .map(item => item.word.id), [shared.id]);
      assert.deepEqual(await isolatedRepo.getLearnedWords('2026-10-11', '韧性', 0, 50, 'custom_learned'), []);
      assert.equal((await isolatedRepo.getLearnedWords('2026-10-11', '韧性'))[0].word.meaning, 'adj. 有韧性的');
      const challenge = await isolatedRepo.getChallengeWords(10, 'custom_learned');
      assert.equal(challenge.length, 3); assert.equal(new Set(challenge.map(entry => entry.id)).size, 3);
      assert.deepEqual(new Set(challenge.map(entry => entry.id)), new Set(entries.map(entry => entry.id)));
      assert.equal(challenge.find(entry => entry.id === shared.id).meaning, override.meaning);
      assert.equal(challenge.some(entry => entry.word === 'maintain'), true);
      assert.equal(challenge.some(entry => entry.id === emptyMeaning || entry.id === flagged), false);
      assert.deepEqual(persistedLearningState(isolatedStore), before);
      assert.deepEqual(isolatedStore.db.prepare('SELECT * FROM word ORDER BY id').all(), definitionsBefore);
      assert.deepEqual(isolatedStore.db.prepare('SELECT * FROM word_book_item ORDER BY book_id,word_id').all(), membershipsBefore);
    });
  });
  await check('legacy exam and busy preferences cannot shrink the saved daily new-word goal under heavy review backlog', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(...Array.from({ length: 180 }, (_, index) => word(`goal_fixture_${index}`, '目标测试词')));
      await isolatedRepo.importCatalog(extended);
      const isolatedService = new LearningService(); await isolatedService.initialize(contextFor(extended));
      const entries = await isolatedRepo.queryWords('SELECT * FROM word ORDER BY id');
      for (const entry of entries.slice(0, 101)) {
        await isolatedStore.executeSql('INSERT INTO word_progress(word_id,review_count,strength,next_review_at) VALUES(?,1,30,?)',
          [entry.id, now - 1000]);
      }
      await isolatedStore.executeSql("UPDATE daily_plan SET budget='busy'");
      const settings = isolatedService.getSettings();
      settings.learningMode = 'exam'; settings.dailyNewTarget = 20; settings.reminderEnabled = true;
      await isolatedService.updateSettings(settings);
      const snapshot = await isolatedService.getSnapshot();
      assert.equal(snapshot.settings.learningMode, 'exam'); assert.equal(snapshot.settings.reminderEnabled, true);
      assert.equal(snapshot.settings.dailyNewTarget, 20); assert.equal(snapshot.plan.budget, 'normal');
      assert.equal(snapshot.plan.backlogCount, 101); assert.equal(snapshot.plan.reviewTarget, 21);
      assert.equal(snapshot.plan.newTarget, 20);
      const session = await isolatedService.startSession('today');
      assert.equal(session.items.filter(item => item.type === 'new').length, 20);
      assert.equal(session.items.filter(item => item.type === 'review').length, 21);
      settings.dailyNewTarget = 40; await isolatedService.updateSettings(settings);
      assert.equal((await isolatedService.getSnapshot()).plan.newTarget, 40);
    });
  });
  await check('custom target changes preserve committed new words and never reduce the plan below completed progress', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(...Array.from({ length: 10 }, (_, index) => word(`target_fixture_${index}`, '变更测试词')));
      await isolatedRepo.importCatalog(extended);
      const isolatedService = new LearningService(); await isolatedService.initialize(contextFor(extended));
      const session = await isolatedService.startSession('onboarding'); assert.equal(session.items.length, 3);
      for (let index = 0; index < 3; index++) await isolatedService.record(models.ReviewResult.KNOW, 1000);
      const recordsBefore = isolatedStore.db.prepare('SELECT * FROM review_record ORDER BY id').all();
      await isolatedStore.executeSql("UPDATE daily_plan SET budget='free'");
      const settings = isolatedService.getSettings(); settings.learningMode = 'exam'; settings.dailyNewTarget = 2;
      await isolatedService.updateSettings(settings);
      let snapshot = await isolatedService.getSnapshot();
      assert.equal(snapshot.settings.dailyNewTarget, 2); assert.equal(snapshot.plan.budget, 'normal');
      assert.equal(snapshot.plan.newTarget, 3); assert.equal(snapshot.plan.newDone, 3);
      assert.equal(snapshot.stats.days.find(day => day.date === snapshot.plan.date).newCount, 3);
      settings.dailyNewTarget = 8; await isolatedService.updateSettings(settings);
      snapshot = await isolatedService.getSnapshot();
      assert.equal(snapshot.settings.dailyNewTarget, 8); assert.equal(snapshot.plan.newTarget, 8);
      assert.equal(snapshot.plan.newDone, 3); assert.equal((await isolatedRepo.getPlan(snapshot.plan.date)).newDone, 3);
      assert.deepEqual(isolatedStore.db.prepare('SELECT * FROM review_record ORDER BY id').all(), recordsBefore);
      assert.equal((await isolatedService.startSession('today')).items.filter(item => item.type === 'new').length, 5);
    });
  });
  await check('daily plan caps only at available fresh vocabulary while leaving the custom target and completed count intact', async () => {
    await withIsolatedRepository(async (isolatedRepo) => {
      const isolatedService = new LearningService(); await isolatedService.initialize(contextFor(catalog));
      const available = await isolatedRepo.countUnlearned('cet4'); assert.equal(available, 2);
      const settings = isolatedService.getSettings(); settings.dailyNewTarget = 50;
      await isolatedService.updateSettings(settings);
      assert.equal((await isolatedService.getSnapshot()).plan.newTarget, available);
      const session = await isolatedService.startSession('today'); assert.equal(session.items.length, available);
      await isolatedService.record(models.ReviewResult.KNOW, 1000);
      let snapshot = await isolatedService.getSnapshot();
      assert.equal(snapshot.plan.newDone, 1); assert.equal(snapshot.plan.newTarget, available);
      await isolatedService.record(models.ReviewResult.KNOW, 1000);
      snapshot = await isolatedService.getSnapshot();
      assert.equal(await isolatedRepo.countUnlearned('cet4'), 0);
      assert.equal(snapshot.plan.newDone, available); assert.equal(snapshot.plan.newTarget, available);
      assert.equal(snapshot.settings.dailyNewTarget, 50);
      assert.equal(snapshot.stats.days.find(day => day.date === snapshot.plan.date).newCount, available);
    });
  });
  await check('quick practice keeps its six or three fresh-word quota despite a legacy busy plan', async () => {
    await withIsolatedRepository(async (isolatedRepo, isolatedStore) => {
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version = 2;
      extended.books[0].words.push(...Array.from({ length: 10 }, (_, index) => word(`quick_fixture_${index}`, '速学测试词')));
      await isolatedRepo.importCatalog(extended);
      const isolatedService = new LearningService(); await isolatedService.initialize(contextFor(extended));
      await isolatedStore.executeSql("UPDATE daily_plan SET budget='busy'");
      let session = await isolatedService.startSession('quick');
      assert.equal(session.items.filter(item => item.type === 'new').length, 6);
      assert.equal(session.items.filter(item => item.type === 'review').length, 0);
      await isolatedService.clearSession();
      const entries = await isolatedRepo.getWords('cet4', 'all', '');
      for (const entry of entries.slice(0, 5)) {
        await isolatedStore.executeSql('INSERT INTO word_progress(word_id,review_count,next_review_at) VALUES(?,1,?)', [entry.id, now - 1000]);
      }
      await isolatedStore.executeSql("UPDATE daily_plan SET budget='busy'");
      session = await isolatedService.startSession('quick');
      assert.equal(session.items.filter(item => item.type === 'new').length, 3);
      assert.equal(session.items.filter(item => item.type === 'review').length, 5);
      assert.equal((await isolatedService.getSnapshot()).plan.budget, 'normal');
    });
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
  await check('midnight resets counters and ignores legacy budget while retaining pending session', async () => {
    await store.executeSql("UPDATE daily_plan SET budget='busy' WHERE date='2026-10-06'");
    assert.equal((await service.getSnapshot()).plan.budget, 'normal');
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

  const backupState = service => service.exportData().then(text => BackupService.parse(text));
  const reminderFields = settings => ({ enabled: settings.reminderEnabled,
    hour: settings.reminderHour, minute: settings.reminderMinute });
  const normalizeBackup = backup => {
    const normalized = JSON.parse(JSON.stringify(backup));
    const identities = new Map(backup.words.map(word => [word.id, word.word.trim().toLowerCase()]));
    const spelling = id => { assert.ok(identities.has(id), `unknown backup word ${id}`); return identities.get(id); };
    normalized.wordIdentities = (normalized.wordIdentities || []).map(item => ({ word: spelling(item.id) }))
      .sort((a, b) => a.word.localeCompare(b.word));
    normalized.words = normalized.words.map(item => ({ ...item, id: spelling(item.id), word: item.word.trim().toLowerCase() }))
      .sort((a, b) => a.word.localeCompare(b.word));
    for (const book of normalized.books) {
      book.words = book.words.map(item => ({ ...item, id: spelling(item.id) }));
    }
    normalized.progress = normalized.progress.map(item => ({ ...item, wordId: spelling(item.wordId) }))
      .sort((a, b) => a.wordId.localeCompare(b.wordId));
    normalized.records = normalized.records.map(item => ({ ...item, wordId: spelling(item.wordId) }));
    normalized.masteredWords = normalized.masteredWords.map(item => ({ ...item, wordId: spelling(item.wordId) }))
      .sort((a, b) => a.wordId.localeCompare(b.wordId));
    normalized.session.items.forEach(item => { item.word.id = spelling(item.word.id); });
    delete normalized.exportedAt;
    delete normalized.settings.reminderEnabled;
    delete normalized.settings.reminderHour;
    delete normalized.settings.reminderMinute;
    return normalized;
  };
  const legacyBackup = async (service, repo, version) => {
    const backup = await backupState(service);
    backup.version = version;
    for (const book of backup.books) { book.words = await repo.backupBookWords(book.id); }
    delete backup.compact; delete backup.wordIdentities; delete backup.words;
    delete backup.dictionaryVersion; delete backup.masteredWords;
    return backup;
  };
  const wholeDatabase = store => Object.fromEntries(store.db.prepare(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all()
    .map(({ name }) => [name, store.db.prepare(`SELECT * FROM ${name} ORDER BY rowid`).all()]));
  const seedBackup = async (source, repo, store) => {
    await source.importWords('备份顺序与自定义释义', [word('maintain', '专属释义一'),
      word('resilient', '专属释义二'), word('zebra', '斑马')]);
    const book = (await repo.getBooks()).find(book => book.category === 'custom');
    const settings = source.getSettings();
    Object.assign(settings, { currentBookId: book.id, dailyNewTarget: 3, autoPronounce: true,
      autoPronounceConfigured: true, onboarded: true, reminderEnabled: true, reminderHour: 7,
      reminderMinute: 15, themeMode: 'dark', spellingRecall: true, hapticsEnabled: false });
    await source.updateSettings(settings);
    const session = await source.startSession('quick');
    await source.record(models.ReviewResult.KNOW, 1500);
    await source.record(models.ReviewResult.FUZZY, 4500);
    await source.setFavorite(session.items[0].word.id, true);
    await source.setNewWord(session.items[1].word.id, true);
    await source.savePracticeResult('spelling', 2, 3, 5000);
    // A formerly edited/deleted membership must not lose its historical word or explicit IDs.
    await store.executeSql("INSERT INTO word(id,word,phonetic,meaning,example,translation) VALUES(9001,'orphaned_history','','曾学词','','')");
    await seedLearnedWord(store, 9001, now - 86400000, 80);
    await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)', [9001, now - 86400000]);
    await store.executeSql("INSERT INTO daily_glow(date,earned_on,reason) VALUES('2026-09-01','2026-09-02','额外学习点亮')");
    await source.getSnapshot();
    return backupState(source);
  };
  await check('compact backup v3 maps different device IDs by spelling and preserves order, definitions, orphan history and settings', async () => {
    await withIsolatedRepository(async (sourceRepo, sourceDb) => {
      const source = new LearningService(); await source.initialize(contextFor(catalog));
      const original = await seedBackup(source, sourceRepo, sourceDb);
      const sourceStats = await sourceRepo.getStatistics(now);
      const originalReminder = reminderFields(source.getSettings());
      let returning;
      await withIsolatedRepository(async (destinationRepo, destinationDb) => {
        // Deliberately allocate different local IDs before importing the bundled catalog.
        await destinationDb.executeSql("INSERT INTO word(id,word,phonetic,meaning,example,translation) VALUES(8000,'destination_only','','目标设备本地词','','')");
        const destination = new LearningService(); await destination.initialize(contextFor(catalog));
        const local = destination.getSettings();
        local.reminderEnabled = false; local.reminderHour = 22; local.reminderMinute = 45;
        await destination.updateSettings(local);
        await destinationDb.executeSql("INSERT INTO app_meta(key,value) VALUES('reminder_probe','local-registration')");
        await destination.restoreData(original);
        assert.deepEqual(normalizeBackup(await backupState(destination)), normalizeBackup(original));
        assert.deepEqual(reminderFields(destination.getSettings()), { enabled: false, hour: 22, minute: 45 });
        assert.equal(await destinationRepo.scalar("SELECT COUNT(*) FROM app_meta WHERE key='reminder_probe' AND value='local-registration'"), 1);
        assert.deepEqual(await destinationRepo.getStatistics(now), sourceStats);
        const book = original.books.find(book => book.category === 'custom');
        assert.deepEqual((await destinationRepo.backupBookWords(book.id)).map(word => [word.word, word.meaning]),
          book.words.map(word => [word.word, word.meaning]));
        const orphan = await destinationRepo.findWordBySpelling('orphaned_history');
        assert.ok(orphan); assert.notEqual(orphan.id, 9001);
        assert.equal((await destination.getProgress(orphan.id)).strength, 80);
        const restarted = new LearningService(); await restarted.initialize(contextFor(catalog));
        assert.deepEqual(normalizeBackup(await backupState(restarted)), normalizeBackup(original));
        assert.equal(restarted.getSettings().autoPronounceConfigured, true);
        assert.equal(restarted.getSettings().autoPronounce, true);
        assert.deepEqual(reminderFields(restarted.getSettings()), { enabled: false, hour: 22, minute: 45 });
        assert.deepEqual(normalizeBackup(await backupState(restarted)).session, normalizeBackup(original).session);
        returning = await backupState(restarted);
      });
      await source.restoreData(returning);
      assert.deepEqual(normalizeBackup(await backupState(source)), normalizeBackup(original));
      assert.deepEqual(reminderFields(source.getSettings()), originalReminder);
      const next = await source.record(models.ReviewResult.KNOW, 1000);
      assert.equal(next.index, original.session.index + 1, 'restored cursor continues with the next word');
      const after = await backupState(source);
      assert.ok(after.records.at(-1).id > Math.max(...original.records.map(record => record.id)));
      assert.equal(after.records.length, original.records.length + 1);
    });
  });
  await check('legacy v1 backup recovers IDs and infers only missing new/review types without inventing voice consent', async () => {
    await withIsolatedRepository(async (repo) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      await service.startSession('today'); await service.record(models.ReviewResult.KNOW, 1000);
      const legacy = await legacyBackup(service, repo, 1);
      delete legacy.practiceResults; delete legacy.glowRecords; delete legacy.settings.autoPronounceConfigured;
      legacy.settings.autoPronounce = true;
      for (const record of legacy.records) delete record.itemType;
      for (const progress of legacy.progress) {
        delete progress.hesitationCount; delete progress.lastResponseMs;
        delete progress.consecutiveFailures; delete progress.consecutiveKnown;
      }
      for (const plan of legacy.plans) delete plan.backlogCount;
      await service.restoreData(legacy);
      assert.equal((await repo.allRecords())[0].itemType, 'new');
      assert.equal(service.getSettings().autoPronounce, false);
      assert.equal(service.getSettings().autoPronounceConfigured, false);
      assert.equal((await repo.allProgress())[0].hesitationCount, 0);
      const restarted = new LearningService(); await restarted.initialize(contextFor(catalog));
      assert.equal((await restarted.getHistory(legacy.records[0].wordId)).length, 1);
    });
  });
  await check('legacy v2 preserves explicit review type at level zero and restores mastery and optional history', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      await service.startSession('today'); await service.record(models.ReviewResult.KNOW, 1000);
      const legacy = await legacyBackup(service, repo, 2);
      legacy.records[0].itemType = 'review'; legacy.records[0].previousLevel = 0;
      legacy.records[0].nextStrength = 80; legacy.progress[0].strength = 80;
      await service.restoreData(legacy);
      assert.equal((await repo.allRecords())[0].itemType, 'review');
      assert.deepEqual(await repo.allMasteredWords(), [Object.assign(new models.MasteredWord(), {
        wordId: legacy.records[0].wordId, firstMasteredAt: legacy.records[0].reviewAt })]);
      assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM word_progress').get().count, 1);
    });
  });
  await check('damaged, conflicting and future backups reject before any durable or in-memory replacement', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const valid = await seedBackup(service, repo, store);
      const before = wholeDatabase(store); const session = service.getSession(); const settings = service.getSettings();
      assert.throws(() => BackupService.parse('{"format":'), /完整/);
      for (const damage of [b => { b.version = 6; }, b => { b.wordIdentities.push(b.wordIdentities[0]); },
        b => { b.progress[0].wordId = 999999; }, b => { b.records[0].itemType = 'anything'; },
        b => { b.session.index = 99; }, b => { b.books.find(book => book.category === 'custom').words[0].id = 999999; },
        b => { b.settings.dailyNewTarget = 0; }, b => { b.days[0].date = '2026-02-30'; },
        b => { b.wordIdentities[0].word = b.wordIdentities[1].word; }, b => { b.records.push(null); }]) {
        const broken = JSON.parse(JSON.stringify(valid)); damage(broken);
        await assert.rejects(service.restoreData(broken));
        assert.deepEqual(wholeDatabase(store), before);
        assert.deepEqual(service.getSession(), session); assert.deepEqual(service.getSettings(), settings);
      }
      await service.restoreData(valid); // A failed validation must not poison the operation queue.
    });
  });
  await check('an interrupted restore rolls back deletes, inserts, settings and session atomically and can retry', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const imported = await seedBackup(service, repo, store);
      await service.setFavorite(imported.progress[0].wordId, false);
      const current = service.getSettings(); current.themeMode = 'light'; await service.updateSettings(current);
      const before = wholeDatabase(store); const oldSession = service.getSession();
      const transaction = store.createTransaction.bind(store);
      store.createTransaction = async () => {
        const tx = await transaction(); const batch = tx.batchInsert;
        tx.batchInsert = async (table, values) => {
          if (table === 'daily_summary') throw new Error('simulated full disk while restoring');
          return batch(table, values);
        };
        return tx;
      };
      await assert.rejects(service.restoreData(imported), /simulated full disk/);
      assert.deepEqual(wholeDatabase(store), before);
      assert.deepEqual(service.getSettings(), current); assert.deepEqual(service.getSession(), oldSession);
      store.createTransaction = transaction;
      await service.restoreData(imported);
      assert.deepEqual(normalizeBackup(await backupState(service)), normalizeBackup(imported));
    });
  });
  await check('a delayed old-home snapshot finishes before restore and cannot overwrite restored daily progress', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const imported = await backupState(service); imported.plans = []; imported.days = [];
      await store.executeSql('UPDATE daily_plan SET new_done=5');
      const due = service.repository.countDue.bind(service.repository);
      let release; const gate = new Promise(resolve => { release = resolve; });
      let announce; const reached = new Promise(resolve => { announce = resolve; });
      let once = true;
      service.repository.countDue = async value => {
        if (once) { once = false; announce(); await gate; }
        return due(value);
      };
      const snapshot = service.getSnapshot(); await reached;
      let restored = false;
      const restoration = service.restoreData(imported).then(() => { restored = true; });
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(restored, false, 'restore waits for outstanding mutation-capable reads');
      release(); await snapshot; await restoration;
      assert.deepEqual(await repo.allPlans(), [], 'old newDone=5 cannot reappear after restore');
    });
  });
  await check('export waits for an in-flight answer and captures matching events, counters and session cursor', async () => {
    await withIsolatedRepository(async () => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      await service.startSession('today');
      const record = service.repository.record.bind(service.repository);
      let release; const gate = new Promise(resolve => { release = resolve; });
      let announce; const reached = new Promise(resolve => { announce = resolve; });
      service.repository.record = async (...args) => { announce(); await gate; return record(...args); };
      const answering = service.record(models.ReviewResult.KNOW, 1000); await reached;
      let exported = false;
      const exporting = backupState(service).then(backup => { exported = true; return backup; });
      await new Promise(resolve => setImmediate(resolve)); assert.equal(exported, false);
      release(); await answering; const backup = await exporting;
      assert.equal(backup.records.length, 1); assert.equal(backup.progress[0].reviewCount, 1);
      assert.equal(backup.session.index, 1); assert.equal(backup.days[0].newCount, 1);
    });
  });

  await check('legacy full v3 backups remain restorable alongside compact v3', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const original = await seedBackup(service, repo, store);
      const full = JSON.parse(JSON.stringify(original)); full.compact = false;
      full.words = await repo.allWords();
      for (const book of full.books) { book.words = await repo.backupBookWords(book.id); }
      delete full.wordIdentities;
      const originalSemantic = normalizeBackup(original);
      await service.setFavorite(original.progress[0].wordId, false);
      assert.equal(await service.restoreData(full), 0);
      assert.deepEqual(normalizeBackup(await backupState(service)), originalSemantic);
    });
  });
  await check('safety backup failure aborts restore before any data or session changes', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const imported = await seedBackup(service, repo, store);
      const before = wholeDatabase(store), session = service.getSession(), settings = service.getSettings();
      const backup = store.backup; store.backup = async () => { throw new Error('safety backup full disk'); };
      await assert.rejects(service.restoreData(imported), /safety backup full disk/);
      assert.deepEqual(wholeDatabase(store), before); assert.deepEqual(service.getSession(), session);
      assert.deepEqual(service.getSettings(), settings); store.backup = backup;
      assert.equal(await service.restoreData(imported), 0);
    });
  });
  await check('failed rollback still attempts safety restore and leaves the previous database intact', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const imported = await seedBackup(service, repo, store);
      const before = wholeDatabase(store);
      const createTransaction = store.createTransaction.bind(store);
      store.createTransaction = async () => {
        const transaction = await createTransaction(), batch = transaction.batchInsert, rollback = transaction.rollback;
        transaction.batchInsert = async (table, values) => {
          if (table === 'daily_summary') { throw new Error('restore write failed'); }
          return batch(table, values);
        };
        transaction.rollback = async () => { await rollback(); throw new Error('rollback reporting failure'); };
        return transaction;
      };
      await assert.rejects(service.restoreData(imported), /restore write failed/);
      assert.equal(store.restores, 1); assert.deepEqual(wholeDatabase(store), before);
      store.createTransaction = createTransaction;
    });
  });
  await check('schema 3 to 6 migration rolls all DDL and user_version back on interruption', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const entry = (await repo.getWords('', 'all', ''))[0];
      await seedLearnedWord(store, entry.id, now - 1000, 84);
      for (const table of ['sentence_recall_attempt', 'pending_word', 'sentence_memory', 'reading_progress', 'practice_attempt']) {
        await store.executeSql(`DROP TABLE ${table}`);
      }
      await store.executeSql('DROP TABLE article'); await store.executeSql('DROP TABLE review_undo');
      await store.executeSql('DROP INDEX idx_progress_mistakes'); store.version = 3;
      const before = wholeDatabase(store), createTransaction = store.createTransaction.bind(store);
      store.createTransaction = async () => {
        const transaction = await createTransaction(), execute = transaction.execute;
        transaction.execute = async (sql, args) => {
          if (sql.includes('CREATE TABLE IF NOT EXISTS article')) { throw new Error('schema 4 DDL interrupted'); }
          return execute(sql, args);
        };
        return transaction;
      };
      await assert.rejects(new DatabaseManager().initialize(contextFor(catalog)), /schema 4 DDL interrupted/);
      assert.equal(store.version, 3); assert.deepEqual(wholeDatabase(store), before);
      assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name='review_undo'").get().n, 0);
      store.createTransaction = createTransaction;
      await new DatabaseManager().initialize(contextFor(catalog)); assert.equal(store.version, 6);
      assert.equal((await repo.getProgress(entry.id)).strength, 84);
      assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name='article'").get().n, 1);
    });
  });
  await check('undo restores every new-word counter, schedule, history and saved cursor, and cannot repeat', async () => {
    await withIsolatedRepository(async (_repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const session = await service.startSession('today'), before = wholeDatabase(store);
      await service.record(models.ReviewResult.KNOW, 1700); assert.equal(service.canUndo(), true);
      assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM review_record').get().n, 1);
      assert.deepEqual(await service.undoLast(), session); assert.equal(service.canUndo(), false);
      assert.deepEqual(wholeDatabase(store), before);
      await assert.rejects(service.undoLast(), /没有可撤销/); assert.deepEqual(wholeDatabase(store), before);
    });
  });
  await check('undo restores existing progress, plan, summary, mastery and glow exactly', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const entry = (await repo.getWords('', 'all', ''))[0];
      await seedLearnedWord(store, entry.id, now - 86400000, 70);
      await store.executeSql('UPDATE word_progress SET next_review_at=?,wrong_count=1,favorite=1,is_new_word=1,hesitation_count=2,last_response_ms=4200,consecutive_failures=2 WHERE word_id=?',
        [now - 1, entry.id]);
      await store.executeSql('INSERT INTO mastered_word(word_id,first_mastered_at) VALUES(?,?)', [entry.id, now - 86400000]);
      const key = domain('utils/TimeUtils.ets').dateKey(now), yesterday = domain('utils/TimeUtils.ets').shiftedDate(now, -1);
      await store.executeSql('INSERT INTO daily_summary(date,new_count,review_count,known_count,total_count,duration_ms) VALUES(?,2,3,1,5,9000)', [key]);
      await store.executeSql('INSERT INTO daily_glow(date,earned_on,reason) VALUES(?,?,?)', [yesterday, key, 'original_glow']);
      const session = await service.startSession('review'), before = wholeDatabase(store);
      assert.equal(session.items[0].word.id, entry.id);
      await service.record(models.ReviewResult.FORGET, 4500); await service.undoLast();
      assert.deepEqual(wholeDatabase(store), before); assert.deepEqual(service.getSession(), session);
    });
  });
  await check('undo removes newly awarded mastery and a newly added glow', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const entry = (await repo.getWords('', 'all', ''))[0];
      await seedLearnedWord(store, entry.id, now - 86400000, 70);
      await store.executeSql('UPDATE word_progress SET next_review_at=? WHERE word_id=?', [now - 1, entry.id]);
      await service.startSession('review'); const before = wholeDatabase(store);
      await service.record(models.ReviewResult.KNOW, 1000);
      assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM mastered_word').get().n, 1);
      assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM daily_glow').get().n, 1);
      await service.undoLast(); assert.deepEqual(wholeDatabase(store), before);
    });
  });
  await check('leaving study invalidates undo and a second answer replaces only the last judgment', async () => {
    await withIsolatedRepository(async (_repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      await service.startSession('quick'); await service.record(models.ReviewResult.FORGET, 800);
      const afterFirst = wholeDatabase(store); afterFirst.review_undo = [];
      await service.record(models.ReviewResult.KNOW, 900); await service.undoLast();
      assert.deepEqual(wholeDatabase(store), afterFirst);
      assert.equal(service.getSession().index, 1); await assert.rejects(service.undoLast(), /没有可撤销/);
      await service.record(models.ReviewResult.FUZZY, 1300); await service.invalidateUndo();
      const departed = wholeDatabase(store); await assert.rejects(service.undoLast(), /没有可撤销/);
      assert.deepEqual(wholeDatabase(store), departed);
    });
  });
  await check('undo and concurrent duplicate undo serialize behind a pending answer', async () => {
    await withIsolatedRepository(async (_repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      await service.startSession('today'); const before = wholeDatabase(store);
      const record = service.repository.record.bind(service.repository);
      let release, announce; const gate = new Promise(r => { release = r; }), reached = new Promise(r => { announce = r; });
      service.repository.record = async (...args) => { announce(); await gate; return record(...args); };
      const answering = service.record(models.ReviewResult.KNOW, 1000); await reached;
      const first = service.undoLast(); const second = service.undoLast().then(() => undefined, error => error);
      release(); await answering; await first; assert.match((await second).message, /没有可撤销/);
      assert.deepEqual(wholeDatabase(store), before);
    });
  });
  await check('mistake book filters mastery and zero errors, paginates in order, and its twenty-word practice updates scheduling', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const extended = JSON.parse(JSON.stringify(catalog)); extended.version++;
      extended.books[0].words.push(...Array.from({ length: 28 }, (_, index) => word(`mistake_${String(index).padStart(2, '0')}`, '错题释义')));
      await repo.importCatalog(extended);
      const entries = (await repo.getWords('', 'all', '', 500)).filter(item => item.word.startsWith('mistake_'));
      for (let index = 0; index < entries.length; index++) {
        await store.executeSql('INSERT INTO word_progress(word_id,review_count,wrong_count,strength,last_review_at,next_review_at) VALUES(?,20,?,?,?,?)',
          [entries[index].id, index < 26 ? index % 5 + 1 : 0, index === 25 ? 75 : 40, now - index * 1000, now + 86400000]);
      }
      const expected = store.db.prepare('SELECT word_id FROM word_progress WHERE wrong_count>0 AND strength<75 ORDER BY wrong_count DESC,last_review_at DESC,word_id').all().map(row => row.word_id);
      assert.equal(expected.length, 25);
      const first = await repo.getMistakes(0, 10), next = await repo.getMistakes(10, 10);
      assert.deepEqual(first.map(item => item.word.id), expected.slice(0, 10));
      assert.deepEqual(next.map(item => item.word.id), expected.slice(10, 20));
      assert.equal((await service.getSnapshot()).mistakeCount, 25);
      const session = await service.startSession('mistake'); assert.equal(session.items.length, 20);
      assert.deepEqual(session.items.map(item => item.word.id), expected.slice(0, 20));
      assert.equal(session.items.every(item => item.type === 'review'), true);
      const before = await service.getProgress(session.items[0].word.id), key = domain('utils/TimeUtils.ets').dateKey(now);
      await service.record(models.ReviewResult.FORGET, 2000);
      const after = await service.getProgress(session.items[0].word.id);
      assert.equal(after.reviewCount, before.reviewCount + 1); assert.equal(after.wrongCount, before.wrongCount + 1);
      assert.ok(after.nextReviewAt < before.nextReviewAt);
      assert.equal((await repo.getPlan(key)).reviewDone, 1); assert.equal((await repo.getDays())[0].reviewCount, 1);
      await store.executeSql('UPDATE word_progress SET strength=75 WHERE word_id=?', [session.items[0].word.id]);
      assert.equal((await repo.getMistakes()).some(item => item.word.id === session.items[0].word.id), false);
    });
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
    assert.equal(legacy.version, 6);
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
    await check('quick mode uses five due plus three fresh without shrinking the custom daily goal', async () => {
      for (const entry of all.slice(0, 65)) {
        await fullDb.getStore().executeSql('INSERT INTO word_progress(word_id,review_count,strength,next_review_at) VALUES(?,1,30,?)', [entry.id, now - 1000]);
      }
      let plan = (await full.getSnapshot()).plan;
      assert.equal(plan.newTarget, 20); assert.equal(plan.reviewTarget, 60);
      await fullDb.getStore().executeSql('UPDATE word_progress SET next_review_at=? WHERE word_id=?', [now + 10000000, all[0].id]);
      assert.equal((await full.getSnapshot()).plan.newTarget, 20);
      const quick = await full.startSession('quick');
      assert.equal(quick.items.filter(item => item.type === 'review').length, 5);
      assert.equal(quick.items.filter(item => item.type === 'new').length, 3);
      const settings = full.getSettings(); settings.learningMode = 'exam'; await full.updateSettings(settings);
      assert.equal((await full.getSnapshot()).plan.newTarget, 20);
      await fullDb.getStore().executeSql('UPDATE word_progress SET wrong_count=99 WHERE word_id=?', [all[64].id]);
      assert.equal((await fullRepo.getDue(now, 5, true))[0].id, all[64].id);
      const untouched = await fullRepo.queryWords('SELECT * FROM word WHERE id NOT IN(SELECT word_id FROM word_progress) LIMIT 36');
      for (const entry of untouched) {
        await fullDb.getStore().executeSql('INSERT INTO word_progress(word_id,review_count,next_review_at) VALUES(?,1,?)', [entry.id, now - 1000]);
      }
      assert.equal((await full.getSnapshot()).dueCount, 100);
      assert.equal((await full.getSnapshot()).plan.newTarget, 20);
    });
    stores.get('ciying.db').db.close(); stores.set('ciying.db', original);
  });
  const { ExperienceRepository } = domain('repository/ExperienceRepository.ets');
  const { ExperienceService, PracticeJournal } = domain('service/ExperienceService.ets');
  const { ArticleRepository } = domain('repository/ArticleRepository.ets');
  const { ArticleService } = domain('service/ArticleService.ets');
  const experience = domain('model/ExperienceModels.ets');
  const { recommendPractice, skillEvidence, originalSentence } = domain('utils/ExperienceUtils.ets');
  const { curatedArticles } = domain('data/CuratedArticles.ets');
  const { articleParagraphs } = domain('utils/ArticleTokenizer.ets');
  const attempt = (id, wordId = 1, mode = 'meaning', correct = false, hinted = false, recordedAt = Date.now()) =>
    Object.assign(new experience.PracticeAttempt(), { id, wordId, mode, correct, hinted, recordedAt, durationMs: 500 });
  const memory = (id, articleId = -1, wordId = 1) => Object.assign(new experience.SentenceMemory(), {
    id, wordId, articleId, articleTitle: '雨天的一把伞', paragraphKey: '0:0',
    sentence: 'She opened her bag.', note: '我的记录', createdAt: Date.now()
  });
  await check('per-word answer retries are idempotent and never change review schedules or daily goals', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      const experiences = new ExperienceRepository(database);
      const before = persistedLearningState(store);
      await Promise.all([experiences.saveAttempt(attempt('same')), experiences.saveAttempt(attempt('same'))]);
      assert.equal((await experiences.attempts(1)).length, 1);
      assert.deepEqual(persistedLearningState(store), before);
      await assert.rejects(experiences.saveAttempt(attempt('bad', 999999)));
      assert.equal((await experiences.attempts()).length, 1);
    });
  });
  await check('practice journal excludes hidden time and reuses the same attempt after retries', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      ExperienceService.getInstance().initialize(database);
      const clock = Date.now; let time = clock(); Date.now = () => time;
      try {
        const journal = new PracticeJournal(); journal.beginQuestion(); time += 1000; journal.pause();
        time += 60000; journal.resume(); time += 500;
        await journal.record(1, 'meaning', true, false); await journal.record(1, 'meaning', true, false);
        const saved = await new ExperienceRepository(database).attempts();
        assert.equal(saved.length, 1); assert.equal(saved[0].durationMs, 1500);
      } finally { Date.now = clock; }
    });
  });
  await check('recommendations use this session or repeated recent errors and clear after independent success', async () => {
    const session = new models.StudySession(); session.startedAt = Date.now() - 2000;
    session.items = [{ word: { id: 1 }, type: 'review' }]; session.index = 1;
    const records = [{ wordId: 1, result: 1, responseMs: 400, reviewAt: Date.now() }];
    const current = recommendPractice([], session, records);
    assert.equal(current.mode, 'meaning'); assert.deepEqual(current.wordIds, [1]);
    assert.equal(recommendPractice([], new models.StudySession(), records).mode, '');
    const missed = [attempt('new', 1, 'dictation', false, false, Date.now()), attempt('old', 1, 'dictation', false, false, Date.now() - 1000)];
    assert.equal(recommendPractice(missed, new models.StudySession(), []).mode, 'dictation');
    assert.equal(recommendPractice(missed.slice(0, 1), new models.StudySession(), []).mode, '');
    assert.equal(recommendPractice([attempt('correct', 1, 'dictation', true), ...missed], new models.StudySession(), []).mode, '');
    const skills = skillEvidence([attempt('hint', 1, 'spelling', true, true)]);
    assert.equal(skills.find(item => item.mode === 'meaning').total, 0);
    assert.equal(skills.find(item => item.mode === 'spelling').hinted, 1);
  });
  await check('targeted practice accepts learned words from another book and excludes unlearned words', async () => {
    await withIsolatedRepository(async (repo, store) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const maintain = await repo.findWordBySpelling('maintain');
      await store.executeSql('INSERT INTO word_progress(word_id,review_count) VALUES(?,1)', [maintain.id]);
      assert.equal((await service.getTargetedWords([maintain.id, maintain.id, 1])).length, 1);
      assert.equal((await service.getTargetedWords([maintain.id]))[0].word, 'maintain');
    });
  });
  await check('original sentences follow the clicked occurrence, preserving punctuation and Unicode', async () => {
    const body = 'A lamp fell. The lamp still works!\n中文说明。She opened her bag.';
    assert.equal(originalSentence(body, '0:0', 16), 'The lamp still works!');
    assert.equal(originalSentence(body, '1:0', 12), 'She opened her bag.');
    const longLine = 'word '.repeat(700) + 'umbrella appeared.';
    const excerpt = originalSentence(longLine, '0:3', 3500);
    assert.ok(excerpt.includes('umbrella')); assert.ok(excerpt.length <= 2000);
  });
  await check('sentence deduplication updates a note and deleting its source preserves the memory', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      const experiences = new ExperienceRepository(database), articles = new ArticleRepository(database);
      const id = await articles.save('我的文章', 'She opened her bag.');
      const first = memory('a', id), again = memory('b', id); again.note = '更新的备注';
      await Promise.all([experiences.saveSentence(first), experiences.saveSentence(again)]);
      assert.equal((await experiences.sentences()).length, 1);
      assert.equal((await experiences.sentences())[0].note, '更新的备注');
      await experiences.savePosition(id, 0); await articles.remove(id);
      const saved = (await experiences.sentences())[0];
      assert.equal(saved.articleId, 0); assert.equal(saved.sentence, first.sentence);
      assert.equal((await experiences.reading(id)).updatedAt, 0);
    });
  });
  await check('reading position and recall writes do not erase each other', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      const experiences = new ExperienceRepository(database);
      const progress = new experience.ReadingProgress(); progress.articleId = -1;
      progress.answers = [1, -1]; progress.completed = false; progress.updatedAt = Date.now();
      await Promise.all([experiences.savePosition(-1, 2), experiences.saveReading(progress)]);
      let saved = await experiences.reading(-1); assert.equal(saved.paragraphIndex, 2); assert.deepEqual(saved.answers, [1, -1]);
      progress.answers = [1, 0]; progress.completed = true;
      await Promise.all([experiences.saveReading(progress), experiences.savePosition(-1, 1)]);
      saved = await experiences.reading(-1); assert.equal(saved.paragraphIndex, 1); assert.equal(saved.completed, true);
      assert.deepEqual(saved.answers, [1, 0]);
    });
  });
  await check('curated reading has stable IDs, 100–220 words, two valid questions and evidence-based ranking', async () => {
    const articles = curatedArticles(); assert.equal(articles.length, 18);
    assert.equal(new Set(articles.map(article => article.id)).size, 18);
    for (const article of articles) {
      const count = article.body.match(/[A-Za-z]+(?:'[A-Za-z]+)*/g).length;
      assert.ok(count >= 100 && count <= 220, `${article.title}: ${count}`);
      assert.equal(article.questions.length, 2);
      for (const question of article.questions) { assert.ok(question.options[question.answer]); assert.ok(question.explanation); }
    }
    await withIsolatedRepository(async (repo, store, database) => {
      ExperienceService.getInstance().initialize(database);
      const service = new ArticleService(); service.initialize({}, database);
      const before = await service.recommendations(); assert.ok(before.every(item => item.learnedCount === 0));
      await store.executeSql("INSERT INTO word(word,phonetic,meaning,example,translation) VALUES('umbrella','','伞','','')");
      const umbrella = await repo.findWordBySpelling('umbrella');
      await store.executeSql('INSERT INTO word_progress(word_id,review_count,strength) VALUES(?,1,12)', [umbrella.id]);
      const after = await service.recommendations(); assert.equal(after[0].article.id, -1); assert.equal(after[0].learnedCount, 1);
      const progress = new experience.ReadingProgress(); progress.articleId = -1; progress.completed = true;
      await ExperienceService.getInstance().saveReading(progress);
      assert.notEqual((await service.recommendations())[0].article.id, -1);
    });
  });
  await check('v4 backup roundtrip retains articles, original sentences, reading answers and per-word evidence', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const experiences = new ExperienceRepository(database), articles = new ArticleRepository(database);
      const articleId = await articles.save('我的文章', 'She opened her bag.');
      await experiences.saveSentence(memory('saved', articleId)); await experiences.saveAttempt(attempt('attempt'));
      const reading = new experience.ReadingProgress(); reading.articleId = -1; reading.answers = [1, 0]; reading.completed = true;
      await experiences.saveReading(reading);
      const backup = BackupService.parse(await service.exportData()); assert.equal(backup.version, 5);
      assert.equal(backup.sentences.length, 1); assert.equal(backup.practiceAttempts.length, 1);
      await experiences.removeSentence('saved'); await articles.remove(articleId);
      await service.restoreData(backup);
      assert.equal((await articles.get(articleId)).body, 'She opened her bag.');
      assert.equal((await experiences.sentences())[0].note, '我的记录');
      assert.deepEqual((await experiences.reading(-1)).answers, [1, 0]);
      assert.equal((await experiences.attempts()).length, 1);
      const before = wholeDatabase(store);
      for (const damage of [b => b.sentences[0].articleId = 99999, b => b.practiceAttempts[0].wordId = 99999,
        b => b.readingProgress[0].answers = [999], b => b.readingProgress[0].paragraphIndex = 999,
        b => b.sentences.push(b.sentences[0])]) {
        const broken = JSON.parse(JSON.stringify(backup)); damage(broken);
        await assert.rejects(service.restoreData(broken)); assert.deepEqual(wholeDatabase(store), before);
      }
      const legacy = JSON.parse(JSON.stringify(backup)); legacy.version = 3;
      delete legacy.articles; delete legacy.sentences; delete legacy.practiceAttempts; delete legacy.readingProgress;
      await service.restoreData(legacy);
      assert.equal((await experiences.sentences()).length, 1); assert.ok(await articles.get(articleId));
      assert.equal((await experiences.attempts()).length, 0);
    });
  });
  await check('failure while restoring experience data rolls the entire backup replacement back', async () => {
    await withIsolatedRepository(async (repo, store, database) => {
      const service = new LearningService(); await service.initialize(contextFor(catalog));
      const experiences = new ExperienceRepository(database); await experiences.saveAttempt(attempt('keep'));
      const backup = BackupService.parse(await service.exportData()); const before = wholeDatabase(store);
      const create = store.createTransaction.bind(store);
      store.createTransaction = async () => {
        const transaction = await create(); const execute = transaction.execute;
        transaction.execute = async (sql, args) => {
          if (sql.startsWith('INSERT INTO practice_attempt')) { throw new Error('injected experience restore failure'); }
          return execute(sql, args);
        }; return transaction;
      };
      await assert.rejects(service.restoreData(backup), /injected/);
      store.createTransaction = create; assert.deepEqual(wholeDatabase(store), before);
      assert.equal((await experiences.attempts()).length, 1);
    });
  });

  Date.now = actualNow;
  for (const store of stores.values()) store.db.close();
  fs.rmSync(testDirectory, { recursive: true, force: true });
  console.log(`${checks} domain and SQLite behavior checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
