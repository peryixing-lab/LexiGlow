/* Executes real article component lifecycle methods; builders remain a native UI acceptance check. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const sources = path.resolve(__dirname, '../entry/src/main/ets');
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename }); module._compile(output.outputText, filename);
};
const models = require(path.join(sources, 'model/AppModels.ets'));
const articleModels = require(path.join(sources, 'model/ArticleModels.ets'));
const experienceModels = require(path.join(sources, 'model/ExperienceModels.ets'));
const experienceUtils = require(path.join(sources, 'utils/ExperienceUtils.ets'));
const tokenizer = require(path.join(sources, 'utils/ArticleTokenizer.ets'));
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { resolve, reject, promise };
};
const loadComponent = (name, stubs) => {
  const source = fs.readFileSync(path.join(sources, `pages/${name}.ets`), 'utf8');
  const component = source.slice(source.indexOf(`@ComponentV2\nexport struct ${name}`));
  let logic = component.slice(0, component.indexOf('\n  @Builder\n')) + '\n}\n';
  if (name === 'ArticlePage') {
    logic = source.slice(source.indexOf('class ArticleParagraphSource'), source.indexOf('@ComponentV2\nstruct ArticleParagraphView')) + logic;
  }
  logic = logic.replace(/@ComponentV2\s*/g, '').replace(/@(Local|Param|Event)\s+/g, '')
    .replace(/export struct /g, 'export class ');
  const output = ts.transpileModule(logic, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: `${name}.ts` }).outputText;
  const values = { ...models, ...articleModels, ...experienceModels, ...experienceUtils, ...tokenizer,
    ExperienceService: { getInstance: () => ({ async reading(id) { return { articleId: id, paragraphIndex: 0 }; }, async sentences() { return []; } }) }, exports: {},
    Scroller: class { scrollToIndex() {} }, ScrollAlign: { START: 0 },
    adaptiveWindowState: () => ({ bottomInset: 0 }), ...stubs };
  new Function(...Object.keys(values), output)(...Object.values(values));
  const page = new values.exports[name]();
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  return page;
};
const word = (id, spelling) => Object.assign(new models.Word(), { id, word: spelling, meaning: 'test' });
const progress = id => Object.assign(new models.WordProgress(), { wordId: id });
const article = (id, body) => Object.assign(new articleModels.Article(), { id, title: `article ${id}`, body });
let checks = 0;
const check = async (label, action) => { await action(); checks++; console.log(`PASS ${label}`); };
(async () => {
  await check('Old article loads cannot replace a new article or repaint after leaving', async () => {
    const old = deferred(), leaving = deferred();
    const service = { get: id => id === 1 ? old.promise : id === 3 ? leaving.promise : Promise.resolve(article(2, 'Second.')) };
    const page = loadComponent('ArticlePage', { ArticleService: { getInstance: () => service } });
    page.articleId = 1; const first = page.load();
    page.articleId = 2; await page.load(); old.resolve(article(1, 'First.')); await first;
    assert.equal(page.article.id, 2); assert.equal(page.source.getData(0).tokens[0].text, 'Second');
    page.articleId = 3; const third = page.load(); page.aboutToDisappear();
    leaving.resolve(article(3, 'Third.')); await third; assert.equal(page.article.id, 2);
  });
  await check('Rapid word taps ignore old definitions and old progress reads', async () => {
    const first = deferred(), oldProgress = deferred();
    const service = { lookup: spelling => spelling === 'first' ? first.promise : Promise.resolve(word(2, spelling)) };
    const learning = { getProgress: id => id === 1 ? oldProgress.promise : Promise.resolve(progress(id)) };
    const page = loadComponent('ArticlePage', {
      ArticleService: { getInstance: () => service }, LearningService: { getInstance: () => learning }
    });
    const firstTap = page.openWord('first'); await page.openWord('second'); first.resolve(word(1, 'first')); await firstTap;
    assert.equal(page.selectedWord.id, 2); assert.equal(page.selectedProgress.wordId, 2);
    service.lookup = async spelling => word(spelling === 'first' ? 1 : 2, spelling);
    const waitingProgress = page.openWord('first'); await Promise.resolve();
    await page.openWord('second'); oldProgress.resolve(progress(1)); await waitingProgress;
    assert.equal(page.selectedWord.id, 2); assert.equal(page.selectedProgress.wordId, 2);
  });
  await check('An old favorite save remains on its word and cannot alter the newly selected word', async () => {
    const saved = deferred(), flags = [];
    const learning = {
      async setFavorite(id, value) { flags.push([id, value]); await saved.promise; },
      getProgress: async id => progress(id)
    };
    const page = loadComponent('ArticlePage', {
      ArticleService: { getInstance: () => ({ lookup: async spelling => word(2, spelling) }) },
      LearningService: { getInstance: () => learning }
    });
    page.selectedWord = word(1, 'first'); page.selectedProgress = progress(1);
    const saving = page.setFlag(true); await page.openWord('second'); saved.resolve(); await saving;
    assert.deepEqual(flags, [[1, true]]); assert.equal(page.selectedWord.id, 2);
    assert.equal(page.selectedProgress.favorite, false); assert.equal(page.flagSaving, false);
  });
  await check('Repeated speech keeps ownership of the active request so leaving always cancels playback', async () => {
    const first = deferred(), second = deferred(); let spoken = 0, stopped = 0;
    const page = loadComponent('ArticlePage', { AudioService: { getInstance: () => ({
      speak: () => (++spoken === 1 ? first.promise : second.promise), stop() { stopped++; }
    }) } });
    page.spelling = 'hello'; const firstSpeech = page.speak(), secondSpeech = page.speak();
    first.resolve(); await firstSpeech; assert.equal(page.ownsSpeech, true);
    page.aboutToDisappear(); assert.equal(stopped, 1); second.resolve(); await secondSpeech;
    assert.equal(page.ownsSpeech, false);
  });
  await check('Canceling or leaving file selection preserves a draft and resets busy state', async () => {
    let selected = Promise.resolve(undefined);
    const page = loadComponent('ArticleLibraryPage', {
      ArticleImportService: { importFile: () => selected }
    });
    page.draftTitle = 'my draft'; page.draftBody = 'Keep my words.';
    await page.selectFile(); assert.equal(page.draftBody, 'Keep my words.'); assert.equal(page.busy, false);
    const file = deferred(); selected = file.promise; const loading = page.selectFile();
    page.aboutToDisappear(); file.resolve({ title: 'other', body: 'Other words.' }); await loading;
    assert.equal(page.draftTitle, 'my draft'); assert.equal(page.draftBody, 'Keep my words.'); assert.equal(page.busy, false);
  });
  await check('Reading restoration ignores initial layout events and cancels work after leaving', async () => {
    const timers = new Map(), jumps = [], saved = []; let timerId = 0;
    const page = loadComponent('ArticlePage', {
      Scroller: class { scrollToIndex(...args) { jumps.push(args); } },
      setTimeout(callback) { const id = ++timerId; timers.set(id, callback); return id; },
      clearTimeout(id) { timers.delete(id); },
      ArticleService: { getInstance: () => ({ async savePosition(id, index) { saved.push([id, index]); } }) }
    });
    page.article = article(-1, 'First.\n\nSecond.\n\nThird.');
    page.source.setData(tokenizer.articleParagraphs(page.article.body));
    page.ready = true; page.initialParagraph = 2; page.lastParagraph = 2;
    page.moved(0); assert.equal(page.lastParagraph, 2);
    page.restorePosition(); page.restorePosition(); assert.equal(timers.size, 1);
    const restore = timers.get(page.restoreTimer); timers.delete(page.restoreTimer); restore();
    assert.deepEqual(jumps, [[3, false, 0]]); assert.equal(page.positionRestored, true);
    page.moved(4); page.aboutToDisappear();
    assert.deepEqual(saved, [[-1, 2]]); assert.equal(timers.size, 0);
    page.positionRestored = false; page.restorePosition();
    const stale = timers.get(page.restoreTimer); page.aboutToDisappear(); stale();
    assert.equal(jumps.length, 1); assert.equal(timers.size, 0);
  });
  console.log(`Verified ${checks} article lifecycle checks.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
