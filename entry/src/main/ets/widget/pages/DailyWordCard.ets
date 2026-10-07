const wordStorage = new LocalStorage();

@Entry(wordStorage)
@Component
struct DailyWordCard {
  @LocalStorageProp('word') word: string = '每天一点光';
  @LocalStorageProp('wordId') wordId: number = 0;
  @LocalStorageProp('meaning') meaning: string = '打开词萤，点亮第一个单词';
  @LocalStorageProp('progress') progress: string = '开始学习';

  build() {
    Column() {
      Row() {
        Text('词萤').fontSize(13).fontColor($r('app.color.text_secondary'))
        Blank()
        Text('✦').fontSize(17).fontColor($r('app.color.glow_deep'))
      }.width('100%')
      Column({ space: 6 }) {
        Text(this.word).fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.meaning).fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'word', wordId: this.wordId } });
      })
      Row() {
        Text('今日').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`${this.progress} →`).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.width('100%').height(32)
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { route: 'today' } });
      })
    }.width('100%').height('100%').padding(16).backgroundColor($r('app.color.background'))
  }
}
