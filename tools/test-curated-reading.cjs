/* Executes the actual offline content and reading filters; no native UI mocks or source snapshots. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const sources = path.resolve(__dirname, '../entry/src/main/ets');
require.extensions['.ets'] = (module, filename) => {
  module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }, fileName: filename }).outputText, filename);
};
const { curatedArticles } = require(path.join(sources, 'data/CuratedArticles.ets'));
const { ReadingRecommendation } = require(path.join(sources, 'model/ArticleModels.ets'));
const { filterReadingRecommendations, readingRecommendationReason } = require(path.join(sources, 'utils/CuratedReadingUtils.ets'));
const { tokenizeArticleText, articleWordCandidates, articleParagraphs } = require(path.join(sources, 'utils/ArticleTokenizer.ets'));
const articles = curatedArticles();
let checks = 0;
const check = (label, run) => { run(); checks++; console.log(`PASS ${label}`); };

check('18 stable negative identities retain the original four texts and questions exactly', () => {
  assert.equal(articles.length, 18);
  assert.equal(new Set(articles.map(article => article.id)).size, 18);
  assert.deepEqual(articles.map(article => article.id), Array.from({ length: 18 }, (_, index) => -index - 1));
  const original = [
    '712631add635741c08f8f2fdad705f8524c3bc5535bca9d0bd58e67f6870125d',
    '7cd1745deeeb959973856c073b732c62f8e721b30ce770daefcb845e4e0211e5',
    'e0cb762d960885df0291d8c744ba4124c87eb7f957b68045a6ed246652ad1966',
    '0677f85f87a8d01fb6b99a65563f85bba221db50ef89bc32975affb9568601fb'
  ];
  articles.slice(0, 4).forEach((article, index) => {
    assert.equal(crypto.createHash('sha256').update(JSON.stringify([article.title, article.body, article.questions])).digest('hex'), original[index]);
  });
});

check('Every text is a bounded original short article with usable reading metadata', () => {
  assert.equal(new Set(articles.map(article => article.title)).size, 18);
  for (const article of articles) {
    const count = article.body.match(/[A-Za-z]+(?:'[A-Za-z]+)*/g).length;
    assert.ok(count >= 100 && count <= 220, `${article.title}: ${count} words`);
    assert.equal(article.characterCount, article.body.length);
    assert.equal(article.readingMinutes, Math.ceil(count / 100));
    assert.ok(['入门', '基础', '进阶'].includes(article.level));
    assert.ok(['生活', '校园', '工作'].includes(article.topic));
    assert.equal(article.source, '词萤原创 · 离线精选');
    assert.equal(articleParagraphs(article.body).length, 3, article.title);
    assert.ok(article.focusHeadwords.length >= 3);
    const tokens = tokenizeArticleText(article.body).filter(token => token.spelling);
    for (const word of article.focusHeadwords) {
      assert.ok(tokens.some(token => articleWordCandidates(token.spelling).includes(word)), `${article.title}: ${word} is not in its text`);
    }
  }
  for (const level of ['入门', '基础', '进阶']) assert.equal(articles.filter(article => article.level === level).length, 6);
  for (const topic of ['生活', '校园', '工作']) assert.equal(articles.filter(article => article.topic === topic).length, 6);
});

check('36 questions have distinct choices, valid answers and source evidence for every new text', () => {
  const answers = [0, 0, 0];
  for (const article of articles) {
    assert.equal(article.questions.length, 2, article.title);
    for (const question of article.questions) {
      assert.ok(question.prompt.trim());
      assert.equal(question.options.length, 3);
      assert.equal(new Set(question.options).size, 3);
      assert.ok(Number.isInteger(question.answer) && question.answer >= 0 && question.answer < 3);
      answers[question.answer]++;
      assert.ok(question.explanation.trim());
      if (article.id <= -5) {
        const [evidence, interpretation] = question.explanation.split('\n');
        assert.ok(article.body.includes(evidence), `${article.title}: quoted evidence is absent`);
        assert.ok(interpretation && /[\u3400-\u9fff]/.test(interpretation));
      }
    }
  }
  assert.ok(answers.every(count => count >= 8), `Unbalanced answer positions: ${answers}`);
});

check('All 54 reading word notes quote their story and include Chinese meaning support and collocations', () => {
  let count = 0;
  for (const article of articles) {
    assert.equal(article.wordNotes.length, article.focusHeadwords.length);
    assert.deepEqual(article.wordNotes.map(note => note.headword), article.focusHeadwords);
    for (const note of article.wordNotes) {
      assert.ok(article.body.includes(note.example), `${article.title}: ${note.headword} example is not from the text`);
      assert.ok(/[\u3400-\u9fff]/.test(note.translation), `${note.headword}: missing translation`);
      assert.ok(note.collocation.includes(' · '), `${note.headword}: missing collocation explanation`);
      count++;
    }
  }
  assert.equal(count, 54);
});

check('Explicit person-name lists describe actual people in each story and exclude generic capitalised words', () => {
  const generic = new Set(['When', 'At', 'On', 'One', 'He', 'She', 'They', 'It', 'Room', 'Six',
    'Monday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']);
  const names = new Set();
  for (const article of articles) {
    assert.ok(Array.isArray(article.personNames));
    assert.equal(new Set(article.personNames).size, article.personNames.length);
    for (const person of article.personNames) {
      assert.match(person, /^[A-Z][a-z]+$/);
      assert.ok(!generic.has(person), `${article.title}: generic word ${person} is not a declared person`);
      assert.ok(new RegExp(`\\b${person}(?:['’]s)?\\b`).test(article.body), `${article.title}: ${person} is absent`);
      names.add(person);
    }
  }
  assert.equal(names.size, 22);
  assert.deepEqual(articles.find(article => article.id === -15).personNames, []);
  assert.deepEqual(articles.find(article => article.id === -7).personNames, ['Nora']);
  assert.deepEqual(articles.find(article => article.id === -10).personNames, ['Rui', 'Mina', 'Tom']);
});

check('Level and topic filtering preserves recommendation order and never alters saved progress', () => {
  const recommendations = articles.map((article, index) => Object.assign(new ReadingRecommendation(), {
    article, completed: index % 3 === 0, paragraphIndex: index % 2, learnedCount: index, coverage: index * 3
  }));
  const before = JSON.stringify(recommendations);
  assert.deepEqual(filterReadingRecommendations(recommendations, '全部', '全部'), recommendations);
  for (const level of ['入门', '基础', '进阶']) {
    for (const topic of ['生活', '校园', '工作']) {
      const filtered = filterReadingRecommendations(recommendations, level, topic);
      assert.ok(filtered.length > 0, `${level}/${topic}`);
      assert.deepEqual(filtered, recommendations.filter(item => item.article.level === level && item.article.topic === topic));
    }
  }
  assert.equal(JSON.stringify(recommendations), before);
});

check('Reading explanations distinguish completed, resumable, learned and first-reading states', () => {
  const pick = Object.assign(new ReadingRecommendation(), { article: articles[0] });
  assert.match(readingRecommendationReason(pick), /点按查义/);
  pick.learnedCount = 6;
  assert.match(readingRecommendationReason(pick), /6 个词形已有学习记录/);
  pick.paragraphIndex = 1;
  assert.match(readingRecommendationReason(pick), /上次还没读完/);
  pick.completed = true;
  assert.match(readingRecommendationReason(pick), /已经读完/);
  pick.reason = '近期学过的词出现在这里。';
  assert.equal(readingRecommendationReason(pick), pick.reason);
});

console.log(`Verified ${checks} curated reading checks across ${articles.length} articles.`);
