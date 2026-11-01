/* Tests real component method bodies after removing ArkUI builder syntax and decorators.
 * No component logic is reimplemented here. Native UI rendering remains a separate device check. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || path.join(
  process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents',
  'plugins/openharmony/ace-server/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
require.extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: filename
  });
  module._compile(output.outputText, filename);
};
const experienceModels = require(path.join(ets, 'model/ExperienceModels.ets'));
const articleModels = require(path.join(ets, 'model/ArticleModels.ets'));
const experienceUtils = require(path.join(ets, 'utils/ExperienceUtils.ets'));
const practiceClock = require(path.join(ets, 'utils/PracticeClock.ets'));
const spellingUtils = require(path.join(ets, 'utils/SpellingUtils.ets'));
const clozeUtils = require(path.join(ets, 'utils/ClozeBuilder.ets'));
const modelsSource = ts.transpileModule(fs.readFileSync(path.join(ets, 'model/AppModels.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const models = {};
new Function('exports', modelsSource)(models);
const timeSource = ts.transpileModule(fs.readFileSync(path.join(ets, 'utils/TimeUtils.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const timeUtils = {};
new Function('exports', timeSource)(timeUtils);
const drain = async () => { for (let i = 0; i < 8; i++) { await new Promise(resolve => setImmediate(resolve)); } };
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};

class Stack {
  constructor() { this.paths = []; }
  pushPathByName(name, param) { this.paths.push({ name, param }); }
  replacePathByName(name, param) { this.paths.pop(); this.pushPathByName(name, param); }
  clear() { this.paths = []; }
  pop() { return this.paths.pop(); }
  size() { return this.paths.length; }
  getAllPathName() { return this.paths.map(item => item.name); }
  disableAnimation(value) { this.animationDisabled = value; }
}
class Modifier { expandSafeArea() { return this; } }

function loadComponent(filename, name, service, extra = {}) {
  const source = fs.readFileSync(path.join(ets, filename), 'utf8');
  const firstBuilder = source.indexOf('\n  @Builder');
  const build = source.indexOf('\n  build()');
  const ends = [firstBuilder, build].filter(index => index >= 0);
  assert.ok(ends.length > 0, `${name} must have an identifiable ArkUI builder boundary`);
  let logic = source.slice(0, Math.min(...ends)) + '\n}\n';
  logic = logic.replace(/^import .*;\s*$/gm, '').replace(/@(Entry|ComponentV2|Component)(?:\([^\n]*\))?\s*/g, '')
    .replace(/@(Local|Param|Event|State)\s+/g, '').replace(/export\s+struct\s+/, 'export class ')
    .replace(/(^|\n)struct\s+/, '$1export class ');
  const output = ts.transpileModule(logic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: name + '.ts'
  }).outputText;
  const storage = new Map();
  const timers = new Map();
  const motion = { reduced: false, failRead: false, failListen: false,
    listeners: new Set(), added: [], removed: [] };
  let nextTimer = 0;
  const instanceService = { getInstance: () => service };
  const noOpAudio = { getInstance: () => ({ async stop() {}, isActive: () => false,
    release() {}, speak: async () => {} }) };
  const context = { eventHub: { on() {}, off() {}, emit() {} }, getApplicationContext: () => ({ setColorMode() {} }) };
  const stubs = {
    ...models, ...experienceModels, ...articleModels, ...experienceUtils, ...timeUtils, ...practiceClock, ...spellingUtils, ...clozeUtils,
    PracticeJournal: class { beginQuestion() {} pause() {} resume() {} async record() {} },
    ExperienceService: { getInstance: () => ({ async attempts() { return []; } }) },
    ArticleService: { getInstance: () => ({ async recommendations() { return []; } }) },
    exports: {}, LearningService: instanceService,
    AudioFlowService: noOpAudio, AudioService: noOpAudio,
    PronunciationPresenter: class { cancel() {} async play() {} async setup() {} },
    LiveStudyService: { getInstance: () => ({ async stop() {}, async start() {}, async update() {} }) },
    HapticService: { pulse() {}, complete() {} }, FormService: { async update() {} },
    ReminderService: { async cleanupLegacyTests() {}, async syncDailyProgress() {} },
    SharedWordService: { wordsFromText: text => text.split(/\s+/).filter(Boolean) },
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    Scroller: class { constructor() { this.scrolls = []; } scrollTo(options) { this.scrolls.push(options); } },
    TabsController: class {}, CommonModifier: Modifier,
    NavPathStack: Stack, SafeAreaType: { SYSTEM: 1 }, SafeAreaEdge: { TOP: 1, BOTTOM: 2 },
    uiMaterial: { ImmersiveMaterial: class {}, ImmersiveStyle: { ULTRA_THIN: 1 } },
    ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1, COLOR_MODE_NOT_SET: -1 } },
    adaptiveWindowState: () => ({}), $r: resource => resource,
    setInterval: callback => { const id = ++nextTimer; timers.set(id, callback); return id; },
    clearInterval: id => timers.delete(id), setTimeout: callback => { const id = ++nextTimer; timers.set(id, callback); return id; },
    clearTimeout: id => timers.delete(id), Curve: { EaseOut: 1 }, KeyCode: {},
    accessibility: {
      isAnimationReduceEnabledSync() {
        if (motion.failRead) { throw new Error('motion setting unavailable'); }
        return motion.reduced;
      },
      onAnimationReduceStateChange(callback) {
        if (motion.failListen) { throw new Error('motion subscription unavailable'); }
        motion.added.push(callback); motion.listeners.add(callback);
      },
      offAnimationReduceStateChange(callback) { motion.removed.push(callback); motion.listeners.delete(callback); }
    },
    TransitionEffect: { IDENTITY: Symbol('identity') },
    window: { async getLastWindow() { return { async setWindowKeepScreenOn() {} }; } },
    ...extra
  };
  const names = Object.keys(stubs);
  new Function(...names, output)(...names.map(key => stubs[key]));
  const instance = new stubs.exports[name]();
  instance.getUIContext = () => ({ getHostContext: () => context, animateTo(_options, change) { change(); },
    getPromptAction: () => ({ showToast() {} }), getFocusController: () => ({ clearFocus() {} }) });
  return { instance, storage, timers, motion, stubs };
}

