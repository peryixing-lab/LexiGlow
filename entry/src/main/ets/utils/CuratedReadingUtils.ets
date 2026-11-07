import { ReadingRecommendation } from '../model/ArticleModels';

export const READING_LEVELS: string[] = ['全部', '入门', '基础', '进阶'];
export const READING_TOPICS: string[] = ['全部', '生活', '校园', '工作'];

/** Internal editorial groups describe the text, not a measured learner ability. */
export function filterReadingRecommendations(items: ReadingRecommendation[], level: string,
  topic: string): ReadingRecommendation[] {
  return items.filter((item: ReadingRecommendation): boolean =>
    (level === '全部' || item.article.level === level) && (topic === '全部' || item.article.topic === topic));
}

export function readingRecommendationReason(item: ReadingRecommendation): string {
  if (item.reason) { return item.reason; }
  if (!item.completed && item.paragraphIndex > 0) { return '上次还没读完，可以从原来的段落接着读。'; }
  if (item.completed) { return '这篇已经读完，想再读时随时回来。'; }
  if (item.learnedCount > 0) { return `有 ${item.learnedCount} 个词形已有学习记录，可以在文章里再遇见它们。`; }
  return '从一小篇原创短文开始，遇到生词可以点按查义。';
}
