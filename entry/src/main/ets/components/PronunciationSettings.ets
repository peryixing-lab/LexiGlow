import { AudioService } from '../service/AudioService';

@ComponentV2
export struct PronunciationSettings {
  @Local state: string = 'preparing';
  @Local message: string = '正在准备系统语音…';
  @Local canDownload: boolean = false;
  @Local downloading: boolean = false;
  private active: boolean = false;
  private requestVersion: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.downloading = false;
    this.prepare();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
  }

  private async prepare(): Promise<void> {
    const version = ++this.requestVersion;
    this.state = 'preparing';
    this.canDownload = false;
    this.message = '正在准备系统语音…';
    try {
      const status = await AudioService.getInstance().getEnglishVoiceStatus();
      if (!this.active || version !== this.requestVersion) { return; }
      this.state = status === 'installed' || status === 'compatible' || status === 'compatibleOnly' ? 'ready' : 'error';
      this.canDownload = status === 'downloadable' || status === 'compatible';
      if (status === 'installed') {
        this.message = '已使用华为 Core Speech Kit 英语音色，下载完成后可离线朗读。';
      } else if (status === 'compatible' || status === 'compatibleOnly') {
        this.message = '当前使用系统双语音色朗读。' +
          (this.canDownload ? '下载英语专用音色后，将优先使用英语音色。' : '当前设备暂未提供可下载的英语专用音色。');
      } else if (status === 'downloadable') {
        this.message = '英语音色尚未下载。点击下方按钮后由华为系统下载，完成后可离线朗读。';
      } else {
        this.message = '当前设备暂未提供可用语音，请检查系统语音服务或在支持的华为真机上使用。';
      }
    } catch (error) {
      if (this.active && version === this.requestVersion) {
        this.state = 'error';
        this.message = (error as Error).message || '系统语音暂未准备好，返回本页或再次朗读可重试。';
      }
    }
  }

  private async download(): Promise<void> {
    if (this.downloading || !this.canDownload) { return; }
    const version = ++this.requestVersion;
    this.downloading = true;
    this.message = '请在系统提示中确认下载英语音色，下载需要网络。';
    try {
      await AudioService.getInstance().installEnglishVoice();
      if (!this.active || version !== this.requestVersion) { return; }
      await this.prepare();
    } catch (error) {
      if (this.active && version === this.requestVersion) {
        this.state = 'error';
        this.message = (error as Error).message || '英语音色下载未完成，请重试。';
      }
    } finally {
      if (this.active) { this.downloading = false; }
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('单词朗读').fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(this.downloading ? '下载中' : this.state === 'preparing' ? '准备中' : this.state === 'ready' ? '已就绪' : '待处理')
          .fontSize(12).fontColor(this.state === 'ready' ? $r('app.color.success') : $r('app.color.text_secondary'))
      }.width('100%')
      Text(this.message).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.canDownload) {
        Button(this.downloading ? '正在等待系统下载…' : '下载英语音色')
          .width('100%').height(44).fontSize(14)
          .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
          .enabled(!this.downloading).onClick(() => { this.download(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