function word(id, spelling) { const result = new models.Word(); result.id = id; result.word = spelling; result.meaning = '微光'; return result; }
function snapshot() { const result = new models.AppSnapshot(); result.settings.onboarded = true; return result; }
function session(item) { const result = new models.StudySession(); result.mode = 'today'; result.items = [{ word: item, type: 'review' }]; return result; }

async function testSpellingSaveRestart() {
  const gate = deferred(), saved = [];
  const service = {
    getSpellingWords: async () => [word(2, 'shine')], getPracticeResults: async () => [],
    async savePracticeResult(...values) { saved.push(values); if (saved.length === 1) { await gate.promise; } }
  };
  const { instance: page, timers } = loadComponent('pages/SpellingChallengePage.ets', 'SpellingChallengePage', service);
  page.active = true; page.words = [word(1, 'glow')]; page.correctCount = 1; page.clock.resume();
  page.complete = true; page.loading = false;
  const saving = page.saveResult(); await drain();
  const previousVersion = page.version;
  await page.start();
  // The page may disable restart until persistence ends, or start a separately versioned round.
  const restarted = page.version !== previousVersion;
  gate.resolve(); await saving; await drain();
  if (restarted) {
    assert.equal(page.saved, false, 'an old result must not mark the new round already saved');
  } else { await page.start(); }
  page.correctCount = 1; page.finish(); await drain();
  assert.equal(saved.length, 2, 'both completed rounds must receive their own durable result');
  assert.deepEqual(saved.map(values => values.slice(0, 3)), [['spelling', 1, 1], ['spelling', 1, 1]]);
  page.aboutToDisappear(); assert.equal(timers.size, 0);
}

async function testSpellingHistoryFailurePreservesSavedResult() {
  let saves = 0, queries = 0;
  const result = { id: 1, mode: 'spelling', correct: 1, total: 1 };
  const service = {
    async savePracticeResult() { saves++; },
    async getPracticeResults() {
      queries++;
      if (queries === 1) { throw new Error('history read unavailable'); }
      return [result];
    }
  };
  const { instance: page } = loadComponent('pages/SpellingChallengePage.ets', 'SpellingChallengePage', service);
  page.active = true; page.words = [word(1, 'glow')]; page.correctCount = 1;
  page.complete = true; page.loading = false; page.clock.resume();
  await page.saveResult();
  assert.equal(page.saved, true, 'a committed score remains saved even if the history query fails');
  assert.equal(page.error, '', 'history errors must not claim a committed score was not saved');
  assert.ok(page.historyError);
  await page.saveResult();
  assert.equal(saves, 1, 'the failed history query must not duplicate an already committed score');
  await page.loadResults();
  assert.equal(page.historyError, ''); assert.deepEqual(page.results, [result]);
  assert.equal(saves, 1, 'the history retry only rereads results');
}

