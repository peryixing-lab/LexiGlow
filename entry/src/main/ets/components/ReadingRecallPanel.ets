import { Article } from '../model/ArticleModels';
import { ReadingProgress, ReadingQuestion } from '../model/ExperienceModels';
import { ExperienceService } from '../service/ExperienceService';

@ComponentV2
export struct ReadingRecallPanel {
  @Param article: Article = new Article();
  @Local answers: number[] = [];
  @Local completed: boolean = false;
  @Local busy: boolean = false;
  @Local ready: boolean = false;
  @Local error: string = '';
  private generation: number = 0;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }
  private async load(): Promise<void> {
    const generation = ++this.generation;
    try {
      const progress = await ExperienceService.getInstance().reading(this.article.id);
      if (generation !== this.generation) { return; }
      this.answers = this.article.questions.map((_question: ReadingQuestion, index: number) => progress.answers[index] ?? -1);
      this.completed = progress.completed; this.ready = true; this.error = '';
    } catch { if (generation === this.generation) { this.error = '阅读记录暂未载入'; } }
  }
  private allAnswered(): boolean { return this.answers.every((answer: number) => answer >= 0); }
  private correctCount(): number {
    return this.answers.filter((answer: number, index: number) => answer === this.article.questions[index].answer).length;
  }
  private async save(index: number = -1, option: number = -1): Promise<void> {
    if (this.busy || !this.ready) { return; }
    if (index >= 0 && this.answers[index] >= 0) { return; }
    if (index < 0 && !this.allAnswered()) { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    const answers = this.answers.slice(); if (index >= 0) { answers[index] = option; }
    try {
      const progress = await ExperienceService.getInstance().reading(this.article.id);
      progress.answers = answers; progress.completed = index < 0 || this.completed; progress.updatedAt = Date.now();
      await ExperienceService.getInstance().saveReading(progress);
      if (generation === this.generation) { this.answers = answers; this.completed = progress.completed; }
    } catch { if (generation === this.generation) { this.error = '这次阅读记录未保存，请再点一次重试。'; } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  build() {
    Column({ space: 16 }) {
      Text(this.article.questions.length > 0 ? '合上原文，回忆一下' : '读到这里，留下一点光').fontSize(22)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      if (this.ready) {
        ForEach(this.article.questions, (question: ReadingQuestion, index: number) => {
          Column({ space: 10 }) {
            Text(`${index + 1}. ${question.prompt}`).fontSize(17).lineHeight(27).fontColor($r('app.color.text_primary')).width('100%')
            ForEach(question.options, (option: string, optionIndex: number) => {
              Button(option, { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 48 }).padding(14).borderRadius(14)
                .backgroundColor(this.answers[index] === optionIndex ? $r('app.color.glow') : $r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).enabled(!this.busy && this.answers[index] < 0)
                .onClick(() => { this.save(index, optionIndex); })
            }, (option: string) => option)
            if (this.answers[index] >= 0) {
              Text(`${this.answers[index] === question.answer ? '答对了。' : '再看一眼：'}${question.explanation}`)
                .fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
            }
          }.width('100%')
        }, (question: ReadingQuestion) => question.prompt)
        if (this.completed) {
          Text(this.article.questions.length > 0 ? `这篇读完了 · 回忆答对 ${this.correctCount()} / ${this.article.questions.length}` : '这篇读完了，随时回来再读。')
            .fontSize(18).fontColor($r('app.color.success')).width('100%')
          Text('阅读与理解题独立记录，不增加背词完成数。').fontSize(12).fontColor($r('app.color.text_secondary'))
        } else {
          Button('完成这次阅读').height(50).width('100%').enabled(!this.busy && this.allAnswered())
            .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(() => { this.save(); })
        }
      }
      if (this.error) {
        Text(this.error).fontSize(14).fontColor($r('app.color.text_secondary'))
        if (!this.ready) { Button('重新载入').height(44).onClick(() => { this.load(); }) }
      }
    }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24).margin({ top: 24, bottom: 24 })
  }
}
