import { common } from '@kit.AbilityKit';
import { Word } from '../model/AppModels';
import { AudioFlowService, AudioFlowState } from '../service/AudioFlowService';
import { audioCoreMeaning, audioEnglishExample, audioFlowQueue } from '../utils/AudioFlowUtils';
import { bottomContentOffset } from '../utils/SafeAreaUtils';
import { pageHorizontalPadding } from '../utils/ResponsiveLayout';

@ComponentV2
export struct AudioFlowPage {
  @Param words: Word[] = [];
  @Param topInset: number = 0;
  @Event onBack: () => void = () => {};
  @Local flow: AudioFlowState = new AudioFlowState();
  @Local pageWidth: number = 0;
  @Local pageHeight: number = 0;
  @Local available: Word[] = [];
  @Local pageError: string = '';
  private readonly service: AudioFlowService = AudioFlowService.getInstance();
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.available = audioFlowQueue(this.words);
    this.unsubscribe = this.service.subscribe((state: AudioFlowState) => { this.flow = state; });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) { this.unsubscribe(); this.unsubscribe = undefined; }
  }

  private currentWord(): Word {
    if (this.flow.status === 'idle') { return this.available.length > 0 ? this.available[0] : new Word(); }
    return this.flow.word;
  }

  private total(): number { return this.flow.status === 'idle' ? this.available.length : this.flow.total; }
  private playing(): boolean { return this.flow.status === 'playing'; }
  private busy(): boolean { return this.flow.status === 'preparing'; }
  private complete(): boolean { return this.flow.status === 'completed'; }
  private empty(): boolean { return this.total() === 0; }
  private compact(): boolean { return this.pageHeight > 0 && this.pageHeight < 620; }

  private stageLabel(): string {
    if (this.busy()) { return '正在准备离线语音'; }
    if (this.complete()) { return '这轮听词完成了'; }
    if (this.flow.status === 'paused') { return '已暂停 · 继续会重播当前片段'; }
    if (this.flow.status === 'error') { return '暂时无法继续收听'; }
    if (!this.playing()) { return '闭上眼睛，也能温习单词'; }
    if (this.flow.stage === 'recall') { return '留两秒，想一想它的意思'; }
    if (this.flow.stage === 'meaning') { return '正在朗读中文释义'; }
    if (this.flow.stage === 'example') { return '正在朗读英文例句'; }
    return '正在朗读英文单词';
  }

  private controlLabel(): string {
    if (this.busy()) { return '正在准备…'; }
    if (this.playing()) { return '暂停收听'; }
    if (this.flow.status === 'paused') { return '继续收听'; }
    if (this.complete()) { return '再听一轮'; }
    if (this.flow.status === 'error') { return '重试收听'; }
    return '开始收听';
  }

  private async control(): Promise<void> {
    if (this.busy() || this.empty()) { return; }
    this.pageError = '';
    if (this.playing()) { this.service.pause(); return; }
    try {
      if (this.flow.status === 'paused' || this.flow.status === 'error' || this.flow.status === 'completed') {
        await this.service.resume();
      } else {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        if (!context) { throw new Error('无法取得播放环境，请重新打开听词页面。'); }
        await this.service.start(this.available, context);
      }
    } catch (error) { this.pageError = (error as Error).message || '暂时无法收听，请重试。'; }
  }

  private async move(previous: boolean): Promise<void> {
    this.pageError = '';
    try { if (previous) { await this.service.previous(); } else { await this.service.next(); } }
    catch (error) { this.pageError = (error as Error).message || '暂时无法切换单词，请重试。'; }
  }

  private async stop(): Promise<void> {
    this.pageError = '';
    try { await this.service.stop(); }
    catch (error) { this.pageError = (error as Error).message || '停止播放失败，请重试。'; }
  }

  @Builder
  private wordCard() {
    Column({ space: this.compact() ? 12 : 20 }) {
      Text(this.stageLabel()).fontSize(14).fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center).width('100%').accessibilityLevel('yes')
      if (this.busy()) {
        LoadingProgress().width(32).height(32).color($r('app.color.success'))
      }
      Text(this.currentWord().word).fontFamily('serif').fontSize(this.compact() ? 36 : 46)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center).width('100%')
      if (this.currentWord().phonetic) {
        Text(this.currentWord().phonetic).fontSize(17).fontColor($r('app.color.text_secondary'))
      }
      if (this.flow.stage !== 'recall' || !this.playing()) {
        Text(audioCoreMeaning(this.currentWord().meaning)).fontSize(23).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
      } else {
        Text('想好之后，释义会自动读给你听。').fontSize(17).lineHeight(26)
          .fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Center)
      }
      if (this.flow.stage === 'example' && audioEnglishExample(this.currentWord().example)) {
        Text(audioEnglishExample(this.currentWord().example)).fontSize(17).lineHeight(28)
          .fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
      }
    }.width('100%').padding(this.compact() ? 24 : 34)
      .backgroundColor($r('app.color.surface')).borderRadius(28)
  }

  @Builder
  private controls() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('上一词', { type: ButtonType.Normal }).height(56).layoutWeight(1).borderRadius(18)
          .fontSize(16).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .enabled(!this.busy() && this.flow.status !== 'idle' && this.flow.index > 0)
          .accessibilityText('收听上一词').onClick(() => { this.move(true); })
        Button(this.controlLabel(), { type: ButtonType.Normal }).height(56).layoutWeight(1.5).borderRadius(18)
          .fontSize(17).fontWeight(FontWeight.Medium).backgroundColor($r('app.color.brand_ink'))
          .fontColor($r('app.color.inverse_text')).enabled(!this.busy() && !this.empty())
          .onClick(() => { this.control(); })
        Button('下一词', { type: ButtonType.Normal }).height(56).layoutWeight(1).borderRadius(18)
          .fontSize(16).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .enabled(!this.busy() && this.flow.status !== 'idle' && this.flow.index + 1 < this.flow.total)
          .accessibilityText('收听下一词').onClick(() => { this.move(false); })
      }.width('100%')
      if (this.service.isActive() || this.flow.status === 'error') {
        Button('结束收听', { type: ButtonType.Normal }).height(48).width('100%').borderRadius(18)
          .fontSize(16).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .accessibilityText('停止后台播放并结束收听').onClick(() => { this.stop(); })
      }
      if (this.flow.error || this.pageError) {
        Text(this.pageError || this.flow.error).fontSize(14).lineHeight(23)
          .fontColor($r('app.color.strength_low')).width('100%')
      }
    }.width('100%')
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: this.compact() ? 16 : 24 }) {
          Row() {
            Column({ space: 5 }) {
              Text('听词磨耳朵').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
              Text('AUDIO FLOW').fontSize(12).letterSpacing(2).fontColor($r('app.color.text_secondary'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button('返回', { type: ButtonType.Normal }).height(44).padding({ left: 18, right: 18 })
              .fontSize(15).borderRadius(16).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.text_primary')).onClick(this.onBack)
          }.width('100%')
          if (this.empty()) {
            Column({ space: 18 }) {
              Text('先选一些词，再戴上耳机。').fontSize(25).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary')).width('100%')
              Text(this.flow.error || '当前没有带中文释义的单词。选择词书或学习几个词后，再来开始收听。')
                .fontSize(16).lineHeight(27).fontColor($r('app.color.text_secondary')).width('100%')
              Button('返回选择单词', { type: ButtonType.Normal }).height(52).width('100%').borderRadius(18)
                .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text')).onClick(this.onBack)
            }.padding(26).width('100%').backgroundColor($r('app.color.surface')).borderRadius(28)
          } else {
            Row() {
              Text(this.flow.status === 'idle' ? `本轮 ${this.total()} 词` :
                `${this.complete() ? this.total() : this.flow.index + 1} / ${this.total()} 词`)
                .fontSize(15).fontColor($r('app.color.text_secondary'))
              Blank()
              Text('英文 → 回想 → 中文 → 例句').fontSize(12).fontColor($r('app.color.text_secondary'))
            }.width('100%')
            Progress({ value: this.complete() ? this.total() : this.flow.status === 'idle' ? 0 : this.flow.index,
              total: Math.max(1, this.total()), type: ProgressType.Linear })
              .color($r('app.color.success')).backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 4 })
            this.wordCard()
            this.controls()
            Text(this.complete() ? '这轮听词完成了。再见一次，就多一次巩固。' :
              '返回页面或熄屏后仍可收听，锁屏播控和耳机按键可暂停、切词。点击「结束收听」停止后台播放。')
              .fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
            Text('听词用于轻松温习，不计入今日学习任务。').fontSize(12)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }
        }.padding(pageHorizontalPadding(this.pageWidth)).width('100%').constraintSize({ maxWidth: 820 })
      }.width('100%').height('100%').contentStartOffset(56 + this.topInset)
        .contentEndOffset(bottomContentOffset(this.getUIContext()))
        .scrollBar(this.pageWidth >= 600 ? BarState.Auto : BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
      .onAreaChange((_old: Area, area: Area) => { this.pageWidth = Number(area.width); this.pageHeight = Number(area.height); })
  }
}