async function testSpellingSaveFailureStillRetries() {
  let saves = 0;
  const service = {
    async savePracticeResult() {
      saves++;
      if (saves === 1) { throw new Error('score write unavailable'); }
    },
    async getPracticeResults() { return []; }
  };
  const { instance: page } = loadComponent('pages/SpellingChallengePage.ets', 'SpellingChallengePage', service);
  page.active = true; page.words = [word(1, 'glow')]; page.correctCount = 1;
  page.complete = true; page.loading = false; page.clock.resume();
  await page.saveResult();
  assert.equal(page.saved, false); assert.ok(page.error); assert.equal(page.saving, false);
  await page.saveResult();
  assert.equal(page.saved, true); assert.equal(page.error, ''); assert.equal(saves, 2);
}

async function testDictationIsIndependentAndPauses() {
  const realNow = Date.now;
  let now = 100000, audioStops = 0;
  const spoken = [], saved = [];
  Date.now = () => now;
  try {
    const service = {
      getSpellingWords: async () => [word(1, 'glow')],
      getSettings: () => ({ hapticsEnabled: false }),
      getPracticeResults: async () => [
        { id: 1, mode: 'spelling', correct: 1, total: 1 },
        { id: 2, mode: 'dictation', correct: 0, total: 1 }
      ],
      async savePracticeResult(...values) { saved.push(values); }
    };
    const { instance: page, timers } = loadComponent('pages/SpellingChallengePage.ets', 'SpellingChallengePage', service, {
      PronunciationPresenter: class {
        cancel() {}
        async play(text, ui, current, update) {
          if (current()) { spoken.push(text); update('ready', ''); }
        }
      },
      AudioService: { getInstance: () => ({ stop() { audioStops++; } }) }
    });
    page.initialMode = 'dictation'; page.aboutToAppear(); await drain();
    assert.equal(page.mode, 'dictation'); assert.deepEqual(spoken, ['glow']);
    assert.deepEqual(page.letters, [], 'the target letters must not enter the dictation tile model');
    assert.deepEqual(page.results.map(result => result.mode), ['dictation']);
    now += 3500; page.tick(); assert.equal(page.remaining, 87);
    page.visibilityListener(false); assert.equal(timers.size, 0);
    const before = audioStops;
    now += 300000; page.visibilityListener(true); assert.equal(page.remaining, 87);
    now += 1000; page.tick(); assert.equal(page.remaining, 86);
    page.answer = 'lo'; page.submit();
    assert.equal(page.correct, false, 'a middle-letter answer cannot pass dictation');
    await drain(); page.next(); await drain();
    assert.equal(saved.length, 1); assert.deepEqual(saved[0].slice(0, 3), ['dictation', 0, 1]);
    assert.equal(saved[0][3], 4500, 'the saved duration excludes the five minutes in the background');
    assert.ok(audioStops > before, 'finishing cancels pronunciation');
    page.aboutToDisappear(); assert.equal(timers.size, 0);
  } finally { Date.now = realNow; }
}

