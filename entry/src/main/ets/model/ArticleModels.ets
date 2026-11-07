import { ReadingQuestion } from './ExperienceModels';
export class ReadingWordNote {
  headword: string = '';
  example: string = '';
  translation: string = '';
  collocation: string = '';
}
export class ArticleSummary {
  id: number = 0;
  title: string = '';
  characterCount: number = 0;
  createdAt: number = 0;
}

export class Article extends ArticleSummary {
  body: string = '';
  questions: ReadingQuestion[] = [];
  source: string = '';
  level: string = '';
  topic: string = '';
  readingMinutes: number = 0;
  focusHeadwords: string[] = [];
  wordNotes: ReadingWordNote[] = [];
  personNames: string[] = [];
}

export class ArticleImport {
  title: string = '';
  body: string = '';
}

export class ReadingRecommendation {
  article: Article = new Article();
  learnedCount: number = 0;
  totalWords: number = 0;
  coverage: number = 0;
  focusWords: string[] = [];
  completed: boolean = false;
  paragraphIndex: number = 0;
  reason: string = '';
}
