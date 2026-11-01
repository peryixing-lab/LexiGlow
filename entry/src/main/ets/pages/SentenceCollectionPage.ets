import { SentenceMemory } from '../model/ExperienceModels';
import { ExperienceService } from '../service/ExperienceService';

@ComponentV2
export struct SentenceCollectionPage {
  @Event onWord: (wordId: number) => void = () => {};
  @Event onSource: (articleId: number, paragraphKey: string) => void = () => {};
  @Local memories: SentenceMemory[] = [];
  @Local error: string = '';
  @Local ready: boolean = false;
  @Local limit: number = 50;
  private generation: number = 0;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }
  private async load(): Promise<void> {
    const generation = ++this.generation;
    try { const memories = await ExperienceService.getInstance().sentences();
      if (generation === this.generation) { this.memories = memories; this.error = ''; this.ready = true; }
    } catch { if (generation === this.generation) { this.error = '原句暂未载入，请重试'; } }
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('在原句里，记住单词。').fontSize(25).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text('点开单词可以查看练习记录、编辑备注或整理原句。').fontSize(14).lineHeight(24)
          .fontColor($r('app.color.text_secondary')).width('100%')
        if (this.error) {
          Text(this.error).fontColor($r('app.color.text_secondary'))
          Button('重新载入').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.load(); })
        } else if (!this.ready) { LoadingProgress().width(36).height(36) }
        else if (this.memories.length === 0) {
          Text('还没有收藏原句。读文章时点一个词，留下它所在的那句话。').fontSize(17).lineHeight(28)
            .fontColor($r('app.color.text_secondary'))
        }
        ForEach(this.memories.slice(0, this.limit), (item: SentenceMemory) => {
          Column({ space: 12 }) {
            Text(item.sentence).fontSize(18).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
            Text(`来自「${item.articleTitle}」`).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            if (item.note) { Text(item.note).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%') }
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('查看单词与备注').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 8 }).onClick(() => { this.onWord(item.wordId); })
              if (item.articleId !== 0) {
                Button('回到原文').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ bottom: 8 }).onClick(() => { this.onSource(item.articleId, item.paragraphKey); })
              } else { Text('来源已删除，原句保留').fontSize(12).fontColor($r('app.color.text_secondary')) }
            }
          }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
        }, (item: SentenceMemory) => item.id)
        if (this.limit < this.memories.length) { Button('查看更多原句').height(48).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.limit += 50; }) }
      }.padding({ top: 76, bottom: 40, left: 24, right: 24 }).width('100%').constraintSize({ maxWidth: 800 })
    }.height('100%').width('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => { if (visible && this.ready) { this.load(); } })
  }
}