async function testClozeSelectionAndSaveAreSingleFlight() {
  const first = word(1, 'river'); first.meaning = 'n. 河流';
  first.example = 'A bridge crosses the river.'; first.translation = '一座桥横跨这条河。';
  const distractors = [word(2, 'forest'), word(3, 'garden'), word(4, 'market')];
  const question = clozeUtils.buildClozeQuestion(first, [first, ...distractors]);
  assert.ok(question);
  const gate = deferred(), saved = [];
  const service = {
    getSettings: () => ({ hapticsEnabled: false }),
    getPracticeResults: async () => [
      { id: 1, mode: 'dictation' }, { id: 2, mode: 'cloze' }
    ],
    async savePracticeResult(...values) { saved.push(values); await gate.promise; }
  };
  const { instance: page } = loadComponent('pages/ClozeChallengePage.ets', 'ClozeChallengePage', service);
  page.active = true; page.loading = false; page.questions = [question]; page.clock.resume();
  const right = question.options.find(option => option.wordId === first.id);
  page.select(right); page.select(right);
  assert.equal(page.correctCount, 1, 'double taps cannot add a second correct answer');
  await drain(); page.next(); await drain();
  await page.start(); assert.equal(page.questions[0], question, 'a pending save blocks a new round');
  await page.saveResult(); assert.equal(saved.length, 1, 'repeated saves share the one pending write');
  gate.resolve(); await drain();
  assert.equal(page.complete, true); assert.equal(page.saved, true);
  assert.deepEqual(saved[0].slice(0, 3), ['cloze', 1, 1]);
  assert.deepEqual(page.results.map(result => result.mode), ['cloze']);
  page.aboutToDisappear();
}

async function testClozeIgnoresExamplesLoadedAfterLeaving() {
  const gate = deferred();
  const service = { getChallengeWords: async () => [word(1, 'river')], getPracticeResults: async () => [] };
  const { instance: page } = loadComponent('pages/ClozeChallengePage.ets', 'ClozeChallengePage', service, {
    OriginalExampleService: { supplement: () => gate.promise }
  });
  page.aboutToAppear(); await drain();
  page.aboutToDisappear();
  gate.resolve([word(1, 'river'), word(2, 'forest'), word(3, 'garden'), word(4, 'market')]);
  await drain();
  assert.deepEqual(page.questions, [], 'a delayed content load cannot publish to a departed page');
  assert.equal(page.clock.duration(), 0);
}

async function testAudioFlowReplayKeepsRetainedQueue() {
  const calls = [];
  const flowService = {
    async resume() { calls.push(['resume']); },
    async start(words, context) { calls.push(['start', words.map(item => item.id)]); assert.ok(context); }
  };
  const { instance: page } = loadComponent('pages/AudioFlowPage.ets', 'AudioFlowPage', {}, {
    AudioFlowState: class { constructor() { this.status = 'idle'; this.total = 0; this.word = word(0, ''); } },
    AudioFlowService: { getInstance: () => flowService }
  });
  // Reopening during background playback intentionally supplies no replacement words.
  page.available = []; page.flow = { status: 'completed', total: 1 };
  await page.control();
  assert.deepEqual(calls, [['resume']], 'replay must reuse the completed service queue instead of starting an empty one');
  page.available = [word(2, 'shine')]; page.flow = { status: 'idle', total: 0 };
  await page.control();
  assert.deepEqual(calls, [['resume'], ['start', [2]]], 'a fresh idle page still starts its selected words');
}

async function testLearnedDatePickerOnlyOffersKnownDates() {
  const queries = [], dialogs = [];
  const service = { async getLearnedWords(...args) { queries.push(args); return []; } };
  const { instance: page } = loadComponent('pages/LearnedWordsPage.ets', 'LearnedWordsPage', service, {
    dateKey: timestamp => new Date(timestamp).toLocaleDateString('sv-SE')
  });
  page.getUIContext = () => ({ showDatePickerDialog: options => dialogs.push(options) });
  page.dates = [{ date: '', count: 2 }];
  assert.equal(page.hasKnownDates(), false, 'unknown legacy dates must use the static date label');
  page.pickDate(); assert.equal(dialogs.length, 0);
  page.dates = [{ date: '2026-10-09', count: 1 }, { date: '2026-10-08', count: 1 }, { date: '', count: 2 }];
  assert.equal(page.hasKnownDates(), true);
  page.pickDate(); assert.equal(dialogs.length, 1);
  assert.equal(dialogs[0].selected.getDate(), 9, 'the picker starts from a real dated learning day');
  dialogs[0].onDateAccept(new Date(2026, 9, 8)); await drain();
  assert.equal(page.selectedDate, '2026-10-08'); assert.equal(queries[0][0], '2026-10-08');
}

async function testQuietCompletesWithoutTimer() {
  const { instance: page, timers } = loadComponent('pages/QuietReviewPage.ets', 'QuietReviewPage', {});
  page.active = true; page.words = [word(1, 'glow')]; page.mode = 'night';
  page.elapsedBeforePause = 30000; page.index = 0;
  page.run();
  assert.equal(page.complete, true, 'the resumed first tick should finish the final word');
  assert.equal(timers.size, 0, 'the completed final tick must not create a new interval');
  assert.equal(page.timer, -1);
}

