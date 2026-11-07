import { curatedArticles } from '../data/CuratedArticles';
import { tokenizeArticleText, ArticleToken, articleParagraphs } from '../utils/ArticleTokenizer';
import { ExperienceService } from './ExperienceService';
import { common } from '@kit.AbilityKit';
import { Article, ArticleSummary, ReadingRecommendation } from '../model/ArticleModels';
import { Word } from '../model/AppModels';
import { DatabaseManager } from '../repository/DatabaseManager';
import { ArticleRepository } from '../repository/ArticleRepository';
import { readingRecommendationReason } from '../utils/CuratedReadingUtils';
import { LearningService } from './LearningService';

export class ArticleService {
  private static instance: ArticleService = new ArticleService();
  private repository: ArticleRepository | undefined = undefined;
  static getInstance(): ArticleService { return ArticleService.instance; }

  initialize(_context: common.Context, database: DatabaseManager): void {
    this.repository = new ArticleRepository(database,
      (spelling: string): string[] => LearningService.getInstance().lookupSpellings(spelling));
  }

  private getRepository(): ArticleRepository {
    if (!this.repository) { throw new Error('文章库尚未初始化，请重新打开词萤'); }
    return this.repository;
  }

  list(): Promise<ArticleSummary[]> { return this.getRepository().list(); }
  async get(id: number): Promise<Article | undefined> {
    return id < 0 ? curatedArticles().find((article: Article) => article.id === id) : this.getRepository().get(id);
  }

  async recommendations(): Promise<ReadingRecommendation[]> {
    const result: ReadingRecommendation[] = [];
    let latestTopic: string = ''; let latestCompletedAt: number = 0;
    for (const article of curatedArticles()) {
      const recommendation = new ReadingRecommendation(); recommendation.article = article;
      const words = Array.from(new Set<string>(tokenizeArticleText(article.body)
        .filter((token: ArticleToken) => token.spelling.length > 0).map((token: ArticleToken) => token.spelling)));
      const learned = await this.getRepository().learnedSpellings(words);
      recommendation.totalWords = words.length; recommendation.learnedCount = learned.length;
      recommendation.coverage = words.length > 0 ? Math.round(learned.length / words.length * 100) : 0;
      recommendation.focusWords = words.filter((word: string) => learned.indexOf(word) < 0).filter((word: string) => word.length > 4).slice(0, 3);
      const progress = await ExperienceService.getInstance().reading(article.id);
      recommendation.completed = progress.completed; recommendation.paragraphIndex = progress.paragraphIndex;
      recommendation.reason = readingRecommendationReason(recommendation);
      if (progress.completed && progress.updatedAt > latestCompletedAt) {
        latestTopic = article.topic; latestCompletedAt = progress.updatedAt;
      }
      result.push(recommendation);
    }
    const levels = ['入门', '基础', '进阶'];
    return result.sort((a: ReadingRecommendation, b: ReadingRecommendation) =>
      Number(a.completed) - Number(b.completed) ||
      Number(b.paragraphIndex > 0 && !b.completed) - Number(a.paragraphIndex > 0 && !a.completed) ||
      Math.floor(b.coverage / 10) - Math.floor(a.coverage / 10) ||
      Number(a.article.topic === latestTopic) - Number(b.article.topic === latestTopic) ||
      levels.indexOf(a.article.level) - levels.indexOf(b.article.level) || b.coverage - a.coverage ||
      b.article.id - a.article.id);
  }

  async savePosition(articleId: number, paragraphIndex: number): Promise<void> {
    const article = await this.get(articleId); if (!article) { return; }
    await ExperienceService.getInstance().savePosition(articleId,
      Math.max(0, Math.min(articleParagraphs(article.body).length - 1, paragraphIndex)));
  }
  save(title: string, body: string): Promise<number> { return this.getRepository().save(title, body); }
  remove(id: number): Promise<void> { return this.getRepository().remove(id); }
  paragraphStrengths(spellings: string[]): Promise<Map<string, number>> {
    return this.getRepository().paragraphStrengths(spellings);
  }

  async lookup(spelling: string): Promise<Word | undefined> {
    return (await this.lookupCandidates(spelling))[0];
  }

  lookupCandidates(spelling: string): Promise<Word[]> {
    return LearningService.getInstance().lookupCandidates(spelling);
  }

}
