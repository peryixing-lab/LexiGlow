const lockWordStorage = new LocalStorage();

/** Optional 1x2 lock screen form. Requires Huawei lock-screen entitlement before registration. */
@Entry(lockWordStorage)
@Component
struct LockScreenWordCard {
  @LocalStorageProp('word') word: string = '每天一点光';
  @LocalStorageProp('wordId') wordId: number = 0;
  @LocalStorageProp('phonetic') phonetic: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.word).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(this.phonetic || '词萤 · 让单词一点一点亮起来').fontSize(11).fontColor(Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }.width('100%').height('100%').padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center).backgroundColor(Color.Transparent)
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility',
          params: { route: 'word', wordId: this.wordId } });
      })
  }
}
