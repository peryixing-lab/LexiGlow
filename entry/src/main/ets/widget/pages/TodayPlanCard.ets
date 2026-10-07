const planStorage = new LocalStorage();

@Entry(planStorage)
@Component
struct TodayPlanCard {
  @LocalStorageProp('newDone') newDone: number = 0;
  @LocalStorageProp('newTarget') newTarget: number = 20;
  @LocalStorageProp('dueCount') dueCount: number = 0;
  @LocalStorageProp('estimatedMinutes') estimatedMinutes: number = 3;

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('词萤 · 今日计划').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text('✦').fontSize(18).fontColor($r('app.color.glow_deep'))
      }.width('100%')
      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text(`${this.newDone} / ${this.newTarget}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(`点亮新词 · 约 ${this.estimatedMinutes} 分钟`).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        .onClick(() => {
          postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'today' } });
        })
        Column({ space: 4 }) {
          Text(`${this.dueCount}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.success'))
          Text('到期复习 →').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.width(92).alignItems(HorizontalAlign.Start)
        .onClick(() => {
          postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'review' } });
        })
      }.width('100%').layoutWeight(1)
      Row() {
        Text('继续学习 →').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .height(32)
          .onClick(() => {
            postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'today' } });
          })
        Blank()
        Text('3 分钟速学').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .height(32).padding({ left: 12, right: 12 }).backgroundColor($r('app.color.glow')).borderRadius(16)
          .onClick(() => {
            postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'quick' } });
          })
      }.width('100%').height(32)
    }.width('100%').height('100%').padding(16).backgroundColor($r('app.color.background'))
  }
}
