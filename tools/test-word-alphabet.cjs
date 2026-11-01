const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
require.extensions['.ets'] = (module, filename) => {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename });
  module._compile(result.outputText, filename);
};
const alphabetUtils = require(path.resolve(__dirname, '../entry/src/main/ets/utils/WordAlphabet.ets'));
const { buildWordAlphabet, alphabetRowForLetter, wordInitial } = alphabetUtils;
let checks = 0;
const check = (label, action) => { action(); checks++; console.log(`PASS ${label}`); };
const word = (id, spelling) => ({ id, word: spelling, meaning: 'test' });
check('Every one of 6,500 words is reachable; no 80-item limit remains', () => {
  const words = Array.from({ length: 6500 }, (_, i) => word(i + 1,
    String.fromCharCode(65 + i % 26) + String(i).padStart(5, '0')));
  for (const columns of [1, 2, 3]) {
    const index = buildWordAlphabet(words, columns);
    assert.equal(index.rows.flatMap(row => row.words).length, 6500);
    assert.equal(new Set(index.rows.flatMap(row => row.words).map(item => item.id)).size, 6500);
    assert(index.rows.every(row => row.words.length > 0 && row.words.length <= columns));
    assert.equal(new Set(index.rows.map(row => row.key)).size, index.rows.length);
    for (const letter of index.letters) {
      const row = alphabetRowForLetter(index, letter);
      assert.equal(index.rows[row].letter, letter);
      assert.equal(index.rows[row].firstInLetter, true);
    }
  }
});
check('Letters remain contiguous in tablet rows and source order stays unchanged', () => {
  const words = [word(1, 'zebra'), word(2, 'Ant'), word(3, 'apple'), word(4, 'banana'), word(5, 'be')];
  const original = words.map(item => item.word);
  const index = buildWordAlphabet(words, 3);
  assert.deepEqual(words.map(item => item.word), original);
  assert.deepEqual(index.rows.map(row => row.words.map(item => item.word)), [['Ant', 'apple'], ['banana', 'be'], ['zebra']]);
  assert(index.rows.every(row => row.words.every(item => wordInitial(item.word) === row.letter)));
});
check('Filtered and missing-letter jumps choose the nearest available group safely', () => {
  const index = buildWordAlphabet([word(1, 'banana'), word(2, 'map'), word(3, 'mouse')]);
  assert.equal(index.rows[alphabetRowForLetter(index, 'A')].letter, 'B');
  assert.equal(index.rows[alphabetRowForLetter(index, 'C')].letter, 'M');
  assert.equal(index.rows[alphabetRowForLetter(index, 'Z')].letter, 'M');
  assert.equal(alphabetRowForLetter(index, '!'), -1);
  assert.equal(alphabetRowForLetter(buildWordAlphabet([]), 'A'), -1);
});
check('Custom nonalphabetic words remain accessible in #; column values are bounded', () => {
  const words = [word(1, '101'), word(2, '英文'), word(3, ' apple'), word(4, 'Banana')];
  const index = buildWordAlphabet(words, 0);
  assert.equal(index.letters.at(-1), '#');
  assert.equal(index.rows[alphabetRowForLetter(index, '#')].letter, '#');
  assert.equal(index.rows.flatMap(row => row.words).length, 4);
  assert(buildWordAlphabet(words, Infinity).rows.every(row => row.words.length === 1));
});
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/components/AlphabetWordList.ets'), 'utf8');
let logic = source.slice(0, source.indexOf('\n  @Builder\n')) + '\n}\n';
logic = logic.replace(/^import .*;\s*$/gm, '').replace(/@ComponentV2\s*/g, '')
  .replace(/@(Local|Param|Event|BuilderParam)\s+/g, '').replace(/@Monitor\([^\n]*\)\s*/g, '')
  .replace(/export struct /g, 'export class ');
const compiled = ts.transpileModule(logic, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
const exportsObject = {};
class Scroller {
  constructor() { this.jumps = []; this.scrolls = []; }
  scrollToIndex(...args) { this.jumps.push(args); }
  scrollTo(value) { this.scrolls.push(value); }
}
const stubs = { ...alphabetUtils, Scroller, ScrollAlign: { START: 'start' } };
new Function('exports', ...Object.keys(stubs), compiled)(exportsObject, ...Object.values(stubs));
check('Actual component letter jumps include its header and follow filtered data after reload', () => {
  const list = new exportsObject.AlphabetWordList();
  list.words = [word(1, 'apple'), word(2, 'ant'), word(3, 'banana'), word(4, 'zebra')];
  list.columns = 2; list.aboutToAppear();
  assert.equal(list.scroller.scrolls.length, 0, 'Scroller is not bound before the List is created');
  list.listMounted = true;
  list.jumpTo(list.alphabet.indexOf('B'));
  assert.deepEqual(list.scroller.jumps.at(-1), [2, false, 'start']);
  list.syncLetter(3); assert.equal(list.alphabet[list.selectedLetter], 'Z');
  list.words = [word(3, 'banana')]; list.onWordsChanged();
  assert.equal(list.scroller.scrolls.length, 1, 'a filtered result resets a mounted list');
  assert.equal(list.source.totalCount(), 1);
  assert.equal(list.source.getData(0).words[0].id, 3);
  list.jumpTo(list.alphabet.indexOf('Z'));
  assert.deepEqual(list.scroller.jumps.at(-1), [1, false, 'start']);
  list.words = []; list.onWordsChanged(); const jumps = list.scroller.jumps.length;
  list.jumpTo(0); assert.equal(list.scroller.jumps.length, jumps);
});
check('Actual data source notifies lazy-render subscribers and refreshes changed words with stable IDs', () => {
  const list = new exportsObject.AlphabetWordList(); let notifications = 0;
  const listener = { onDataReloaded() { notifications++; } };
  list.source.registerDataChangeListener(listener);
  list.words = [word(1, 'apple')]; list.aboutToAppear();
  const oldKey = list.source.getData(0).key;
  list.words = [word(1, 'ant')]; list.onWordsChanged();
  assert.equal(list.source.getData(0).words[0].word, 'ant');
  assert.notEqual(list.source.getData(0).key, oldKey);
  assert.equal(notifications, 2);
  list.source.unregisterDataChangeListener(listener);
  list.onWordsChanged(); assert.equal(notifications, 2);
});
console.log(`Verified ${checks} alphabet word-list checks.`);
