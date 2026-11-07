export class PracticeAttempt {
  id: string = '';
  wordId: number = 0;
  mode: string = 'meaning';
  correct: boolean = false;
  hinted: boolean = false;
  durationMs: number = 0;
  recordedAt: number = 0;
}

export class SentenceMemory {
  id: string = '';
  wordId: number = 0;
  articleId: number = 0;
  articleTitle: string = '';
  paragraphKey: string = '';
  sentence: string = '';
  note: string = '';
  createdAt: number = 0;
  targetText: string = '';
  targetStart: number = -1;
  recallEnabled: boolean = true;
}

export class SentenceRecallAttempt {
  id: string = '';
  sentenceId: string = '';
  correct: boolean = false;
  hinted: boolean = false;
  durationMs: number = 0;
  recordedAt: number = 0;
}

export class ReadingProgress {
  articleId: number = 0;
  paragraphIndex: number = 0;
  completed: boolean = false;
  answers: number[] = [];
  updatedAt: number = 0;
}

export class ReadingQuestion {
  prompt: string = '';
  options: string[] = [];
  answer: number = 0;
  explanation: string = '';
}

export class PracticeRecommendation {
  mode: string = '';
  title: string = '今天的一点光，已经留下。';
  reason: string = '可以安心收起手机，也可以去读一篇短文。';
  wordIds: number[] = [];
}

export class SkillEvidence {
  mode: string = '';
  label: string = '';
  total: number = 0;
  correct: number = 0;
  hinted: number = 0;
}