async function testFamilyWordPublishesAtomically() {
  const progressGate = deferred();
  const original = word(1, 'glow'), related = word(2, 'shine');
  const service = {
    getWord: async () => related, getProgress: () => progressGate.promise,
    getHistory: async () => [], getWordEnrichment: async () => new models.WordEnrichment()
  };
  const { instance: page } = loadComponent('pages/Index.ets', 'Index', service);
  page.active = true; page.ready = true; page.snapshot = snapshot(); page.currentWord = original;
  page.currentProgress = new models.WordProgress(); page.currentProgress.wordId = 1;
  page.session = session(original); page.pathStack.pushPathByName('Learn', 'today');
  const opening = page.openRelatedWord(2); await drain();
  assert.equal(page.currentWord.id, 1, 'pending related-word metadata must not replace the visible learning word');
  assert.deepEqual(page.pathStack.getAllPathName(), ['Learn']);
  const progress = new models.WordProgress(); progress.wordId = 2; progressGate.resolve(progress);
  await opening;
  assert.equal(page.currentWord.id, 2); assert.equal(page.currentProgress.wordId, 2);
  assert.deepEqual(page.pathStack.getAllPathName(), ['Learn', 'WordDetail']);
}

async function testJudgmentCannotReopenOldDestination() {
  const recordGate = deferred(); const original = word(1, 'glow');
  const service = { record: () => recordGate.promise, canUndo: () => false, getSnapshot: async () => snapshot(),
    getProgress: async id => Object.assign(new models.WordProgress(), { wordId: id }),
    getWordEnrichment: async () => new models.WordEnrichment() };
  const { instance: page, storage } = loadComponent('pages/Index.ets', 'Index', service);
  page.active = true; page.ready = true; page.snapshot = snapshot(); page.currentWord = original;
  page.session = session(original); page.answerVisible = true; page.pathStack.pushPathByName('Learn', 'today');
  const judgment = page.judge(models.ReviewResult.KNOW); await drain();
  storage.set('lexiglowSharedText', 'shine'); page.handleRoute('shared', 0);
  const completed = session(original); completed.index = 1; completed.completed = 1;
  recordGate.resolve(completed); await judgment; await drain();
  assert.deepEqual(page.pathStack.getAllPathName(), ['SharedWords'], 'old judgment must not replace a newer share route with Summary');
  assert.equal(page.sharedText, 'shine');
}

async function testOldShareCannotEraseNewText() {
  const gate = deferred(); const ids = [];
  const service = { async setNewWord(id) { ids.push(id); await gate.promise; } };
  const { instance: page, storage } = loadComponent('pages/SharedWordsPage.ets', 'SharedWordsPage', service);
  page.active = true; page.text = 'glow'; page.selected = [1];
  storage.set('lexiglowSharedText', 'glow'); storage.set('lexiglowSharedRevision', 1);
  const saving = page.save(); await drain();
  page.aboutToDisappear(); storage.set('lexiglowSharedText', 'shine'); storage.set('lexiglowSharedRevision', 2);
  gate.resolve(); await saving;
  assert.deepEqual(ids, [1], 'the original explicit selection remains the only save payload');
  assert.equal(storage.get('lexiglowSharedText'), 'shine', 'an unloaded older confirmation must not clear a newer share');
}

