/* Verify the actual offline ArkTS matcher and challenge session, without device or RDB mocks. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const root = path.resolve(__dirname, '..');
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const { Word } = require(path.join(root, 'entry/src/main/ets/model/AppModels.ets'));
const { meaningAnswers, matchesMeaning } = require(path.join(root, 'entry/src/main/ets/utils/MeaningMatcher.ets'));
const { ChallengeService } = require(path.join(root, 'entry/src/main/ets/service/ChallengeService.ets'));
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/wordbooks/catalog.json')));
const catalogWords = catalog.books.flatMap(book => book.words);
const meaningOf = name => {
  const entry = catalogWords.find(word => word.word === name);
  assert.ok(entry, `The real catalog includes ${name}`);
  return entry.meaning;
};
let checks = 0;
const check = (label, action) => { action(); checks++; console.log(`PASS ${label}`); };
check('one complete sense from a real multi-sense entry passes', () => {
  assert.ok(matchesMeaning('状态', meaningOf('state')));
  assert.ok(matchesMeaning('州', meaningOf('state')));
  assert.ok(matchesMeaning('抛弃', meaningOf('abandon')));
  assert.ok(matchesMeaning('隔热', meaningOf('insulate')));
});
check('substrings and prose containing the right answer fail', () => {
  for (const answer of ['放', '弃', '我认为这可能是放弃但其实不知道', '我写错了，应该是放弃吧', '放弃错误内容']) {
    assert.equal(matchesMeaning(answer, meaningOf('abandon')), false, answer);
  }
  assert.equal(matchesMeaning('态', meaningOf('state')), false);
});
check('delimited alternatives accept one complete matching sense', () => {
  for (const answer of ['放弃；抛弃', '抛弃、离开', '放弃\n离开', '离开, 抛弃', '离开/抛弃']) {
    assert.ok(matchesMeaning(answer, meaningOf('abandon')), answer);
  }
});
check('parts of speech, numbers, whitespace, and terminal punctuation are normalized', () => {
  const meaning = '1. n. 州；2. vt. 声明\n① adj. 严肃的、认真的';
  assert.deepEqual(meaningAnswers(meaning), ['州', '声明', '严肃的', '认真的']);
  assert.ok(matchesMeaning(' 声 明。 ', meaning));
  assert.ok(matchesMeaning('严肃', meaning));
  assert.ok(matchesMeaning('认真的', meaning));
  assert.deepEqual(meaningAnswers('n. 挑战 v. 向……挑战'), ['挑战', '向……挑战']);
});
check('annotations with separators do not create false senses', () => {
  assert.deepEqual(meaningAnswers('n. 职位（学校、公司）, 职责(工作,生活)；[医] 鞭毛'), ['职位', '职责', '鞭毛']);
  assert.ok(matchesMeaning('院长', meaningOf('president')));
  assert.equal(matchesMeaning('学院', meaningOf('president')), false);
});
check('inline lexical parentheses and optional causative words retain complete meanings', () => {
  assert.ok(matchesMeaning('求婚', meaningOf('propose')));
  assert.equal(matchesMeaning('求', meaningOf('propose')), false);
  assert.ok(matchesMeaning('不动产', meaningOf('real')));
  assert.ok(matchesMeaning('联合', meaningOf('combine')));
  assert.ok(matchesMeaning('使联合', meaningOf('combine')));
});
check('dictionary ellipses allow omission of placeholders, without wildcard prose', () => {
  assert.ok(matchesMeaning('在期间', 'prep. 在...期间'));
  assert.ok(matchesMeaning('在……期间', 'prep. 在...期间'));
  assert.ok(matchesMeaning('为提供住宿', meaningOf('accommodate')));
  assert.equal(matchesMeaning('为所有人提供住宿', meaningOf('accommodate')), false);
  assert.equal(matchesMeaning('住宿', meaningOf('accommodate')), false);
});
check('blank answers, pure English entries, and unknown senses fail', () => {
  assert.equal(matchesMeaning('', meaningOf('abandon')), false);
  assert.equal(matchesMeaning('  \n ', meaningOf('abandon')), false);
  assert.equal(matchesMeaning('苹果', meaningOf('abandon')), false);
  assert.deepEqual(meaningAnswers('n. English only'), []);
  assert.deepEqual(meaningAnswers(''), []);
  assert.ok(matchesMeaning('目的', 'n. 目的'));
  assert.equal(matchesMeaning('目', 'n. 目的'), false);
});
check('adjective aliases accept natural short answers without weakening noun or prose checks', () => {
  assert.ok(matchesMeaning('好', 'a. 好的'));
  assert.ok(matchesMeaning('强', 'a. 强的'));
  assert.ok(matchesMeaning('新', 'adj. 新的'));
  assert.ok(matchesMeaning('新', '形容词：新的'));
  assert.ok(matchesMeaning('好', 'n. 好处；adj. 好的；n. 目的'));
  assert.equal(matchesMeaning('目', 'n. 好处；adj. 好的；n. 目的'), false);
  assert.equal(matchesMeaning('放弃的', meaningOf('abandon')), false);
  assert.equal(matchesMeaning('不是好', 'a. 好的'), false);
  assert.equal(matchesMeaning('我觉得不是新的而是旧的', 'a. 新的'), false);
  assert.equal(matchesMeaning('我不认为这个单词意思是强', 'adj. 强的'), false);
});
check('every extracted real catalog sense can be submitted verbatim', () => {
  let senses = 0;
  for (const word of catalogWords) {
    for (const sense of meaningAnswers(word.meaning)) {
      assert.ok(matchesMeaning(sense, word.meaning), `${word.word}: ${sense}`);
      senses++;
    }
  }
  assert.ok(senses > catalogWords.length);
});
const makeWord = (id, name, meaning) => {
  const word = new Word();
  word.id = id; word.word = name; word.meaning = meaning;
  word.phonetic = '/test/'; word.example = 'An example.'; word.translation = '一个例句。'; word.sourceBookId = 'cet4';
  return word;
};
check('session filters invalid candidates, deduplicates ids, and protects its word snapshot', () => {
  const session = new ChallengeService();
  const original = makeWord(1, 'abandon', meaningOf('abandon'));
  session.start([original, makeWord(1, 'duplicate', '错误'), makeWord(2, 'state', meaningOf('state')),
    makeWord(3, 'english', 'English only'), makeWord(4, '', '空白'), makeWord(0, 'invalid', '无效')]);
  assert.equal(session.getTotal(), 2);
  original.meaning = '错误';
  const visited = new Set();
  while (!session.isComplete()) {
    const current = session.currentWord();
    assert.ok(current); assert.ok(!visited.has(current.id)); visited.add(current.id);
    assert.equal(current.phonetic, '/test/'); assert.equal(current.sourceBookId, 'cet4');
    const answer = meaningAnswers(current.meaning)[0];
    current.meaning = 'changed in UI';
    assert.ok(session.submit(answer)); session.next();
  }
  assert.deepEqual([...visited].sort(), [1, 2]);
  assert.equal(session.getCorrectCount(), 2);
  assert.equal(session.getIndex(), 2);
  assert.equal(session.currentWord(), undefined);
});
check('empty and premature actions cannot advance or score; repeat submission cannot score twice', () => {
  const session = new ChallengeService();
  session.start([makeWord(1, 'abandon', meaningOf('abandon'))]);
  assert.throws(() => session.submit(' '), /中文意思/);
  assert.equal(session.isAnswered(), false);
  assert.throws(() => session.next(), /提交答案/);
  assert.equal(session.getIndex(), 0);
  assert.equal(session.getCorrectCount(), 0);
  assert.ok(session.submit('放弃'));
  assert.equal(session.isAnswered(), true);
  assert.equal(session.getLastResult(), true);
  assert.ok(session.submit('错误'));
  assert.ok(session.submit(' '));
  assert.equal(session.getCorrectCount(), 1);
  session.next(); assert.equal(session.isComplete(), true);
  assert.throws(() => session.submit('放弃'), /已结束/);
  session.next(); assert.equal(session.getIndex(), 1);
});
check('incorrect answers and a new round reset session state cleanly', () => {
  const session = new ChallengeService();
  session.start([makeWord(1, 'abandon', meaningOf('abandon'))]);
  assert.equal(session.submit('苹果'), false);
  assert.equal(session.submit('放弃'), false);
  assert.equal(session.getLastResult(), false);
  assert.equal(session.getCorrectCount(), 0);
  session.next(); assert.equal(session.isComplete(), true);
  session.start([makeWord(2, 'state', meaningOf('state'))]);
  assert.equal(session.getIndex(), 0); assert.equal(session.isAnswered(), false);
  assert.equal(session.isComplete(), false); assert.ok(session.submit('状态'));
  assert.equal(session.getCorrectCount(), 1);
  session.start([]);
  assert.equal(session.isComplete(), true); assert.equal(session.getCorrectCount(), 0);
  assert.equal(session.currentWord(), undefined);
});
console.log(`${checks} challenge checks passed.`);
