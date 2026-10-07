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
const contextFor = catalog => ({ resourceManager: { async getRawFileContent() {
  return new TextEncoder().encode(JSON.stringify(catalog));
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
    assert.equal(adjustedNewTarget(20, 61), 6); assert.equal(adjustedNewTarget(20, 100), 0);
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
  await check('learned date pagination retrieves more than 80 words without gaps or repeats and challenge sampling caps at 50', async () => {
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
      for (const limit of [1, 10, 500]) {
        const challenge = await isolatedRepo.getChallengeWords(limit, 'cet6');
        assert.equal(challenge.length, Math.min(limit, 50));
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
