import { Article } from '../model/ArticleModels';
import { ReadingQuestion } from '../model/ExperienceModels';

function readingQuestion(prompt: string, options: string[], answer: number, explanation: string): ReadingQuestion {
  const question = new ReadingQuestion(); question.prompt = prompt; question.options = options;
  question.answer = answer; question.explanation = explanation; return question;
}

function readingArticle(id: number, title: string, body: string, questions: ReadingQuestion[]): Article {
  const article = new Article(); article.id = id; article.title = title; article.body = body;
  article.characterCount = body.length; article.source = '词萤原创 · 离线精选'; article.questions = questions;
  return article;
}

/** Stable negative IDs reserve positive IDs for user imports. Text and questions are authored for LexiGlow. */
export function curatedArticles(): Article[] {
  return [
    readingArticle(-1, '雨天的一把伞',
      'When Mia left the library, rain was falling across the quiet street. She opened her bag and found a notebook, two apples, and a small blue umbrella. A boy stood near the door. He looked at the rain and then at his watch.\n\nMia asked where he was going. His bus stop was just around the corner, on her way home. She offered to share her umbrella. They walked slowly because the path was wet. The boy carried her books so she could hold the umbrella more easily.\n\nAt the bus stop, he thanked her and smiled. Mia still had a long walk ahead, but she no longer minded the weather. A small act of kindness had made an ordinary afternoon feel warmer.',
      [readingQuestion('男孩要去哪里？', ['图书馆', '公交站', '商店'], 1, 'His bus stop was just around the corner. 他要去附近的公交站。'),
       readingQuestion('男孩怎样帮助 Mia？', ['替她拿书', '给她一个苹果', '为她买伞'], 0, 'The boy carried her books. 他替 Mia 拿书，让她更方便撑伞。')]),
    readingArticle(-2, '给自己留十分钟',
      'Every morning, Daniel checked his phone before getting out of bed. Messages and news filled his mind before the day had really begun. He often arrived at work feeling tired, although he had slept well.\n\nOne Sunday, he decided to try a different routine. He put his phone on a shelf outside the bedroom and placed a book beside his bed. The next morning, he read for ten minutes while drinking a glass of water. Nothing urgent happened during that short break.\n\nAfter a week, Daniel did not feel like a completely different person. He still had busy days and difficult tasks. However, those quiet minutes gave him a little space to choose how to begin. He kept the habit because it was simple enough to repeat.',
      [readingQuestion('Daniel 把手机放在哪里？', ['床边', '办公室', '卧室外的架子上'], 2, 'He put his phone on a shelf outside the bedroom.'),
       readingQuestion('他为什么保留这个习惯？', ['它很简单，容易重复', '它让所有工作消失', '他从此不用手机'], 0, 'He kept the habit because it was simple enough to repeat.')]),
    readingArticle(-3, '阳台上的第一片叶子',
      'Lena wanted to grow vegetables, but her apartment had no garden. Her neighbor suggested starting with a pot on the balcony. She chose some seeds, filled the pot with soil, and placed it where it could receive morning sunlight.\n\nFor several days, nothing seemed to happen. Lena watered the soil and wondered whether she had made a mistake. She nearly bought a new packet of seeds. Her neighbor reminded her that growth often begins where we cannot see it.\n\nOn Saturday, a tiny green leaf appeared. It was smaller than her fingernail, yet it changed the way she looked at the pot. Over the following weeks, she learned to notice small changes instead of expecting a harvest immediately. Caring for the plant became a quiet part of her day.',
      [readingQuestion('Lena 在哪里种植物？', ['公园里', '阳台的花盆里', '邻居的花园里'], 1, 'Her neighbor suggested starting with a pot on the balcony.'),
       readingQuestion('她后来学会了什么？', ['每天更换种子', '立刻收获蔬菜', '留意微小的变化'], 2, 'She learned to notice small changes instead of expecting a harvest immediately.')]),
    readingArticle(-4, '修好一盏旧台灯',
      'A small repair shop opened beside the market last month. Instead of selling new products, it invited people to bring things that no longer worked. On the first Saturday, Omar arrived with an old desk lamp. It had belonged to his grandfather.\n\nA volunteer examined the lamp and found a damaged wire. She explained each step while replacing it. Omar asked questions and helped hold the lamp steady. When the light finally came on, several people at the next table smiled.\n\nThe repair took less than an hour. Omar paid for the wire and left a small donation for the shop. He had saved more than the cost of a new lamp. He had also kept an object connected to his family and learned that some broken things deserve another chance.',
      [readingQuestion('台灯的什么部分坏了？', ['灯罩', '电线', '桌子'], 1, 'A volunteer examined the lamp and found a damaged wire.'),
       readingQuestion('这盏灯为什么对 Omar 特别？', ['它属于他的祖父', '它是全新的', '它是商店的奖品'], 0, 'It had belonged to his grandfather. 它承载着家人的记忆。')])
  ];
}
