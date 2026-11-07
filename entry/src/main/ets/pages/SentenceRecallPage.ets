import { common } from '@kit.AbilityKit';
import { SentenceMemory } from '../model/ExperienceModels';
import { ExperienceService, SentenceRecallJournal } from '../service/ExperienceService';
import { LearningService } from '../service/LearningService';
import { hasSentenceTarget, maskedMemorySentence, sentenceRecallMatches } from '../utils/SentenceRecallUtils';

@ComponentV2
export struct SentenceRecallPage {
  @Param sentenceIds: string[] = [];
  @Param visible: boolean = true;
  @Param topInset: number = 0;
  @Event onSource: (articleId: number, paragraphKey: string) => void = () => {};
  @Event onDone: () => void = () => {};
  @Local memories: SentenceMemory[] = [];
  @Local index: number = 0;
  @Local answer: string = '';
  @Local hintUsed: boolean = false;
  @Local meaningHint: string = '';
  @Local answered: boolean = false;
  @Local correct: boolean = false;
  @Local loading: boolean = true;
  @Local complete: boolean = false;
  @Local busy: boolean = false;
  @Local error: string = '';
  @Local saveError: string = '';
  @Local independentCorrect: number = 0;
  @Local hintedCorrect: number = 0;
  @Local answeredCount: number = 0;
  @Local skippedCount: number = 0;
  private active: boolean = false;
  private areaVisible: boolean = true;
  private appBackground: boolean = false;
  private generation: number = 0;
  private journal: SentenceRecallJournal = new SentenceRecallJournal();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private readonly visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.appBackground = !visible; this.updateClock();
  };

  aboutToAppear(): void {
    this.active = true;
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.load();
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++; this.journal.pause();
    this.context().eventHub.off('appVisibility', this.visibilityListener);
  }
  @Monitor('visible')
  visibilityChanged(): void { this.updateClock(); }

  private updateClock(): void {
    if (this.active && this.visible && this.areaVisible && !this.appBackground && !this.loading && !this.complete && !this.answered) {
      this.journal.resume();
    } else { this.journal.pause(); }
  }

  private current(): SentenceMemory { return this.memories[this.index] || new SentenceMemory(); }
  private masked(): string { return maskedMemorySentence(this.current()); }
  private canAnswer(): boolean {
    return this.active && this.visible && this.areaVisible && !this.appBackground && !this.loading && !this.complete && !this.busy;
  }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    this.loading = true; this.error = ''; this.memories = [];
    try {
      const memories = this.sentenceIds.length > 0 ? (await ExperienceService.getInstance().sentences())
        .filter((item: SentenceMemory): boolean => this.sentenceIds.includes(item.id) && hasSentenceTarget(item)).slice(0, 5) :
        await ExperienceService.getInstance().recallRecommendations();
      if (!this.active || generation !== this.generation) { return; }
      this.memories = memories; this.index = 0; this.complete = false;
      this.independentCorrect = 0; this.hintedCorrect = 0; this.answeredCount = 0; this.skippedCount = 0;
      await this.question(generation);
    } catch { if (this.active && generation === this.generation) { this.error = '原句暂未载入，请重试。'; } }
    finally { if (this.active && generation === this.generation) { this.loading = false; this.updateClock(); } }
  }

  private async question(generation: number = this.generation): Promise<void> {
    this.answer = ''; this.hintUsed = false; this.answered = false; this.correct = false;
    this.meaningHint = ''; this.saveError = ''; this.journal.beginQuestion(); this.journal.pause();
    if (!this.current().id) { return; }
    const sentenceId = this.current().id;
    try {
      const word = await LearningService.getInstance().getWord(this.current().wordId);
      if (this.active && generation === this.generation && this.current().id === sentenceId) { this.meaningHint = word.meaning; }
    } catch { /* First-letter hint remains available without a dictionary definition. */ }
    if (this.active && generation === this.generation && this.current().id === sentenceId) { this.updateClock(); }
  }

  private showHint(): void {
    if (!this.canAnswer() || this.answered) { return; }
    this.hintUsed = true;
  }

  private submit(): void {
    if (!this.canAnswer() || this.answered || !this.answer.trim()) { return; }
    this.correct = sentenceRecallMatches(this.current().targetText, this.answer);
    this.answered = true; this.answeredCount++;
    if (this.correct) {
      if (this.hintUsed) { this.hintedCorrect++; } else { this.independentCorrect++; }
    }
    this.journal.pause(); this.getUIContext().getFocusController().clearFocus(); this.saveEvidence();
  }

  private async saveEvidence(): Promise<void> {
    if (this.busy || !this.answered) { return; }
    const generation = this.generation; this.busy = true; this.saveError = '';
    try { await this.journal.record(this.current().id, this.correct, this.hintUsed, this.current().targetText, this.current().targetStart); }
    catch { if (this.active && generation === this.generation) { this.saveError = '这一题暂未保存，请重试后继续。'; } }
    finally { if (this.active && generation === this.generation) { this.busy = false; } }
  }

  private async next(skip: boolean = false): Promise<void> {
    if (!this.canAnswer() || this.busy || this.saveError || (!skip && !this.answered)) { return; }
    if (skip && this.answered) { return; }
    if (skip) { this.skippedCount++; }
    this.journal.pause(); this.getUIContext().getFocusController().clearFocus();
    if (this.index + 1 >= this.memories.length) { this.complete = true; return; }
    this.index++; this.loading = true;
    const generation = this.generation;
    await this.question(generation);
    if (this.active && generation === this.generation) { this.loading = false; this.updateClock(); }
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Text('把遇见的词，再想起来。').fontSize(25).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text('原句回忆可随时跳过；只记录这次作答，不增加每日背词任务。').fontSize(14).lineHeight(24)
          .fontColor($r('app.color.text_secondary')).width('100%')
        if (this.loading) {
          LoadingProgress().width(36).height(36)
        } else if (this.error) {
          Text(this.error).fontSize(16).fontColor($r('app.color.text_secondary'))
          Button('重新载入').height(48).backgroundColor($r('app.color.glow')).fontColor($r('app.color.text_primary')).onClick(() => { this.load(); })
        } else if (this.memories.length === 0) {
          Text('今天先按自己的节奏来。').fontSize(22).fontColor($r('app.color.text_primary')).width('100%')
          Text('没有待推荐的原句。新收藏从另一天开始推荐，每天最多 5 条；也可以在“我的原句”里确认目标词并手动选择。')
            .fontSize(16).lineHeight(27).fontColor($r('app.color.text_secondary')).width('100%')
          Button('返回').height(48).width('100%').backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(this.onDone)
        } else if (this.complete) {
          Text('这一轮原句回忆完成了。').fontSize(24).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
          Text(`作答 ${this.answeredCount} 句 · 跳过 ${this.skippedCount} 句\n无提示答对 ${this.independentCorrect} 句 · 提示后答对 ${this.hintedCorrect} 句`)
            .fontSize(18).lineHeight(30).fontColor($r('app.color.text_primary')).width('100%')
          Text('记得这次的原句词形，是一点具体的进步。它不代表已经完全掌握这个词。').fontSize(14).lineHeight(24)
            .fontColor($r('app.color.text_secondary')).width('100%')
          Button('完成').height(48).width('100%').backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(this.onDone)
        } else {
          Text(`${this.index + 1} / ${this.memories.length} · 填入原句中的完整词形`).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          Text(this.answered ? this.current().sentence : this.masked()).fontSize(23).lineHeight(38)
            .fontColor($r('app.color.text_primary')).width('100%')
          if (!this.answered) {
            TextInput({ text: this.answer, placeholder: '试着写出被遮住的词' }).height(54).maxLength(80)
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).enabled(!this.busy)
              .onChange((text: string) => { this.answer = text; }).onSubmit(() => { this.submit(); })
            if (this.hintUsed) {
              Text(`首字母：${this.current().targetText.slice(0, 1)} · ${this.current().targetText.length} 个字符${this.meaningHint ? `\n关联词条释义：${this.meaningHint}` : ''}`)
                .fontSize(15).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
              Text('请写出原句里的词形；提示后答对会单独记录。').fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary'))
            } else {
              Button('需要一点提示').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.showHint(); })
            }
            Button('确认答案').height(50).width('100%').enabled(this.answer.trim().length > 0 && !this.busy)
              .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(() => { this.submit(); })
            Button('跳过这句').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.next(true); })
          } else {
            Text(this.correct ? (this.hintUsed ? '借助提示，回忆出来了。' : '这次独立回忆出来了。') : `原句用的是 ${this.current().targetText}。下次再慢慢想起来。`)
              .fontSize(18).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
            Text(`来自「${this.current().articleTitle}」`).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            if (this.current().note) { Text(this.current().note).fontSize(15).lineHeight(25).fontColor($r('app.color.text_secondary')).width('100%') }
            if (this.busy) { Text('正在保存这一题…').fontSize(14).fontColor($r('app.color.text_secondary')) }
            if (this.saveError) {
              Text(this.saveError).fontColor($r('app.color.text_secondary')).width('100%')
              Button('重试保存').height(46).enabled(!this.busy).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.saveEvidence(); })
            }
            Button(this.index + 1 >= this.memories.length ? '查看本轮结果' : '下一句').height(50).width('100%').enabled(!this.busy && !this.saveError)
              .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(() => { this.next(); })
            if (this.current().articleId !== 0) {
              Button('回到原文').height(44).enabled(!this.busy && !this.saveError).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                .onClick(() => { this.journal.pause(); this.onSource(this.current().articleId, this.current().paragraphKey); })
            } else { Text('来源已删除，收藏的原句仍然保留。').fontSize(13).fontColor($r('app.color.text_secondary')) }
          }
        }
      }.width('100%').constraintSize({ maxWidth: 800 }).padding({ top: 76 + this.topInset, left: 24, right: 24, bottom: 40 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => { this.areaVisible = visible; this.updateClock(); })
  }
}
