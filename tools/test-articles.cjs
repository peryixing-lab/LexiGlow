/* Actual article pure functions, persistence and picker import with bounded native mocks. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const sources = path.resolve(__dirname, '../entry/src/main/ets');
let checks = 0;
const check = async (label, run) => { await run(); checks++; console.log(`PASS ${label}`); };
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const pickerState = { uris: [], bytes: new Uint8Array(), offset: 0, closed: 0, reads: 0, options: undefined, shortRead: false };
const lookupCalls = [];
const dictionary = new Map();
const originalLoad = Module._load;
Module._load = function(name, parent, isMain) {
  if (name === '@kit.ArkData' || name === '@kit.AbilityKit') return {};
  if (name === '@kit.ArkTS') return { util: { TextDecoder: {
    create: (encoding, options) => ({ decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes) })
  } } };
  if (name === '@kit.CoreFileKit') return {
    picker: { DocumentSelectOptions: class {}, DocumentViewPicker: class {
      async select(options) { pickerState.options = options; return pickerState.uris; }
    } },
    fileIo: { OpenMode: { READ_ONLY: 0 },
      async open() { pickerState.offset = 0; return { fd: 7 }; },
      async stat() { return { size: pickerState.bytes.length }; },
      async read(_fd, chunk) {
        pickerState.reads++;
        if (pickerState.shortRead) return 0;
        const count = Math.min(chunk.byteLength, 137, pickerState.bytes.length - pickerState.offset);
        new Uint8Array(chunk).set(pickerState.bytes.subarray(pickerState.offset, pickerState.offset + count));
        pickerState.offset += count; return count;
      },
      async close() { pickerState.closed++; }
    }
  };
  if (name === './DocxReader' && parent.filename.endsWith('ArticleImportService.ets')) {
    return { DocxReader: { async read() { return 'An entire article.\nSecond paragraph, with punctuation!'; } } };
  }
  if (name === './LearningService' && parent.filename.endsWith('ArticleService.ets')) {
    return { LearningService: { getInstance: () => ({ async findWordBySpelling(word) {
      lookupCalls.push(word); return dictionary.get(word);
    } }) } };
  }
  return originalLoad.call(this, name, parent, isMain);
};
const tokenizer = require(path.join(sources, 'utils/ArticleTokenizer.ets'));
const { ArticleRepository } = require(path.join(sources, 'repository/ArticleRepository.ets'));
const { ArticleService } = require(path.join(sources, 'service/ArticleService.ets'));
const { ArticleImportService } = require(path.join(sources, 'service/ArticleImportService.ets'));
class Rows {
  constructor(items) { this.items = items; this.index = -1; this.columns = Object.keys(items[0] || {}); }
  goToFirstRow() { this.index = 0; return this.items.length > 0; }
  goToNextRow() { return ++this.index < this.items.length; }
  getString(index) { return String(this.items[this.index][this.columns[index]] || ''); }
  getLong(index) { return Number(this.items[this.index][this.columns[index]] || 0); }
  close() {}
}
const withRepository = async run => {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('CREATE TABLE article(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,body TEXT NOT NULL,created_at INTEGER NOT NULL); CREATE TABLE word(id INTEGER PRIMARY KEY,word TEXT COLLATE NOCASE UNIQUE); CREATE TABLE word_progress(word_id INTEGER PRIMARY KEY,strength INTEGER,review_count INTEGER DEFAULT 0)');
  sqlite.exec('CREATE TABLE sentence_memory(id TEXT PRIMARY KEY,word_id INTEGER,article_id INTEGER,paragraph_key TEXT); CREATE TABLE reading_progress(article_id INTEGER PRIMARY KEY)');
  let writes = Promise.resolve(); const queries = [];
  const connection = {
    async querySql(sql, args = []) { queries.push(sql); return new Rows(sqlite.prepare(sql).all(...args)); },
    async executeSql(sql, args = []) { sqlite.prepare(sql).run(...args); }
  };
  const database = {
    getStore: () => connection,
    transaction(operation) {
      const task = writes.then(async () => {
        sqlite.exec('BEGIN');
        try { await operation(connection); sqlite.exec('COMMIT'); }
        catch (error) { sqlite.exec('ROLLBACK'); throw error; }
      });
      writes = task.then(() => {}, () => {}); return task;
    }
  };
  try { await run(new ArticleRepository(database), sqlite, queries, database); }
  finally { sqlite.close(); }
};
const chooseFile = (filename, body) => {
  pickerState.uris = [filename]; pickerState.bytes = new TextEncoder().encode(body);
  pickerState.closed = 0; pickerState.reads = 0; pickerState.shortRead = false;
};
(async () => {
  await check('English token targets preserve punctuation, whitespace and Chinese text', () => {
    const text = "Hello,\tworld! Mary's cat—中文 don't run.\n";
    const tokens = tokenizer.tokenizeArticleText(text);
    assert.equal(tokens.map(token => token.text).join(''), text);
    assert.deepEqual(tokens.filter(token => token.spelling).map(token => token.spelling),
      ['hello', 'world', "mary's", 'cat', "don't", 'run']);
    assert.equal(new Set(tokens.map(token => token.start)).size, tokens.length);
  });
  await check('Candidate order preserves exact spellings and handles regular suffix changes', () => {
    for (const [form, expected] of [['cats','cat'], ['boxes','box'], ['studies','study'], ['studied','study'],
      ['danced','dance'], ['running','run'], ['making','make'], ['happily','happy'], ["Mary’s",'mary']]) {
      const candidates = tokenizer.articleWordCandidates(form);
      assert.equal(candidates[0], form.toLowerCase().replace(/’/g, "'"));
      assert(candidates.includes(expected), `${form}: ${expected}`);
      assert.equal(new Set(candidates).size, candidates.length);
    }
    assert(!tokenizer.articleWordCandidates('went').includes('go'));
    assert.deepEqual(tokenizer.articleWordCandidates('猫'), []);
  });
  await check('Article validation rejects empty, binary and 60,001-character bodies', () => {
    assert.equal(tokenizer.normalizeArticleBody('\uFEFFHello\r\nWorld\r!'), 'Hello\nWorld\n!');
    assert.equal(tokenizer.normalizeArticleBody('a'.repeat(60000)).length, 60000);
    assert.throws(() => tokenizer.normalizeArticleBody('a'.repeat(60001)), /60,000/);
    assert.throws(() => tokenizer.normalizeArticleBody(' \t\n '), /正文/);
    assert.throws(() => tokenizer.normalizeArticleBody('Hello\u0000World'), /字符/);
  });
  await check('60,000-character single-paragraph articles remain bounded without losing characters', () => {
    for (const text of ['hello '.repeat(10000), 'a '.repeat(30000), 'a'.repeat(60000), '中'.repeat(60000)]) {
      const paragraphs = tokenizer.articleParagraphs(text);
      assert.equal(paragraphs.flatMap(part => part.tokens).map(token => token.text).join(''), text);
      assert(paragraphs.length > 1);
      assert.equal(new Set(paragraphs.map(part => part.key)).size, paragraphs.length);
      assert(paragraphs.every(part => part.tokens.length <= 160));
      assert(paragraphs.every(part => part.tokens.reduce((count, token) => count + token.text.length, 0) <= 1200));
      if (text === 'a'.repeat(60000)) assert(paragraphs.every(part => part.tokens.every(token => !token.spelling)));
    }
  });
  await check('Persistent article import, list, delete preserve dictionary data and rollback rejected imports', () =>
    withRepository(async (repo, sqlite) => {
      sqlite.exec("INSERT INTO word VALUES(1,'hello'); INSERT INTO word_progress(word_id,strength) VALUES(1,80)");
      const id = await repo.save(' title ', ' Hello\r\nWorld ', 100);
      assert.equal((await repo.get(id)).body, 'Hello\nWorld');
      assert.equal((await repo.list())[0].title, 'title');
      await assert.rejects(repo.save('large', 'x'.repeat(60001)), /60,000/);
      assert.equal((await repo.list()).length, 1);
      await repo.remove(id); assert.equal((await repo.list()).length, 0);
      assert.equal((await repo.get(id)), undefined);
      assert.equal(sqlite.prepare('SELECT strength FROM word_progress WHERE word_id=1').get().strength, 80);
    }));
  await check('Concurrent imports cannot exceed 20 saved articles; deleting frees a slot', () =>
    withRepository(async repo => {
      for (let i = 0; i < 19; i++) await repo.save(`article ${i}`, 'Hello world.', i);
      const results = await Promise.allSettled(Array.from({ length: 8 }, (_, i) => repo.save(`race ${i}`, 'Hi.')));
      assert.equal(results.filter(item => item.status === 'fulfilled').length, 1);
      assert.equal((await repo.list()).length, 20);
      await repo.remove((await repo.list())[0].id);
      await repo.save('replacement', 'Hi.'); assert.equal((await repo.list()).length, 20);
    }));
  await check('One paragraph query resolves exact spelling before mastered inflection candidates', () =>
    withRepository(async (repo, sqlite, queries) => {
      sqlite.exec("INSERT INTO word VALUES(1,'run'),(2,'running'),(3,'dance'),(4,'box'),(5,'go'); INSERT INTO word_progress(word_id,strength) VALUES(1,90),(2,10),(3,82),(4,75),(5,100)");
      const strengths = await repo.paragraphStrengths(['running', 'danced', 'boxes', 'went', 'RUNNING']);
      assert.equal(strengths.get('running'), 10); assert.equal(strengths.get('danced'), 82);
      assert.equal(strengths.get('boxes'), 75); assert.equal(strengths.get('went'), undefined);
      assert.equal(queries.length, 1); assert(queries[0].includes(' IN ('));
      await repo.paragraphStrengths([]); assert.equal(queries.length, 1);
    }));
  await check('Lookup is exact first, local and accepts regular candidates without irregular guesses', async () => {
    dictionary.clear(); lookupCalls.length = 0;
    dictionary.set('running', { id: 1, word: 'running' }); dictionary.set('run', { id: 2, word: 'run' });
    assert.equal((await ArticleService.getInstance().lookup('running')).id, 1);
    assert.deepEqual(lookupCalls, ['running']);
    dictionary.delete('running'); lookupCalls.length = 0;
    assert.equal((await ArticleService.getInstance().lookup('running')).id, 2);
    assert.equal(lookupCalls.at(-1), 'run');
    assert.equal(await ArticleService.getInstance().lookup('went'), undefined);
  });
  await check('Canceling article picker keeps the current draft and never opens a file', async () => {
    pickerState.uris = []; pickerState.reads = 0; pickerState.closed = 0;
    assert.equal(await ArticleImportService.importFile({}), undefined);
    assert.equal(pickerState.reads, 0); assert.equal(pickerState.closed, 0);
    assert.deepEqual(pickerState.options.fileSuffixFilters, ['文章 TXT / DOCX|.txt,.docx']);
  });
  await check('TXT short reads are completed; DOCX preserves prose rather than importing words', async () => {
    const text = 'Hello world.\r\n'.repeat(300);
    chooseFile('file:///Hello.txt', text);
    const imported = await ArticleImportService.importFile({});
    assert.equal(imported.title, 'Hello'); assert.equal(imported.body, text.replace(/\r\n/g, '\n').trim());
    assert(pickerState.reads > 1); assert.equal(pickerState.closed, 1);
    chooseFile('file:///Essay.docx', 'PKmock');
    assert.equal((await ArticleImportService.importFile({})).body, 'An entire article.\nSecond paragraph, with punctuation!');
    assert.equal(pickerState.closed, 1);
  });
  await check('Invalid UTF-8, oversized contents and incomplete reads fail and release file handles', async () => {
    chooseFile('file:///Bad.txt', 'Hello'); pickerState.bytes = Uint8Array.from([0xff,0xff]);
    await assert.rejects(ArticleImportService.importFile({}), /UTF-8/); assert.equal(pickerState.closed, 1);
    chooseFile('file:///TooLong.txt', 'a'.repeat(60001));
    await assert.rejects(ArticleImportService.importFile({}), /60,000/); assert.equal(pickerState.closed, 1);
    chooseFile('file:///Short.txt', 'Hello'); pickerState.shortRead = true;
    await assert.rejects(ArticleImportService.importFile({}), /完整/); assert.equal(pickerState.closed, 1);
  });
  console.log(`Verified ${checks} article checks.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
