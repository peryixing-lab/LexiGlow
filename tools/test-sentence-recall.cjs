/* Runs the actual sentence selection/scheduling and repository against SQLite. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const root = path.resolve(__dirname, '..', 'entry/src/main/ets');
process.env.TZ = 'Asia/Shanghai';
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.ArkData' || name === '@kit.AbilityKit') return {};
  if (name.endsWith('/PendingWordService')) return { PendingWordService: { exportInside: async () => {}, restoreInside: async () => {} } };
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const { SentenceMemory, SentenceRecallAttempt } = require(path.join(root, 'model/ExperienceModels.ets'));
const { DataExport } = require(path.join(root, 'model/AppModels.ets'));
const { originalSentenceSelection, sentenceTargetChoices, hasSentenceTarget, maskedMemorySentence,
  sentenceRecallMatches, recommendedSentenceMemories } = require(path.join(root, 'utils/SentenceRecallUtils.ets'));
const { ExperienceRepository } = require(path.join(root, 'repository/ExperienceRepository.ets'));
const { ExperienceService, SentenceRecallJournal } = require(path.join(root, 'service/ExperienceService.ets'));
let checks = 0;
const check = async (name, action) => { await action(); checks++; console.log(`PASS ${name}`); };
const at = (day, hour = 12) => new Date(2026, 10, day, hour).getTime();
const memory = (id = 's1', createdAt = at(5)) => Object.assign(new SentenceMemory(), {
  id, wordId: 1, articleId: -1, articleTitle: '源文章', paragraphKey: '0:0', sentence: 'She found a key and found a door.',
  targetText: 'found', targetStart: 4, createdAt
});
const attempt = (id, sentenceId, correct, hinted, recordedAt) => Object.assign(new SentenceRecallAttempt(), {
  id, sentenceId, correct, hinted, durationMs: 1200, recordedAt
});
class RecallRows {
  constructor(rows) { this.rows = rows; this.index = -1; this.columns = Object.keys(rows[0] || {}); }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { this.index++; return this.index < this.rows.length; }
  getLong(index) { return Number(this.rows[this.index][this.columns[index]]); }
  getString(index) { return String(this.rows[this.index][this.columns[index]]); }
  close() {}
}
const db = new DatabaseSync(':memory:');
db.exec(`PRAGMA foreign_keys=ON;
CREATE TABLE word(id INTEGER PRIMARY KEY); INSERT INTO word VALUES(1);
CREATE TABLE article(id INTEGER PRIMARY KEY,title TEXT,body TEXT,created_at INTEGER);
CREATE TABLE practice_attempt(id TEXT PRIMARY KEY,word_id INTEGER,mode TEXT,correct INTEGER,hinted INTEGER,duration_ms INTEGER,recorded_at INTEGER);
CREATE TABLE reading_progress(article_id INTEGER PRIMARY KEY,paragraph_index INTEGER,completed INTEGER,answers TEXT,updated_at INTEGER);
CREATE TABLE sentence_memory(id TEXT PRIMARY KEY,word_id INTEGER REFERENCES word(id),article_id INTEGER,article_title TEXT,paragraph_key TEXT,sentence TEXT,note TEXT,created_at INTEGER,target_text TEXT DEFAULT '',target_start INTEGER DEFAULT -1,recall_enabled INTEGER DEFAULT 1);
CREATE TABLE sentence_recall_attempt(id TEXT PRIMARY KEY,sentence_id TEXT NOT NULL REFERENCES sentence_memory(id) ON DELETE CASCADE,correct INTEGER,hinted INTEGER,duration_ms INTEGER,recorded_at INTEGER);`);
const store = {
  async executeSql(sql, args = []) { db.prepare(sql).run(...args); },
  async querySql(sql, args = []) { return new RecallRows(db.prepare(sql).all(...args)); }
};
const database = { getStore: () => store, async transaction(action) {
  db.exec('BEGIN'); try { await action(store); db.exec('COMMIT'); } catch (error) { db.exec('ROLLBACK'); throw error; }
} };
const repository = new ExperienceRepository(database);
const drain = async () => { for (let i = 0; i < 6; i++) await new Promise(resolve => setImmediate(resolve)); };
const deferred = () => {
  let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve };
};
function recallPage(service = {}) {
  const source = fs.readFileSync(path.join(root, 'pages/SentenceRecallPage.ets'), 'utf8');
  let logic = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
  logic = logic.replace(/^import .*;\s*$/gm, '').replace(/@ComponentV2\s*/g, '')
    .replace(/@(Local|Param|Event)\s+/g, '').replace(/\s*@Monitor\([^\n]*\)\s*/g, '\n  ')
    .replace(/export struct /, 'export class ');
  const output = ts.transpileModule(logic, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText;
  const stubs = { exports: {}, SentenceMemory, SentenceRecallJournal, hasSentenceTarget, maskedMemorySentence, sentenceRecallMatches,
    ExperienceService: { getInstance: () => Object.assign({ sentences: async () => [], recallRecommendations: async () => [] }, service) },
    LearningService: { getInstance: () => ({ getWord: async () => ({meaning: '找到'}) }) } };
  const names = Object.keys(stubs); new Function(...names, output)(...names.map(name => stubs[name]));
  const page = new stubs.exports.SentenceRecallPage();
  page.getUIContext = () => ({getHostContext: () => ({eventHub: {on() {}, off() {}}}), getFocusController: () => ({clearFocus() {}})});
  return page;
}
(async () => {
  await check('clicked second occurrence keeps case and its exact UTF-16 position', () => {
    const body = '  She found a key and found a door. Next sentence.';
    const selected = originalSentenceSelection(body, '0:0', body.lastIndexOf('found'));
    assert.equal(selected.sentence, 'She found a key and found a door.');
    assert.equal(selected.targetStart, 20); assert.equal(selected.targetText, 'found');
    const unicode = '😀 She found a key.';
    assert.equal(originalSentenceSelection(unicode, '0:0', unicode.indexOf('found')).targetStart, unicode.indexOf('found'));
  });
  await check('long sentence clips around clicked token without losing the selected word', () => {
    const text = 'prefix '.repeat(400) + 'umbrellas ' + 'suffix '.repeat(400) + '.';
    const selected = originalSentenceSelection(text, '0:0', text.indexOf('umbrellas'));
    assert.ok(selected.sentence.length <= 2000); assert.ok(selected.sentence.startsWith('…'));
    assert.equal(selected.sentence.slice(selected.targetStart, selected.targetStart + selected.targetText.length), 'umbrellas');
  });
  await check('legacy, partial-token and invalid offsets never silently become practice targets', () => {
    const old = memory(); old.targetStart = -1; old.targetText = '';
    assert.equal(hasSentenceTarget(old), false);
    const partial = memory(); partial.targetText = 'ound'; partial.targetStart = 5;
    assert.equal(hasSentenceTarget(partial), false);
    const wrong = memory(); wrong.targetStart = 6;
    assert.equal(hasSentenceTarget(wrong), false);
    assert.equal(sentenceTargetChoices("He's found it.")[0].text, "He's");
  });
  await check('masking also hides repeated answer forms without hiding unrelated fragments', () => {
    assert.equal(maskedMemorySentence(memory()), 'She _____ a key and _____ a door.');
    assert.equal(sentenceRecallMatches('found', ' FOUND '), true);
    assert.equal(sentenceRecallMatches('found', 'find'), false);
    assert.equal(sentenceRecallMatches("He's", 'He’s'), true);
  });
  await check('recommendations respect dates, pauses and all-day five-sentence budget', () => {
    const memories = Array.from({length: 12}, (_, i) => memory(`s${i}`));
    assert.equal(recommendedSentenceMemories(memories, [], at(5, 23)).length, 0);
    assert.equal(recommendedSentenceMemories(memories, [], at(6, 0)).length, 5);
    memories[0].recallEnabled = false; assert.ok(recommendedSentenceMemories(memories, [], at(6)).every(x => x.id !== 's0'));
    const today = [attempt('a1', 's1', false, false, at(6, 9)), attempt('a2', 's2', true, false, at(6, 9))];
    assert.equal(recommendedSentenceMemories(memories, today, at(6)).length, 3);
    assert.equal(recommendedSentenceMemories(memories, Array.from({length: 5}, (_, i) => attempt(`a${i}`, `s${i}`, true, false, at(6, 9))), at(6)).length, 0);
  });
  await check('wrong, hinted success and independent success have separate cross-day waits', () => {
    const source = memory();
    assert.equal(recommendedSentenceMemories([source], [attempt('a', source.id, false, false, at(6))], at(7)).length, 1);
    assert.equal(recommendedSentenceMemories([source], [attempt('a', source.id, true, true, at(6))], at(8)).length, 0);
    assert.equal(recommendedSentenceMemories([source], [attempt('a', source.id, true, true, at(6))], at(9)).length, 1);
    assert.equal(recommendedSentenceMemories([source], [attempt('a', source.id, true, false, at(6))], at(12)).length, 0);
    assert.equal(recommendedSentenceMemories([source], [attempt('a', source.id, true, false, at(6))], at(13)).length, 1);
  });
  await check('repository persists exact targets and same-source recollection remains one item', async () => {
    const source = memory(); await repository.saveSentence(source);
    const duplicate = memory('duplicate'); duplicate.note = '更新备注'; duplicate.targetStart = 20;
    await repository.saveSentence(duplicate);
    const saved = await repository.sentences(); assert.equal(saved.length, 1); assert.equal(duplicate.id, source.id);
    assert.equal(saved[0].targetStart, 20); assert.equal(saved[0].note, '更新备注');
  });
  await check('attempt retries are idempotent and target changes reject stale writes', async () => {
    const item = attempt('a1', 's1', true, false, at(6));
    await repository.saveRecallAttempt(item, 'found', 20); await repository.saveRecallAttempt(item, 'found', 20);
    assert.equal((await repository.recallAttempts()).length, 1);
    await assert.rejects(repository.saveRecallAttempt(attempt('a2', 's1', true, false, at(6)), 'found', 4), /目标已改变/);
    const changed = (await repository.sentences())[0]; changed.targetStart = 4; await repository.saveSentence(changed);
    assert.equal((await repository.recallAttempts()).length, 0);
  });
  await check('backup export/restore keeps hints and target offsets; v4 clears new attempts safely', async () => {
    await repository.saveRecallAttempt(attempt('a3', 's1', true, true, at(7)), 'found', 4);
    const backup = new DataExport(); backup.version = 5; await repository.exportInto(backup);
    assert.equal(backup.sentenceRecallAttempts[0].hinted, true); assert.equal(backup.sentences[0].targetStart, 4);
    await database.transaction(async transaction => ExperienceRepository.restore(transaction, backup, new Map([[1, 1]])));
    assert.equal((await repository.recallAttempts())[0].hinted, true);
    const v4 = new DataExport(); v4.version = 4; v4.sentences = backup.sentences.map(source => {
      const old = {...source}; delete old.targetText; delete old.targetStart; delete old.recallEnabled; return old;
    });
    await database.transaction(async transaction => ExperienceRepository.restore(transaction, v4, new Map([[1, 1]])));
    assert.equal((await repository.recallAttempts()).length, 0); assert.equal((await repository.sentences())[0].targetStart, -1);
  });
  await check('deleted sources preserve their sentences; deleting a sentence cascades its attempts', async () => {
    const source = memory('deleted-source'); source.articleId = 999;
    await repository.saveSentence(source);
    assert.equal((await repository.sentences()).find(x => x.id === source.id).articleId, 0);
    await repository.saveRecallAttempt(attempt('a4', source.id, false, true, at(7)), 'found', 4);
    await repository.removeSentence(source.id);
    assert.equal((await repository.recallAttempts()).length, 0);
  });
  await check('journal freezes first answer and duration across a failed write/retry', async () => {
    const service = ExperienceService.getInstance(); const original = service.saveRecallAttempt;
    const seen = []; service.saveRecallAttempt = async row => { seen.push({...row}); if (seen.length === 1) throw Error('disk unavailable'); };
    try {
      const journal = new SentenceRecallJournal(); journal.beginQuestion(); journal.pause();
      await assert.rejects(journal.record('s1', true, true, 'found', 4));
      await journal.record('changed', false, false, 'different', 0);
      assert.deepEqual(seen[0], seen[1]);
    } finally { service.saveRecallAttempt = original; }
  });
  await check('v1-v3 restores retain local sentences and clear incompatible recall attempts', async () => {
    for (const version of [1, 2, 3]) {
      const source = memory('local-old'); await repository.saveSentence(source);
      await repository.saveRecallAttempt(attempt(`legacy-${version}`, source.id, true, false, at(7)), 'found', 4);
      const before = (await repository.sentences()).map(row => row.id).sort();
      const backup = new DataExport(); backup.version = version;
      await database.transaction(async transaction => ExperienceRepository.restore(transaction, backup, new Map([[1, 1]])));
      assert.deepEqual((await repository.sentences()).map(row => row.id).sort(), before);
      assert.equal((await repository.recallAttempts()).length, 0);
    }
  });
  await check('actual recall page pauses its journal while covered, invisible or in background', () => {
    const page = recallPage(); const calls = [];
    page.journal = { resume: () => calls.push('resume'), pause: () => calls.push('pause') };
    page.active = true; page.loading = false; page.updateClock(); assert.equal(calls.at(-1), 'resume');
    page.visible = false; page.visibilityChanged(); assert.equal(calls.at(-1), 'pause');
    page.visible = true; page.visibilityListener(false); assert.equal(calls.at(-1), 'pause');
    page.visibilityListener(true); assert.equal(calls.at(-1), 'resume');
    page.areaVisible = false; page.updateClock(); assert.equal(calls.at(-1), 'pause');
    page.aboutToDisappear(); assert.equal(calls.at(-1), 'pause');
  });
  await check('actual recall page ignores a recommendation response after leaving', async () => {
    const gate = deferred(); const page = recallPage({recallRecommendations: () => gate.promise});
    page.active = true; const loading = page.load(); page.aboutToDisappear(); gate.resolve([memory()]);
    await loading; assert.equal(page.memories.length, 0); assert.equal(page.active, false);
  });
  await check('actual recall page blocks next after failed save and retries the same immutable answer', async () => {
    const service = ExperienceService.getInstance(); const original = service.saveRecallAttempt; const saved = [];
    service.saveRecallAttempt = async row => { saved.push({...row}); if (saved.length === 1) throw Error('disk unavailable'); };
    try {
      const page = recallPage(); page.active = true; page.loading = false; page.memories = [memory('q1'), memory('q2')];
      page.answer = 'found'; page.submit(); await drain(); assert.ok(page.saveError); assert.equal(page.independentCorrect, 1);
      await page.next(); assert.equal(page.index, 0);
      await page.saveEvidence(); assert.equal(page.saveError, ''); assert.deepEqual(saved[0], saved[1]);
      await page.next(); assert.equal(page.index, 1); assert.equal(page.answered, false);
      page.aboutToDisappear();
    } finally { service.saveRecallAttempt = original; }
  });
  console.log(`${checks} sentence recall checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => { db.close(); });
