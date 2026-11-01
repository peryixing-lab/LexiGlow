/* Runs the actual settings store with Preferences writes persisted only by flush(). */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');

let persisted = undefined;
let flushes = 0;
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.AbilityKit') return {};
  if (name === '@kit.ArkData') return { preferences: { async getPreferences() {
    const values = new Map(persisted === undefined ? [] : [['settings', persisted]]);
    return {
      async get(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
      async put(key, value) { values.set(key, value); },
      async flush() { persisted = values.get('settings'); flushes++; }
    };
  } } };
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = function(module, filename) {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const source = path.resolve(__dirname, '../entry/src/main/ets');
const { UserSettings } = require(path.join(source, 'model/AppModels.ets'));
const { UserSettingsStore } = require(path.join(source, 'store/UserSettingsStore.ets'));
const open = async database => {
  const store = new UserSettingsStore(); await store.initialize({}, database); return store;
};
const withDatabase = async action => {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('CREATE TABLE app_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
  const database = {
    writes: 0, fail: false,
    getStore: () => ({ async querySql(sql) {
      const row = sqlite.prepare(sql).get();
      return { goToFirstRow: () => !!row, getString: () => row.value, close() {} };
    } }),
    async transaction(operation) {
      sqlite.exec('BEGIN');
      try {
        await operation({ async executeSql(sql, args) { sqlite.prepare(sql).run(...args); } });
        if (database.fail) throw new Error('simulated settings commit failure');
        sqlite.exec('COMMIT'); database.writes++;
      } catch (error) { sqlite.exec('ROLLBACK'); throw error; }
    }
  };
  try { await action(database, sqlite); } finally { sqlite.close(); }
};
const withoutPronunciation = settings => {
  const result = { ...settings };
  delete result.autoPronounce; delete result.autoPronounceConfigured;
  return result;
};
let checks = 0;
const check = async (label, action) => {
  persisted = undefined; flushes = 0;
  await action(); checks++; console.log(`PASS ${label}`);
};
(async () => {
  await check('fresh installs remain silent after onboarding saves and restart', async () => {
    const store = await open();
    assert.equal(store.getSettings().autoPronounce, false);
    const next = store.getSettings(); next.onboarded = true; await store.save(next);
    assert.equal((await open()).getSettings().autoPronounce, false);
  });
  await check('legacy default-on settings migrate once and preserve every other preference', async () => {
    const legacy = Object.assign(new UserSettings(), { onboarded: true, currentBookId: 'cet6',
      dailyNewTarget: 7, autoPronounce: true, reminderEnabled: true, reminderHour: 8,
      reminderMinute: 35, themeMode: 'dark', learningMode: 'exam', foundation: 'advanced',
      examDate: '2026-12-19', spellingRecall: true, hapticsEnabled: false });
    delete legacy.autoPronounceConfigured;
    persisted = JSON.stringify(legacy);
    const store = await open();
    assert.equal(store.getSettings().autoPronounce, false);
    assert.deepEqual(withoutPronunciation(store.getSettings()), withoutPronunciation(legacy));
    assert.equal(JSON.parse(persisted).autoPronounce, false);
    assert.equal(JSON.parse(persisted).autoPronounceConfigured, false);
    assert.equal(flushes, 1);
    assert.deepEqual((await open()).getSettings(), store.getSettings());
    assert.equal(flushes, 1, 'reopening migrated preferences must not rewrite them');
  });
  await check('an explicit enable survives restart and unrelated preference changes', async () => {
    let store = await open();
    const enabled = store.getSettings();
    enabled.autoPronounce = true; enabled.autoPronounceConfigured = true;
    await store.save(enabled);
    store = await open();
    assert.equal(store.getSettings().autoPronounce, true);
    const changed = store.getSettings(); changed.themeMode = 'dark'; changed.dailyNewTarget = 9;
    await store.save(changed);
    const reopened = (await open()).getSettings();
    assert.equal(reopened.autoPronounce, true);
    assert.equal(reopened.autoPronounceConfigured, true);
    assert.equal(reopened.themeMode, 'dark'); assert.equal(reopened.dailyNewTarget, 9);
  });
  await check('an explicit disable remains silent across later launches', async () => {
    let store = await open();
    const enabled = store.getSettings();
    enabled.autoPronounce = true; enabled.autoPronounceConfigured = true; await store.save(enabled);
    store = await open();
    const disabled = store.getSettings(); disabled.autoPronounce = false; await store.save(disabled);
    assert.equal((await open()).getSettings().autoPronounce, false);
    assert.equal(JSON.parse(persisted).autoPronounceConfigured, true);
  });
  await check('Preferences migrate once into SQLite and explicit pronunciation and local reminder choices survive restart', async () => {
    await withDatabase(async (database, sqlite) => {
      const settings = Object.assign(new UserSettings(), { currentBookId: 'cet6', dailyNewTarget: 12,
        autoPronounce: true, autoPronounceConfigured: true, reminderEnabled: true,
        reminderHour: 6, reminderMinute: 40, themeMode: 'dark' });
      persisted = JSON.stringify(settings);
      const store = await open(database);
      assert.deepEqual(store.getSettings(), settings);
      assert.equal(database.writes, 1);
      assert.deepEqual(JSON.parse(sqlite.prepare("SELECT value FROM app_meta WHERE key='user_settings'").get().value),
        JSON.parse(JSON.stringify(settings)));
      persisted = JSON.stringify(new UserSettings()); // Stale Preferences must not override the database.
      assert.deepEqual((await open(database)).getSettings(), settings);
      assert.equal(database.writes, 1);
    });
  });
  await check('legacy default-on Preferences migrate silently into SQLite without changing local notification settings', async () => {
    await withDatabase(async (database) => {
      const legacy = Object.assign(new UserSettings(), { autoPronounce: true,
        reminderEnabled: true, reminderHour: 23, reminderMinute: 55 });
      delete legacy.autoPronounceConfigured;
      persisted = JSON.stringify(legacy);
      const migrated = (await open(database)).getSettings();
      assert.equal(migrated.autoPronounce, false); assert.equal(migrated.autoPronounceConfigured, false);
      assert.deepEqual(withoutPronunciation(migrated), withoutPronunciation(legacy));
      assert.deepEqual((await open(database)).getSettings(), migrated);
      assert.equal(database.writes, 1);
    });
  });
  await check('committed restored settings take precedence over previous Preferences on the next launch', async () => {
    await withDatabase(async (database) => {
      persisted = JSON.stringify(new UserSettings());
      const store = await open(database);
      const restored = Object.assign(store.getSettings(), { currentBookId: 'custom_restored',
        dailyNewTarget: 8, autoPronounce: true, autoPronounceConfigured: true,
        reminderEnabled: false, reminderHour: 20, reminderMinute: 5 });
      await database.transaction(tx => tx.executeSql(
        "INSERT OR REPLACE INTO app_meta(key,value) VALUES('user_settings',?)", [JSON.stringify(restored)]));
      store.acceptCommitted(restored);
      assert.deepEqual(store.getSettings(), restored);
      assert.deepEqual((await open(database)).getSettings(), restored);
    });
  });
  await check('a failed SQLite settings commit preserves persisted and in-memory choices and a later save succeeds', async () => {
    await withDatabase(async (database) => {
      const store = await open(database); const before = store.getSettings();
      const changed = Object.assign(store.getSettings(), { autoPronounce: true, autoPronounceConfigured: true,
        reminderEnabled: true, reminderHour: 9, reminderMinute: 10 });
      database.fail = true;
      await assert.rejects(store.save(changed), /simulated settings commit failure/);
      assert.deepEqual(store.getSettings(), before);
      assert.deepEqual((await open(database)).getSettings(), before);
      database.fail = false; await store.save(changed);
      assert.deepEqual((await open(database)).getSettings(), changed);
    });
  });
  console.log(`${checks} settings checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