async function testOnboardingMotionListenerLifecycle() {
  const state = snapshot(); state.settings.onboarded = false;
  const service = { async initialize() {}, async getSnapshot() { return state; } };
  const { instance: page, timers, motion, stubs } = loadComponent('pages/Index.ets', 'Index', service);
  motion.reduced = true;
  page.aboutToAppear(); await drain();
  assert.equal(page.pathStack.animationDisabled, true, 'native page navigation remains separate from onboarding motion');
  assert.equal(page.reduceMotion, true, 'the first render must read the current system motion preference');
  assert.equal(page.welcomeTransition(), stubs.TransitionEffect.IDENTITY, 'reduced motion must bypass onboarding transforms');
  assert.equal(motion.listeners.size, 1);
  const listener = motion.added[0];
  listener(false); assert.equal(page.reduceMotion, false, 'system preference updates while visible must reach the page');
  listener(true); assert.equal(page.reduceMotion, true);
  page.aboutToDisappear();
  assert.deepEqual(motion.removed, [listener], 'unsubscribe must use the exact registered callback');
  assert.equal(motion.listeners.size, 0); assert.equal(timers.size, 0);
  listener(false); assert.equal(page.reduceMotion, true, 'a queued callback after removal must not mutate a hidden page');
  page.aboutToDisappear();
  assert.deepEqual(motion.removed, [listener], 'repeat cleanup must not unregister the same listener twice');
  motion.reduced = false;
  page.aboutToAppear(); await drain();
  assert.equal(page.reduceMotion, false); assert.equal(motion.listeners.size, 1);
  assert.equal(motion.added[1], listener, 'reopening must reuse the stable callback instead of allocating another identity');
  page.aboutToDisappear(); assert.equal(motion.listeners.size, 0); assert.equal(timers.size, 0);
}

async function testOnboardingMotionCapabilityFailure() {
  for (const failure of ['failRead', 'failListen']) {
    const state = snapshot(); state.settings.onboarded = false;
    const service = { async initialize() {}, async getSnapshot() { return state; } };
    const { instance: page, timers, motion, stubs } = loadComponent('pages/Index.ets', 'Index', service);
    motion[failure] = true;
    page.aboutToAppear(); await drain();
    assert.equal(page.ready, true, `${failure} must not block database initialization or onboarding`);
    assert.equal(page.reduceMotion, true, `${failure} must fall back to motion-free onboarding`);
    assert.equal(page.welcomeTransition(), stubs.TransitionEffect.IDENTITY);
    page.aboutToDisappear(); assert.equal(motion.listeners.size, 0); assert.equal(timers.size, 0);
    assert.equal(motion.removed.length, 0, 'an unsuccessful subscription must not remove someone else\'s listener');
  }
}

async function testOnboardingRapidStepsPreserveSelections() {
  const { instance: page, timers } = loadComponent('pages/Index.ets', 'Index', {});
  page.selectedBook = 'cet6'; page.foundation = 'sprint'; page.selectedTarget = 30;
  for (const step of [1, 2, 3, 2, 1, 0, 1, 3, 2, 3]) { page.setWelcomeStep(step); }
  assert.equal(page.welcomeStep, 3, 'the latest explicit step must win without waiting on an earlier animation callback');
  assert.equal(page.selectedBook, 'cet6'); assert.equal(page.foundation, 'sprint'); assert.equal(page.selectedTarget, 30);
  assert.equal(timers.size, 0, 'step navigation must not queue timer-based state changes');
  assert.equal(page.welcomeScroller.scrolls.length, 10);
  assert.ok(page.welcomeScroller.scrolls.every(scroll => scroll.xOffset === 0 && scroll.yOffset === 0 && scroll.animation === false),
    'each new step must expose its heading immediately even when the previous wordbook list was scrolled');
  for (const step of [-1, 4, 3]) { page.setWelcomeStep(step); }
  assert.equal(page.welcomeStep, 3); assert.equal(page.welcomeScroller.scrolls.length, 10);
  page.busy = true; page.setWelcomeStep(2);
  assert.equal(page.welcomeStep, 3, 'step controls must not change the selection phase while completion is saving');
  assert.equal(page.welcomeScroller.scrolls.length, 10);
}

async function testOnboardingCompletionIsSingleFlight() {
  const gate = deferred(), saved = [], started = [];
  const state = snapshot(); state.settings.onboarded = false;
  state.settings.reminderEnabled = true;
  const service = {
    async updateSettings(settings) { saved.push(settings); await gate.promise; state.settings = settings; },
    async getSnapshot() { return state; }
  };
  const { instance: page } = loadComponent('pages/Index.ets', 'Index', service);
  page.snapshot = state; page.welcomeStep = 3; page.selectedBook = 'cet6';
  page.foundation = 'sprint'; page.selectedTarget = 30;
  page.beginStudy = async mode => { started.push(mode); };
  const first = page.finishOnboarding(); await drain();
  assert.equal(page.busy, true);
  await page.finishOnboarding(); page.setWelcomeStep(2);
  assert.equal(saved.length, 1, 'rapid repeated completion taps must not submit multiple settings updates');
  assert.equal(page.welcomeStep, 3);
  gate.resolve(); await first;
  assert.equal(page.busy, false); assert.equal(page.snapshot.settings.onboarded, true);
  assert.equal(saved[0].currentBookId, 'cet6'); assert.equal(saved[0].dailyNewTarget, 30);
  assert.equal(saved[0].foundation, 'sprint'); assert.equal(saved[0].learningMode, 'exam');
  assert.equal(saved[0].reminderEnabled, true, 'onboarding completion must preserve unrelated settings');
  assert.deepEqual(started, ['onboarding']);
}

