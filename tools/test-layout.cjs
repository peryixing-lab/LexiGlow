/* Test real ArkTS layout helpers against card geometry and resize scenarios. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const deveco = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  path.join(deveco, 'plugins/openharmony/ace-server/node_modules/typescript'));
const filename = path.resolve(__dirname, '../entry/src/main/ets/utils/ResponsiveLayout.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
  fileName: filename
});
const layoutModule = new Module(filename, module);
layoutModule.filename = filename;
layoutModule._compile(compiled.outputText, filename);
const { PAGE_MAX_WIDTH, pageHorizontalPadding, primaryNavigationRailWidth,
  responsiveColumnCount, responsiveCardWidth, usesTopNavigation } = layoutModule.exports;

const policies = [
  { name: 'books', minimum: 320, maximum: 3, gap: 12 },
  { name: 'statistics/profile', minimum: 300, maximum: 2, gap: 16 },
  { name: 'learned words', minimum: 320, maximum: 3, gap: 14 }
];
const epsilon = 1e-7;
let checks = 0;
function check(label, action) {
  action();
  checks++;
  console.log(`PASS ${label}`);
}

function cardGeometry(contentWidth, policy) {
  const columns = responsiveColumnCount(contentWidth, policy.minimum, policy.maximum, policy.gap);
  const cardWidth = responsiveCardWidth(contentWidth, columns, policy.gap);
  const occupied = columns * cardWidth + (columns - 1) * policy.gap;
  const label = `${policy.name}, content ${contentWidth}vp`;
  assert.ok(Number.isInteger(columns) && columns >= 1 && columns <= policy.maximum, label);
  assert.ok(Number.isFinite(cardWidth) && cardWidth >= 0, label);
  assert.ok(occupied <= contentWidth + epsilon, `${label}: row overflows`);
  assert.ok(Math.abs(occupied - contentWidth) < epsilon, `${label}: row leaves avoidable space`);
  if (columns > 1) {
    assert.ok(cardWidth + epsilon >= policy.minimum, `${label}: cards become too narrow`);
  }
  if (columns < policy.maximum) {
    const nextRowMinimum = (columns + 1) * policy.minimum + columns * policy.gap;
    assert.ok(contentWidth < nextRowMinimum, `${label}: an additional readable column fits`);
  }
  return { columns, cardWidth };
}

// Large-device tabs and word destinations receive the full window width;
// other devices retain their existing navigation rail at 840vp.
function windowGeometry(windowWidth, policy, deviceType = '2in1') {
  const rail = policy.name !== 'learned words' ? primaryNavigationRailWidth(windowWidth, deviceType) : 0;
  const paneWidth = windowWidth - rail;
  const padding = pageHorizontalPadding(paneWidth);
  const contentWidth = Math.max(0, Math.min(paneWidth, PAGE_MAX_WIDTH) - padding * 2);
  return { paneWidth, padding, contentWidth, ...cardGeometry(contentWidth, policy) };
}

check('phone, tablet and 2in1 panes fit every card policy', () => {
  assert.equal(PAGE_MAX_WIDTH, 1600, 'wide dashboards retain the agreed 1600vp page width');
  const windows = [
    ['small phone', 320, 'phone'], ['phone', 390, 'phone'], ['phone landscape', 780, 'phone'],
    ['tablet portrait', 768, 'tablet'], ['tablet landscape', 1280, 'tablet'],
    ['2in1 window', 1024, '2in1'], ['2in1 fullscreen', 1920, '2in1'], ['wide desktop', 2560, '2in1']
  ];
  for (const [name, width, deviceType] of windows) {
    for (const policy of policies) {
      const result = windowGeometry(width, policy, deviceType);
      assert.ok(result.contentWidth + result.padding * 2 <= result.paneWidth + epsilon, name);
      assert.ok(result.contentWidth + result.padding * 2 <= PAGE_MAX_WIDTH + epsilon, name);
    }
  }
});

check('top navigation transition preserves the full tablet and 2in1 content width', () => {
  for (const deviceType of ['tablet', '2in1']) {
    for (const width of [839, 840, 841]) {
      assert.equal(usesTopNavigation(width, deviceType), width >= 840);
      for (const policy of policies.slice(0, 2)) {
        const result = windowGeometry(width, policy, deviceType);
        assert.equal(result.paneWidth, width);
        assert.equal(result.contentWidth, width - 48);
      }
    }
  }
  for (const deviceType of ['phone', 'wearable', 'unknown']) {
    assert.equal(usesTopNavigation(1920, deviceType), false);
    assert.equal(primaryNavigationRailWidth(839, deviceType), 0);
    assert.equal(primaryNavigationRailWidth(840, deviceType), 104);
  }
});

check('known 49% plus 16vp small-window overflow is eliminated', () => {
  const contentWidth = 672;
  assert.ok(contentWidth * 0.49 * 2 + 16 > contentWidth, 'fixture reproduces the old wrapped half-card');
  const result = cardGeometry(contentWidth, policies[1]);
  assert.equal(result.columns, 2);
  assert.ok(Math.abs(result.cardWidth * 2 + 16 - contentWidth) < epsilon);
});

check('proportionally smaller fullscreen windows select readable 3, 2 and 1 columns', () => {
  // 1920x1080 -> 960x540 -> 640x360: aspect ratio is unchanged.
  for (const policy of policies.filter(item => item.maximum === 3)) {
    assert.deepEqual([1920, 960, 640].map(width => windowGeometry(width, policy).columns), [3, 2, 1]);
  }
  assert.deepEqual([1920, 960, 640].map(width => windowGeometry(width, policies[1]).columns), [2, 2, 1]);
});

check('column transitions preserve minimum card width, including fractional vp', () => {
  for (const policy of policies) {
    for (let nextColumns = 2; nextColumns <= policy.maximum; nextColumns++) {
      const requiredWidth = nextColumns * policy.minimum + (nextColumns - 1) * policy.gap;
      assert.equal(cardGeometry(requiredWidth - 0.01, policy).columns, nextColumns - 1);
      assert.equal(cardGeometry(requiredWidth, policy).columns, nextColumns);
      cardGeometry(requiredWidth + 0.01, policy);
    }
    for (let width = 0; width <= 2600; width += 7.25) {
      cardGeometry(width, policy);
    }
  }
});

check('page gutters change at 360vp and 1200vp without overflowing rows', () => {
  for (const [width, padding] of [[320, 16], [359.99, 16], [360, 24], [1199.99, 24], [1200, 32], [1200.01, 32]]) {
    assert.equal(pageHorizontalPadding(width), padding, `${width}vp gutter`);
    for (const policy of policies) {
      cardGeometry(Math.min(width, PAGE_MAX_WIDTH) - padding * 2, policy);
    }
  }
});

check('resize out and back returns identical geometry', () => {
  const widths = [320, 360, 600, 839, 840, 841, 960, 1199, 1200, 1303, 1304, 1600, 1920, 2560];
  for (const policy of policies) {
    const firstPass = new Map(widths.map(width => [width, windowGeometry(width, policy)]));
    for (const width of [...widths].reverse().concat(widths)) {
      assert.deepEqual(windowGeometry(width, policy), firstPass.get(width), `${policy.name}, ${width}vp`);
    }
  }
});

console.log(`${checks} layout checks passed.`);
