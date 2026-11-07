import { common, UIExtensionContentSession } from '@kit.AbilityKit';
import { SharedWordService } from '../service/SharedWordService';

@Entry({ useSharedStorage: true })
@Component
struct SharedWordPage {
  @LocalStorageProp('sharedTitle') sharedTitle: string = '';
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

  private async importAsArticle(): Promise<void> {
    if (this.opening || !this.sharedText.trim()) { return; }
    this.opening = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIExtensionContext;
      await context.startAbility({
        bundleName: 'com.lovexjy.lexiglow', abilityName: 'EntryAbility',
        parameters: {
          route: 'sharedArticle',
          lexiglowSharedTitle: this.sharedTitle || '知萤联动笔记',
          lexiglowSharedArticle: this.sharedText
        }
      });
      await this.session?.terminateSelf();
    } catch (_) {
      this.message = '暂时无法打开词萤伴读，请稍后再试';
      this.opening = false;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('词萤收词与伴读').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('可提取英文单词加入生词本，或将整篇笔记导入词萤精读伴读').fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%')
      Scroll() {
        Column({ space: 12 }) {
          if (this.sharedTitle) {
            Text(this.sharedTitle).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
          }
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
      Button('导入到词萤伴读').width('100%').height(46)
        .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
        .enabled(!this.opening && this.sharedText.trim().length > 0)
        .onClick(() => { this.importAsArticle(); })
      Button('取消').width('100%').height(44).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary')).onClick(() => { this.session?.terminateSelf(); })
    }.padding(24).width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
