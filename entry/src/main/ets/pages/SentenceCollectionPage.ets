import { SentenceMemory } from '../model/ExperienceModels';
import { ExperienceService } from '../service/ExperienceService';
import { LearningService } from '../service/LearningService';
import { hasSentenceTarget, sentenceTargetChoices, SentenceRecallTarget } from '../utils/SentenceRecallUtils';
import { PendingWordsPanel } from '../components/PendingWordsPanel';

@ComponentV2
export struct SentenceCollectionPage {
  @Event onWord: (wordId: number) => void = () => {};
  @Event onSource: (articleId: number, paragraphKey: string) => void = () => {};
  @Event onRecall: (sentenceIds: string[]) => void = () => {};
  @Param topInset: number = 0;
  @Local memories: SentenceMemory[] = [];
  @Local due: SentenceMemory[] = [];
  @Local error: string = '';
  @Local ready: boolean = false;
  @Local busy: boolean = false;
  @Local limit: number = 50;
  @Local queryText: string = '';
  @Local sourceFilter: string = '';
  @Local editingId: string = '';
  @Local targetQuery: string = '';
  @Local editingWord: string = '';
  private active: boolean = false;
  private generation: number = 0;
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; this.generation++; }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    try {
      const memories = await ExperienceService.getInstance().sentences();
      const due = await ExperienceService.getInstance().recallRecommendations();
      if (generation === this.generation) { this.memories = memories; this.due = due; this.error = ''; this.ready = true; }
    } catch { if (generation === this.generation) { this.error = '原句暂未载入，请重试'; } }
  }

  private filtered(): SentenceMemory[] {
    const query = this.queryText.trim().toLowerCase();
    return this.memories.filter((item: SentenceMemory): boolean => (!this.sourceFilter || item.articleTitle === this.sourceFilter) &&
      (!query || `${item.sentence}\n${item.note}\n${item.articleTitle}\n${item.targetText}`.toLowerCase().includes(query)));
  }

  private sourceOptions(): SelectOption[] {
    const titles = Array.from(new Set<string>(this.memories.map((item: SentenceMemory): string => item.articleTitle)));
    const options: SelectOption[] = [{ value: '全部来源' }];
    for (const title of titles) { options.push({ value: title }); }
    return options;
  }

  private choices(item: SentenceMemory): SentenceRecallTarget[] {
    const query = this.targetQuery.trim().toLowerCase();
    return sentenceTargetChoices(item.sentence).filter((target: SentenceRecallTarget): boolean =>
      !query || target.text.toLowerCase().includes(query)).slice(0, 40);
  }

  private hasTarget(item: SentenceMemory): boolean { return hasSentenceTarget(item); }

  private async editTarget(item: SentenceMemory): Promise<void> {
    this.editingId = this.editingId === item.id ? '' : item.id; this.targetQuery = ''; this.editingWord = '';
    if (!this.editingId) { return; }
    const generation = this.generation;
    try {
      const word = await LearningService.getInstance().getWord(item.wordId);
      if (generation === this.generation && this.editingId === item.id) { this.editingWord = word.word; }
    } catch { /* The saved sentence can still be confirmed if its dictionary entry is unavailable. */ }
  }

  private async updateMemory(item: SentenceMemory, target: SentenceRecallTarget | undefined = undefined): Promise<void> {
    if (this.busy) { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    const copy = JSON.parse(JSON.stringify(item)) as SentenceMemory;
    if (target) { copy.targetText = target.text; copy.targetStart = target.start; copy.recallEnabled = true; }
    else { copy.recallEnabled = !copy.recallEnabled; }
    try {
      await ExperienceService.getInstance().saveSentence(copy);
      if (generation === this.generation) { this.editingId = ''; await this.load(); }
    } catch { if (generation === this.generation) { this.error = '原句设置未能保存，请重试'; } }
    finally { if (this.active) { this.busy = false; } }
  }

  private practiceFiltered(): void {
    const ids = this.filtered().filter((item: SentenceMemory): boolean => this.hasTarget(item)).slice(0, 5)
      .map((item: SentenceMemory): string => item.id);
    if (ids.length > 0) { this.onRecall(ids); }
    else { this.error = '请先为一条原句确认要回忆的词，再开始练习。'; }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('在原句里，记住单词。').fontSize(25).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text('留下遇见它的那句话，也可以在另一天再回忆。原句练习独立记录，可随时跳过。')
          .fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
        PendingWordsPanel({ onChanged: () => { this.load(); } })
        if (this.due.length > 0) {
          Button(`今天可选的一小步 · 回忆 ${this.due.length} 条原句`).height(48).width('100%')
            .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).enabled(!this.busy)
            .onClick(() => { this.onRecall(this.due.map((item: SentenceMemory): string => item.id)); })
        }
        TextInput({ text: this.queryText, placeholder: '搜索原句、备注或来源' }).height(48)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
          .onChange((text: string) => { this.queryText = text; this.limit = 50; })
        Select(this.sourceOptions()).value(this.sourceFilter || '全部来源').fontColor($r('app.color.text_primary'))
          .onSelect((index: number) => { this.sourceFilter = index === 0 ? '' : String(this.sourceOptions()[index]?.value || ''); this.limit = 50; })
        Button('用筛选出的原句练习 · 最多 5 条').height(46).width('100%').enabled(!this.busy)
          .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.practiceFiltered(); })
        if (this.error) {
          Text(this.error).fontColor($r('app.color.text_secondary')).width('100%')
          Button('重新载入').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.load(); })
        }
        if (!this.ready) { LoadingProgress().width(36).height(36) }
        else if (this.memories.length === 0) {
          Text('还没有收藏原句。读文章时点一个词，留下它所在的那句话。').fontSize(17).lineHeight(28)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.filtered().length === 0) {
          Text('没有找到符合条件的原句，试试其他关键词或来源。').fontSize(16).lineHeight(26).fontColor($r('app.color.text_secondary'))
        }
        ForEach(this.filtered().slice(0, this.limit), (item: SentenceMemory) => {
          Column({ space: 12 }) {
            Text(item.sentence).fontSize(18).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
            Text(`来自「${item.articleTitle}」`).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            if (item.note) { Text(item.note).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%') }
            Text(this.hasTarget(item) ? `回忆词：${item.targetText} · ${item.recallEnabled ? '可推荐' : '已暂停推荐'}` : '这是一条旧收藏，确认目标词后才会进入原句回忆。')
              .fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('查看单词与备注').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 8 }).onClick(() => { this.onWord(item.wordId); })
              if (item.articleId !== 0) {
                Button('回到原文').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 8 }).onClick(() => { this.onSource(item.articleId, item.paragraphKey); })
              } else { Text('来源已删除，原句保留').fontSize(12).fontColor($r('app.color.text_secondary')) }
              if (this.hasTarget(item)) {
                Button('回忆这句').height(44).enabled(!this.busy).backgroundColor($r('app.color.glow')).fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 8 }).onClick(() => { this.onRecall([item.id]); })
                Button(item.recallEnabled ? '暂停推荐' : '恢复推荐').height(44).enabled(!this.busy).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 8 }).onClick(() => { this.updateMemory(item); })
              }
              Button(this.editingId === item.id ? '收起目标选择' : '确认回忆词').height(44).enabled(!this.busy).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ bottom: 8 }).onClick(() => { this.editTarget(item); })
            }
            if (this.editingId === item.id) {
              Text(`请选择当时要回忆的词${this.editingWord ? `（关联词条：${this.editingWord}）` : ''}。同词多次出现时，序号对应句内位置。更换目标会清除这句旧目标的回忆成绩。`)
                .fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
              TextInput({ text: this.targetQuery, placeholder: '筛选句中的英文词' }).height(46)
                .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                .onChange((text: string) => { this.targetQuery = text; })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.choices(item), (target: SentenceRecallTarget) => {
                  Button(`${target.text} · ${target.start + 1}`).height(44).enabled(!this.busy)
                    .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 8, bottom: 8 })
                    .onClick(() => { this.updateMemory(item, target); })
                }, (target: SentenceRecallTarget) => `${item.id}:${target.start}`)
              }
            }
          }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
        }, (item: SentenceMemory) => item.id)
        if (this.limit < this.filtered().length) {
          Button('查看更多原句').height(48).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.limit += 50; })
        }
      }.padding({ top: 76 + this.topInset, bottom: 40, left: 24, right: 24 }).width('100%').constraintSize({ maxWidth: 800 })
    }.height('100%').width('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => { if (visible && this.ready && !this.busy) { this.load(); } })
  }
}