async function testRefreshUsesDailyNewProgressAndConfiguredGoal() {
  const state = snapshot(), synced = [];
  const today = timeUtils.dateKey(), yesterday = timeUtils.shiftedDate(Date.now(), -1);
  state.settings.dailyNewTarget = 37; state.settings.reminderEnabled = true;
  state.plan.newTarget = 5; state.plan.newDone = 5; state.plan.reviewDone = 80;
  state.stats.days = [
    Object.assign(new models.DaySummary(), { date: yesterday, newCount: 400, reviewCount: 500 }),
    Object.assign(new models.DaySummary(), { date: today, newCount: 36, reviewCount: 120 })
  ];
  const { instance: page } = loadComponent('pages/Index.ets', 'Index', { async getSnapshot() { return state; } }, {
    ReminderService: { async syncDailyProgress(_context, settings, newCount) { synced.push({ settings, newCount }); } }
  });
  await page.refresh();
  assert.equal(synced.length, 1); assert.equal(synced[0].settings, state.settings);
  assert.equal(synced[0].settings.dailyNewTarget, 37, 'native reminder synchronization must receive the user\'s configured goal');
  assert.equal(synced[0].newCount, 36, 'only today\'s actual new-word count may satisfy that goal');
  assert.ok(synced[0].newCount < synced[0].settings.dailyNewTarget,
    'a completed reduced daily plan or high review count must not make the configured new-word goal complete');
  state.stats.days[1].newCount = 37;
  await page.refresh();
  assert.equal(synced[1].newCount, 37, 'a refreshed durable new-word record must reach reminder synchronization');
  state.stats.days = state.stats.days.slice(0, 1);
  await page.refresh();
  assert.equal(synced[2].newCount, 0, 'yesterday\'s progress must not satisfy today\'s goal when today has no row yet');
}

async function testSavedJudgmentSurvivesReminderSyncFailure() {
  const original = word(1, 'glow'), savedSnapshot = snapshot(), toasts = [], synced = [];
  savedSnapshot.stats.days = [Object.assign(new models.DaySummary(), { date: timeUtils.dateKey(), newCount: 1, reviewCount: 3 })];
  savedSnapshot.stats.totalLearned = 1;
  const completed = session(original); completed.index = 1; completed.completed = 1;
  let saves = 0;
  const service = {
    async record() { saves++; return completed; },
    canUndo() { return false; },
    async getSnapshot() { return savedSnapshot; }
  };
  const { instance: page } = loadComponent('pages/Index.ets', 'Index', service, {
    ReminderService: { async syncDailyProgress(_context, settings, newCount) {
      synced.push({ settings, newCount }); throw new Error('native reminder unavailable');
    } }
  });
  page.active = true; page.ready = true; page.snapshot = snapshot(); page.currentWord = original;
  page.session = session(original); page.session.items[0].type = 'new'; page.answerVisible = true;
  page.pathStack.pushPathByName('Learn', 'today'); page.toast = message => toasts.push(message);
  await page.judge(models.ReviewResult.KNOW);
  assert.equal(saves, 1); assert.equal(synced.length, 1); assert.equal(synced[0].newCount, 1);
  assert.equal(page.snapshot, savedSnapshot, 'a reminder failure must preserve the newly loaded durable learning snapshot');
  assert.equal(page.session, completed); assert.equal(page.answerVisible, false);
  assert.deepEqual(page.pathStack.getAllPathName(), ['Summary'], 'the saved final word must still finish the learning flow');
  assert.equal(page.busy, false); assert.equal(page.error, '');
  assert.match(page.reminderFeedback, /学习记录已保存/);
  assert.deepEqual(toasts, [], 'native reminder failure must not tell the user that a saved word was not saved');
  await page.judge(models.ReviewResult.KNOW);
  assert.equal(saves, 1, 'reminder failure must not leave the saved judgment available for duplicate submission');
}

