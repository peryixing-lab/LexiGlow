/* Exercise actual offline cloze/spelling logic and every packaged original example. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(output.outputText, filename);
};
const { Word } = require(path.join(ets, 'model/AppModels.ets'));
const { buildClozeQuestion, buildClozeRound, clozeContainsWord } = require(path.join(ets, 'utils/ClozeBuilder.ets'));
const { spellingMatches, dictationMatches } = require(path.join(ets, 'utils/SpellingUtils.ets'));
const { PracticeClock } = require(path.join(ets, 'utils/PracticeClock.ets'));
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/wordbooks/catalog.json')));
const dictionary = new Map(catalog.books.flatMap(book => book.words).map(word => [word.word.toLowerCase(), word]));
const pack = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/examples/original-examples-v1.json')));
const word = (id, headword, meaning = 'n. 物体', example = '', translation = '') =>
  Object.assign(new Word(), { id, word: headword, meaning, example, translation });
let checks = 0;
const check = (name, action) => { action(); checks++; console.log(`PASS ${name}`); };
check('dictation requires a complete word while spelling retains its middle-letter answer', () => {
  assert.ok(spellingMatches('shine', 'hin'));
  assert.equal(dictationMatches('shine', 'hin'), false);
  assert.ok(dictationMatches('shine', ' SHINE '));
  assert.equal(dictationMatches('shine', ''), false);
});
check('practice clock excludes repeated background and hidden-page intervals', () => {
  const clock = new PracticeClock();
  clock.resume(10000); clock.resume(11000);
  assert.equal(clock.remaining(90, 13500), 87);
  clock.pause(13500); clock.pause(17000);
  assert.equal(clock.remaining(90, 313500), 87);
  clock.resume(313500); assert.equal(clock.duration(315000), 5000);
  clock.pause(315000); assert.equal(clock.duration(900000), 5000);
  clock.reset(); assert.equal(clock.duration(900000), 0);
});
check('cloze boundaries reject substrings, hyphen fragments, and contractions', () => {
  assert.equal(clozeContainsWord('art', 'A cartoon hangs on the wall.'), false);
  assert.equal(clozeContainsWord('well', 'A well-known singer arrived.'), false);
  assert.equal(clozeContainsWord('can', "I can't come today."), false);
  assert.ok(clozeContainsWord('art', 'The art, framed in oak, was beautiful.'));
});
check('cloze detects common regular inflections and does not invent a missing occurrence', () => {
  for (const [headword, sentence] of [
    ['apple', 'The apples are ripe.'], ['watch', 'He watches the road.'], ['study', 'She studied the map.'],
    ['plan', 'We planned a holiday.'], ['move', 'The boat is moving.'], ['lie', 'The cat is lying on the rug.']
  ]) { assert.ok(clozeContainsWord(headword, sentence), headword); }
  assert.equal(clozeContainsWord('go', 'He went home.'), false);
  assert.equal(clozeContainsWord('', 'An empty answer.'), false);
});
check('cloze prefers matching noun choices, deduplicates spellings, and blanks every repeated answer', () => {
  const target = word(1, 'river', 'n. 河流', 'The river flows, and the river rises.', '河流流淌着，水位也升高了。');
  const candidates = [target, word(2, 'forest', 'n. 森林'), word(3, 'garden', 'n. 花园'),
    word(4, 'market', 'n. 市场'), word(5, 'Forest', 'n. 森林'), word(6, 'angry', 'a. 生气的')];
  const question = buildClozeQuestion(target, candidates);
  assert.ok(question); assert.equal(question.options.length, 4);
  assert.equal(new Set(question.options.map(option => option.text.toLowerCase())).size, 4);
  assert.deepEqual(new Set(question.options.map(option => option.text)), new Set(['river', 'forest', 'garden', 'market']));
  assert.equal(clozeContainsWord('river', question.sentence), false);
  assert.equal((question.sentence.match(/_____/g) || []).length, 2);
  assert.equal(question.translation, target.translation);
  assert.equal(question.originalSentence, target.example);
});
check('four options preserve a shared grammatical inflection', () => {
  const target = word(1, 'apple', 'n. 苹果', 'The apples are ripe.', '苹果熟了。');
  const question = buildClozeQuestion(target, [target, word(2, 'pear'), word(3, 'peach'), word(4, 'berry')]);
  assert.ok(question);
  assert.deepEqual(new Set(question.options.map(option => option.text)), new Set(['apples', 'pears', 'peaches', 'berries']));
});
check('invalid, untranslated, ambiguous-form, and undersized inputs produce no question', () => {
  const target = word(1, 'river', 'n. 河流', 'The river is wide.', '这条河很宽。');
  assert.equal(buildClozeQuestion(target, [target, word(2, 'forest'), word(3, 'garden')]), undefined);
  const others = [word(2, 'forest'), word(3, 'garden'), word(4, 'market')];
  assert.equal(buildClozeQuestion(word(0, 'river', '', target.example, target.translation), others), undefined);
  assert.equal(buildClozeQuestion(word(1, 'river', '', 'A garden.', '一个花园。'), others), undefined);
  assert.equal(buildClozeQuestion(word(1, 'river', '', target.example, ''), others), undefined);
  assert.equal(buildClozeQuestion(word(1, 'help', 'v. 帮助', 'I help her because she helped me.', '我帮她，因为她帮过我。'), others), undefined);
});
check('round deduplicates headwords and never exceeds the requested limit', () => {
  const words = [word(1, 'river', 'n. 河流', 'A river crosses the valley.', '一条河穿过山谷。'),
    word(2, 'forest', 'n. 森林', 'A forest covers the hill.', '森林覆盖着山丘。'),
    word(3, 'garden'), word(4, 'market'), word(5, 'River', 'n. 河流', 'The river is wide.', '河很宽。')];
  const questions = buildClozeRound(words, 1);
  assert.equal(questions.length, 1);
  const full = buildClozeRound(words, 20);
  assert.equal(full.length, 2); assert.equal(new Set(full.map(question => question.word.word.toLowerCase())).size, 2);
});
check('original pack covers at least 1,000 real distinct dictionary headwords with authored bilingual content', () => {
  assert.equal(pack.version, 1); assert.ok(pack.examples.length >= 1000);
  assert.equal(new Set(pack.examples.map(example => example.headword)).size, pack.examples.length);
  assert.equal(pack.headwordCount, pack.examples.length);
  const source = fs.readFileSync(path.join(root, 'tools/data/original_examples.tsv'), 'utf8').split('\n')
    .filter(row => row && !row.startsWith('#')).map(row => row.split('\t'));
  const authored = new Set(source.map(([example, translation]) => JSON.stringify([example, translation])));
  assert.equal(pack.sentenceCount, source.length);
  assert.equal(pack.license, 'GPL-3.0-only'); assert.ok(pack.provenance.includes('no third-party'));
  assert.equal(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', pack.licenseFile), 'utf8'),
    fs.readFileSync(path.join(root, 'LICENSE'), 'utf8'));
  for (const example of pack.examples) {
    assert.ok(dictionary.has(example.headword), `real dictionary headword: ${example.headword}`);
    assert.ok(clozeContainsWord(example.headword, example.example), `target occurs: ${example.headword}`);
    assert.ok(/[\u3400-\u9fff]/.test(example.translation), `Chinese translation: ${example.headword}`);
    assert.ok(authored.has(JSON.stringify([example.example, example.translation])), `authored source: ${example.headword}`);
    assert.equal(/the word|means in english|spelled|vocabulary item/i.test(example.example), false,
      `not a metalinguistic placeholder: ${example.headword}`);
  }
});
check('every original entry can generate a usable four-choice question without leaking its answer', () => {
  const entries = pack.examples.map((entry, index) => word(index + 1, entry.headword,
    dictionary.get(entry.headword).meaning, entry.example, entry.translation));
  let generated = 0;
  for (const target of entries) {
    const question = buildClozeQuestion(target, entries);
    assert.ok(question, `usable original example: ${target.word}`);
    assert.equal(question.options.length, 4);
    assert.equal(question.options.filter(option => option.wordId === target.id).length, 1);
    assert.equal(clozeContainsWord(target.word, question.sentence), false, `hidden target: ${target.word}`);
    generated++;
  }
  assert.ok(generated >= 1000);
});
console.log(`${checks} practice checks passed; ${pack.examples.length} original headwords verified.`);
