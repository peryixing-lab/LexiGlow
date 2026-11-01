import { MistakeWord } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { dateKey } from '../utils/TimeUtils';

@ComponentV2
export struct MistakeBookPage {
  @Event onOpenWord: (id: number) => void = () => {};
  @Event onPractice: () => void = () => {};
  @Param visible: boolean = true;
  @Local words: MistakeWord[] = [];
  @Local loading: boolean = false;
  @Local hasMore: boolean = true;
  @Local error: string = '';
  private generation: number = 0;
  aboutToAppear(): void { this.load(true); }
  aboutToDisappear(): void { this.generation++; }
  @Monitor('visible')
  onVisible(): void { if (this.visible) { this.load(true); } else { this.generation++; this.loading = false; } }
  private async load(reset: boolean): Promise<void> {
    if (!reset && (this.loading || !this.hasMore)) { return; }
    const generation = ++this.generation;
    this.loading = true; this.error = '';
    const offset = reset ? 0 : this.words.length;
    try {
      const page = await LearningService.getInstance().getMistakes(offset);
      if (generation !== this.generation) { return; }
      this.words = reset ? page : this.words.concat(page); this.hasMore = page.length === 50;
    } catch (error) {
      if (generation === this.generation) { this.error = (error as Error).message || '错题暂未载入'; }
    } finally { if (generation === this.generation) { this.loading = false; } }
  }
  build() {
    Column({ space: 16 }) {
      Text('把容易忘的，再记牢一些。').fontSize(24).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      Text('按错误次数排序 · 强度达到 75 后自动移出。每次判断会更新日常复习安排。')
        .fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
      Button('开始错题练习 · 最多 20 词').height(48).width('100%')
        .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
        .enabled(!this.loading && this.words.length > 0).onClick(() => { this.onPractice(); })
      if (this.error) {
        Text(this.error).fontColor($r('app.color.text_secondary'))
        Button('重新载入').onClick(() => { this.load(true); })
      }
      List({ space: 10 }) {
        ForEach(this.words, (item: MistakeWord) => {
          ListItem() {
            Column({ space: 8 }) {
              Row() {
                Text(item.word.word).fontSize(21).fontWeight(FontWeight.Medium).layoutWeight(1)
                  .fontColor($r('app.color.text_primary'))
                Text(`错 ${item.wrongCount} 次`).fontSize(13).fontColor($r('app.color.text_secondary'))
              }.width('100%')
              Text(item.word.meaning).fontSize(15).maxLines(2).fontColor($r('app.color.text_secondary')).width('100%')
              Text(`强度 ${item.strength} · 上次判断 ${dateKey(item.lastReviewAt)}`)
                .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.surface'))
              .onClick(() => { this.onOpenWord(item.word.id); }).focusable(true)
          }
        }, (item: MistakeWord) => `${item.word.id}`)
        if (!this.loading && !this.error && this.words.length === 0) {
          ListItem() { Text('还没有需要集中巩固的词。继续按真实回忆判断就好。')
            .fontSize(16).lineHeight(26).fontColor($r('app.color.text_secondary')).padding(24) }
        }
        if (this.loading) { ListItem() { Text('正在载入…').fontColor($r('app.color.text_secondary')).padding(16) } }
        if (this.hasMore && !this.loading) {
          ListItem() { Button('载入更多').width('100%').onClick(() => { this.load(false); }) }
        }
      }.width('100%').layoutWeight(1).onReachEnd(() => { this.load(false); })
    }.padding({ left: 24, right: 24, top: 76, bottom: 24 }).width('100%').height('100%')
      .backgroundColor($r('app.color.background'))
  }
}