async function testSearchInvalidatesDuringDebounce() {
  const old = deferred(), current = deferred(), calls = [];
  const { instance, timers } = loadComponent('pages/Index.ets', 'Index', {
    getWords(book, filter, query) { calls.push(query); return query === 'a' ? old.promise : current.promise; }
  });
  instance.searchText = 'a';
  const pending = instance.search();
  instance.scheduleSearch('apple');
  old.resolve([word(1, 'ant')]); await pending;
  assert.equal(instance.words.length, 0, 'old result is invalid as soon as input changes');
  assert.equal(instance.loadingWords, true);
  const timer = timers.get(instance.searchTimer); timer(); await drain();
  current.resolve([word(2, 'apple')]); await drain();
  assert.deepEqual(calls, ['a', 'apple']);
  assert.equal(instance.words[0].word, 'apple');
  assert.equal(instance.loadingWords, false);
  assert.equal(timers.size, 0, 'completed debounce does not leave a timer');
}

async function testSearchIgnoresObsoleteErrors() {
  const old = deferred();
  const { instance } = loadComponent('pages/Index.ets', 'Index', { getWords: () => old.promise });
  let toasts = 0; instance.toast = () => { toasts++; };
  const pending = instance.search(); instance.scheduleSearch('new');
  old.reject(new Error('obsolete')); await pending;
  assert.equal(toasts, 0);
  assert.equal(instance.loadingWords, true);
  instance.service = { getWords: async () => { throw new Error('current'); } };
  instance.words = [word(1, 'old')]; await instance.search();
  assert.equal(toasts, 1); assert.equal(instance.words.length, 0);
  assert.equal(instance.loadingWords, false);
}

(async () => {
  const tests = [
    ['search invalidates old results during debounce', testSearchInvalidatesDuringDebounce],
    ['search suppresses obsolete errors and clears failed results', testSearchIgnoresObsoleteErrors],
    ['spelling round persistence survives a rapid restart', testSpellingSaveRestart],
    ['saved spelling scores survive a history-read failure without duplicates', testSpellingHistoryFailurePreservesSavedResult],
    ['an uncommitted spelling score remains retryable', testSpellingSaveFailureStillRetries],
    ['dictation hides letter tiles, requires complete spelling, and pauses in the background', testDictationIsIndependentAndPauses],
    ['cloze double taps and restarts cannot duplicate an independent score', testClozeSelectionAndSaveAreSingleFlight],
    ['late original-example loads do not mutate a departed cloze page', testClozeIgnoresExamplesLoadedAfterLeaving],
    ['audio replay reuses its retained queue while a fresh page starts selected words', testAudioFlowReplayKeepsRetainedQueue],
    ['unknown learned dates have no picker while known dates load the selected day', testLearnedDatePickerOnlyOffersKnownDates],
    ['quiet final tick completes without leaking a timer', testQuietCompletesWithoutTimer],
    ['family details publish only after all local data is ready', testFamilyWordPublishesAtomically],
    ['old judgments cannot replace a newer incoming route', testJudgmentCannotReopenOldDestination],
    ['old share saving preserves newer pending text', testOldShareCannotEraseNewText],
    ['onboarding follows system reduced motion and cleans up its listener', testOnboardingMotionListenerLifecycle],
    ['unavailable motion APIs keep onboarding usable without animations', testOnboardingMotionCapabilityFailure],
    ['rapid onboarding steps preserve selections and reveal the next heading', testOnboardingRapidStepsPreserveSelections],
    ['onboarding completion submits once while settings save is pending', testOnboardingCompletionIsSingleFlight],
    ['reminder refresh uses today\'s durable new-word count and the configured goal', testRefreshUsesDailyNewProgressAndConfiguredGoal],
    ['saved learning survives native reminder synchronization failure', testSavedJudgmentSurvivesReminderSyncFailure]
  ];
  let failures = 0;
  for (const [name, test] of tests) {
    try { await test(); console.log(`PASS ${name}`); }
    catch (error) { failures++; console.error(`FAIL ${name}\n${error.stack}`); }
  }
  if (failures) { process.exitCode = 1; }
  else { console.log(`UI lifecycle: ${tests.length} real-component race checks passed.`); }
})();
