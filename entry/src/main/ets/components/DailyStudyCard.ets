import { StudyCardImageService } from '../service/StudyCardImageService';

@ComponentV2
export struct DailyStudyCard {
  @Param date: string = '';
  @Param newCount: number = 0;
  @Param reviewCount: number = 0;
  @Param minutes: number = 0;
  @Param cardId: string = 'lexiglow-today-study-card';
  @Local saving: boolean = false;
  @Local message: string = '';
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void { this.active = false; }

  private async save(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true;
    this.message = '';
    try {
      const saved = await StudyCardImageService.save(this.getUIContext(), this.cardId, this.date);
      if (this.active) { this.message = saved ? '今日学习卡片已保存' : ''; }
    } catch (_) { if (this.active) { this.message = '图片暂时无法保存，请重试'; } }
    finally { if (this.active) { this.saving = false; } }
  }

  @Builder
  private metric(value: number, label: string) {
    Column({ space: 6 }) {
      Text(`${Math.max(0, Math.floor(value))}`).fontSize(30).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
    }.layoutWeight(1)
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 22 }) {
        Row() {
          Text('今日学习卡片').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.date).fontSize(13).fontColor($r('app.color.text_secondary'))
        }.width('100%')
        Row() {
          this.metric(this.newCount, '新学单词')
          this.metric(this.reviewCount, '复习单词')
          this.metric(this.minutes, '学习分钟')
        }.width('100%')
        Text(this.newCount + this.reviewCount > 0 ? '每一次认真，都让单词再亮一点。' : '从一个单词开始，今天也可以亮起来。')
          .fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
        Row() {
          Text('词萤 LexiGlow').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Blank()
          Text(`今日 ${Math.max(0, this.newCount + this.reviewCount)} 次认真回忆`).fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }.width('100%')
      }.id(this.cardId).padding(24).width('100%').alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.glow')).borderRadius(24)
      Button(this.saving ? '正在保存…' : '保存图片').width('100%').height(46).enabled(!this.saving)
        .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
        .onClick(() => { this.save(); })
      if (this.message) {
        Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.width('100%')
  }
}
