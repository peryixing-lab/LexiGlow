import { common, UIExtensionContentSession } from '@kit.AbilityKit';
import { SharedWordService } from '../service/SharedWordService';

@Entry({ useSharedStorage: true })
@Component
struct SharedWordPage {
  @LocalStorageProp('sharedText') sharedText: string = '';
  @LocalStorageProp('shareSession') session: UIExtensionContentSession | undefined = undefined;
  @State opening: boolean = false;
  @State message: string = '';

  private async openPreview(): Promise<void> {
    if (this.opening || SharedWordService.wordsFromText(this.sharedText).length === 0) { return; }
    this.opening = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIExtensionContext;
      await context.startAbility({
        bundleName: 'com.lovexjy.lexiglow', abilityName: 'EntryAbility',
        parameters: { route: 'shared', lexiglowSharedText: this.sharedText }
      });
      await this.session?.terminateSelf();
    } catch (_) {
      this.message = '暂时无法打开词萤，请稍后再试';
      this.opening = false;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('词萤收词').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('先查看本地释义，再确认加入生词本').fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text(this.sharedText || '这次分享没有可识别的英文文本').fontSize(16)
            .fontColor($r('app.color.text_primary')).width('100%').copyOption(CopyOptions.InApp)
          Text(SharedWordService.wordsFromText(this.sharedText).join(' · ')).fontSize(14)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }.width('100%')
      }.layoutWeight(1).width('100%')
      if (this.message) {
        Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Button(this.opening ? '正在打开…' : '查看释义并收词').width('100%').height(48)
        .backgroundColor($r('app.color.glow_deep')).fontColor(Color.White)
        .enabled(!this.opening && SharedWordService.wordsFromText(this.sharedText).length > 0)
        .onClick(() => { this.openPreview(); })
      Button('取消').width('100%').height(44).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary')).onClick(() => { this.session?.terminateSelf(); })
    }.padding(24).width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
