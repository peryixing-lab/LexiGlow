import { curatedArticles } from '../data/CuratedArticles';
import { tokenizeArticleText, ArticleToken, articleParagraphs } from '../utils/ArticleTokenizer';
import { ExperienceService } from './ExperienceService';
import { common } from '@kit.AbilityKit';
import { Article, ArticleSummary, ReadingRecommendation } from '../model/ArticleModels';
import { Word } from '../model/AppModels';
import { DatabaseManager } from '../repository/DatabaseManager';
import { ArticleRepository } from '../repository/ArticleRepository';
import { articleWordCandidates } from '../utils/ArticleTokenizer';
import { LearningService } from './LearningService';

export class ArticleService {
  private static instance: ArticleService = new ArticleService();
  private repository: ArticleRepository | undefined = undefined;
  static getInstance(): ArticleService { return ArticleService.instance; }

  initialize(_context: common.Context, database: DatabaseManager): void {
    this.repository = new ArticleRepository(database);
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
      result.push(recommendation);
    }
    return result.sort((a: ReadingRecommendation, b: ReadingRecommendation) =>
      Number(a.completed) - Number(b.completed) || b.coverage - a.coverage || b.article.id - a.article.id);
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
    for (const candidate of articleWordCandidates(spelling)) {
      const word = await LearningService.getInstance().findWordBySpelling(candidate);
      if (word) { return word; }
    }
    return undefined;
  }

}
