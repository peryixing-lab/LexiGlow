/* Exercises the real route parser, Ability lifecycle methods and Index route handler.
 * System URI matching and actual UI rendering still need device verification. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT || path.join(
  process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents',
  'plugins/openharmony/ace-server/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
const read = name => fs.readFileSync(path.join(ets, name), 'utf8');
const transpile = source => ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
const routeExports = {};
new Function('exports', transpile(read('utils/LaunchRouteUtils.ets')))(routeExports);
const { TODAY_PLAN_DEEP_LINK, resolveLaunchRoute } = routeExports;
const drain = async () => { await new Promise(resolve => setImmediate(resolve)); };
let checks = 0;
const check = async (label, action) => { await action(); checks++; console.log(`PASS ${label}`); };

function makeAbility() {
  const storage = new Map(), events = [];
  const appStorage = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
  const shareExports = {};
  const shareSource = read('service/SharedWordService.ets').replace(/^import .*;\s*$/gm, '');
  new Function('exports', 'AppStorage', 'systemShare', transpile(shareSource))(
    shareExports, appStorage, { getSharedData: async want => ({ getRecords: () => [
      { utd: 'general.plain-text', content: want.testSharedText || '' }
    ] }) });
  const context = { eventHub: { emit: (...args) => events.push(args) },
    getApplicationContext: () => ({ setColorMode() {} }) };
  const stubs = {
    exports: {},
    UIAbility: class { constructor() { this.context = context; } },
    AudioService: { getInstance: () => ({ initialize() {} }) },
    SharedWordService: shareExports.SharedWordService,
    AppStorage: appStorage,
    ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } },
    resolveLaunchRoute
  };
  const source = read('entryability/EntryAbility.ets').replace(/^import .*;\s*$/gm, '');
  const names = Object.keys(stubs);
  new Function(...names, transpile(source))(...names.map(name => stubs[name]));
  return { ability: new stubs.exports.default(), storage, events };
}

function makeRouteHandler({ ready = true, onboarded = true, restoring = false } = {}) {
  const source = read('pages/Index.ets');
  const method = signature => {
    const start = source.indexOf(`  ${signature}`);
    assert.ok(start >= 0, signature);
    let end = source.indexOf('{', start), depth = 1;
    while (depth > 0) {
      const char = source[++end];
      assert.notEqual(char, undefined, 'method braces must balance');
      if (char === '{') { depth++; }
      if (char === '}') { depth--; }
    }
    return source.slice(start, end + 1);
  };
  const storage = new Map([['launchRoute', 'todayPlan']]);
  const effects = { started: [], stopped: 0, timerStops: 0, clears: 0, paths: [] };
  const stubs = {
    exports: {},
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    LiveStudyService: { getInstance: () => ({ stop: () => { effects.stopped++; } }) }
  };
  const names = Object.keys(stubs);
  const methods = [
    'handleRoute(route: string, wordId: number): void {',
    'dispatchInitialRoute(): void {',
    'async finishOnboarding(): Promise<void> {'
  ].map(method).join('\n');
  new Function(...names, transpile(`export class RouteHarness {\n${methods}\n}`))(
    ...names.map(name => stubs[name]));
  const handler = new stubs.exports.RouteHarness();
  Object.assign(handler, {
    ready, restoring, snapshot: { settings: { onboarded }, dailyWord: { id: 1 } }, tab: 3,
    busy: false, foundation: 'normal', selectedBook: 2, selectedTarget: 10,
    wordLoadVersion: 0, studyNavigationVersion: 0,
    stopQuickTimer: () => { effects.timerStops++; },
    beginStudy: mode => effects.started.push(mode),
    pathStack: {
      clear: () => { effects.clears++; effects.paths = []; },
      pushPathByName: (name, parameters) => effects.paths.push({ name, parameters })
    }
  });
  handler.copySettings = () => ({ ...handler.snapshot.settings });
  handler.service = { updateSettings: async settings => { handler.snapshot.settings = settings; } };
  handler.refresh = async () => {};
  handler.toast = message => { throw new Error(message); };
  return { handler, storage, effects };
}

(async () => {
  await check('only the supported plan URI is accepted', () => {
    assert.equal(resolveLaunchRoute(TODAY_PLAN_DEEP_LINK, 'quick'), 'todayPlan');
    const rejected = [
      'lexiglow://study/today', 'lexiglow://study/plan/', 'lexiglow://study/plan?route=quick',
      'lexiglow://study/plan#quick', 'lexiglow://study.example/plan', 'lexiglow://study:80/plan',
      'lexiglow://user@study/plan', 'lexiglow://study/%70lan', 'other://study/plan',
      'https://study/plan', ' lexiglow://study/plan', 'lexiglow://study/plan\n'
    ];
    for (const uri of rejected) { assert.equal(resolveLaunchRoute(uri, 'quick'), '', uri); }
    for (const route of ['word', 'shared', 'review', 'today', 'quick', 'audioFlow', 'night', 'desk']) {
      assert.equal(resolveLaunchRoute('', route), route, 'existing internal Wants retain route parameters');
    }
  });
  await check('cold launch stores the plan route for initialized UI', async () => {
    const { ability, storage, events } = makeAbility();
    ability.onCreate({ uri: TODAY_PLAN_DEEP_LINK, parameters: { route: 'quick', wordId: 9 } }, {});
    await drain();
    assert.equal(storage.get('launchRoute'), 'todayPlan');
    assert.equal(storage.get('launchWordId'), 0);
    assert.deepEqual(events, []);
  });
  await check('warm launch notifies the existing page with the plan route', async () => {
    const { ability, storage, events } = makeAbility();
    ability.onNewWant({ uri: TODAY_PLAN_DEEP_LINK }, {});
    await drain();
    assert.equal(storage.get('launchRoute'), 'todayPlan');
    assert.deepEqual(events, [['openRoute', 'todayPlan', 0]]);
  });
  await check('unknown URI cannot replace or dispatch a running route', async () => {
    const { ability, storage, events } = makeAbility();
    storage.set('launchRoute', 'word');
    ability.onNewWant({ uri: 'lexiglow://study/unknown', parameters: { route: 'quick' } }, {});
    await drain();
    assert.equal(storage.get('launchRoute'), 'word');
    assert.deepEqual(events, []);
  });
  await check('existing parameter and share Wants remain compatible', async () => {
    const { ability, storage, events } = makeAbility();
    ability.onNewWant({ parameters: { route: 'review', wordId: 7 } }, {});
    await drain();
    assert.deepEqual(events, [['openRoute', 'review', 7]]);
    events.length = 0;
    ability.onNewWant({ action: 'ohos.want.action.sendData', uri: 'file://shared.txt', testSharedText: 'apple' }, {});
    await drain();
    assert.equal(storage.get('launchRoute'), 'shared');
    assert.equal(storage.get('lexiglowSharedText'), 'apple');
    assert.deepEqual(events, [['openRoute', 'shared', 0]]);
    events.length = 0;
    ability.onNewWant({ parameters: { route: 'shared', lexiglowSharedText: 'pear' } }, {});
    await drain();
    assert.equal(storage.get('lexiglowSharedText'), 'pear');
    assert.deepEqual(events, [['openRoute', 'shared', 0]]);
  });
  await check('plan route opens the plan destination without creating a study session', () => {
    const { handler, storage, effects } = makeRouteHandler();
    handler.handleRoute('todayPlan', 0);
    assert.equal(handler.tab, 0);
    assert.deepEqual(effects.paths, [{ name: 'TodayPlan', parameters: '' }]);
    assert.deepEqual(effects.started, []);
    assert.equal(storage.get('launchRoute'), '');
  });
  await check('plan route waits for initialization and onboarding without clearing the current UI', () => {
    for (const condition of [{ ready: false }, { onboarded: false }, { restoring: true }]) {
      const { handler, storage, effects } = makeRouteHandler(condition);
      handler.dispatchInitialRoute();
      assert.equal(storage.get('launchRoute'), 'todayPlan');
      assert.equal(effects.clears, 0);
      assert.equal(effects.stopped, 0);
      assert.deepEqual(effects.started, []);
      handler.ready = true; handler.snapshot.settings.onboarded = true; handler.restoring = false;
      handler.dispatchInitialRoute();
      assert.deepEqual(effects.paths, [{ name: 'TodayPlan', parameters: '' }]);
    }
  });
  await check('finishing onboarding consumes the pending plan instead of starting onboarding study', async () => {
    const { handler, storage, effects } = makeRouteHandler({ onboarded: false });
    handler.dispatchInitialRoute();
    assert.equal(storage.get('launchRoute'), 'todayPlan');
    await handler.finishOnboarding();
    assert.equal(handler.snapshot.settings.onboarded, true);
    assert.equal(handler.busy, false);
    assert.equal(storage.get('launchRoute'), '');
    assert.deepEqual(effects.paths, [{ name: 'TodayPlan', parameters: '' }]);
    assert.deepEqual(effects.started, []);
  });
  await check('system declaration matches the configured platform link and preserves launcher skill', () => {
    const modulePath = path.join(root, 'entry/src/main/module.json5');
    const config = JSON.parse(fs.readFileSync(modulePath, 'utf8').replace(/,\s*([}\]])/g, '$1'));
    const ability = config.module.abilities.find(item => item.name === 'EntryAbility');
    assert.equal(ability.exported, true);
    assert.equal(ability.launchType, 'singleton');
    assert.ok(ability.skills.some(skill => skill.actions.includes('ohos.want.action.home')));
    const skill = ability.skills.find(item => item.actions.includes('ohos.want.action.viewData'));
    assert.ok(skill.entities.includes('entity.system.browsable'));
    assert.deepEqual(skill.uris, [{ scheme: 'lexiglow', host: 'study', path: 'plan' }]);
    assert.equal(`${skill.uris[0].scheme}://${skill.uris[0].host}/${skill.uris[0].path}`, TODAY_PLAN_DEEP_LINK);
  });
  console.log(`${checks} launch route checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
