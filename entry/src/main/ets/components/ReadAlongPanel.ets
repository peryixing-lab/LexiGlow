import { common } from '@kit.AbilityKit';
import { ReadAlongRecorderService } from '../service/ReadAlongRecorderService';

@ComponentV2
export struct ReadAlongPanel {
  @Param word: string = '';
  @Param visible: boolean = true;
  @Local permission: string = 'unknown';
  @Local status: string = 'idle';
  @Local hasRecording: boolean = false;
  @Local message: string = '';
  @Local seconds: number = 0;
  private recorder: ReadAlongRecorderService = new ReadAlongRecorderService();
  private active: boolean = false;
  private appVisible: boolean = true;
  private generation: number = 0;
  private clock: number = -1;
  private startedAt: number = 0;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.appVisible = visible;
    if (!visible) {
      this.recorder.stop().catch(() => {});
      this.recorder.stopPlayback().catch(() => {});
      this.clearClock();
    }
  };

  aboutToAppear(): void {
    this.active = true;
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.connectRecorder();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.generation++;
    this.clearClock();
    this.context().eventHub.off('appVisibility', this.visibilityListener);
    this.recorder.dispose().catch(() => {});
  }

  @Monitor('word', 'visible')
  private onTargetChanged(): void {
    this.generation++;
    this.clearClock();
    const previous = this.recorder;
    this.recorder = new ReadAlongRecorderService();
    this.status = 'idle';
    this.hasRecording = false;
    this.message = '';
    this.seconds = 0;
    if (this.permission === 'requesting') { this.permission = 'unknown'; }
    previous.dispose().catch(() => {});
    this.connectRecorder();
  }

  private connectRecorder(): void {
    const generation = this.generation;
    this.recorder.setListener((state: string, hasRecording: boolean, message: string): void => {
      if (!this.active || generation !== this.generation) { return; }
      this.status = state;
      this.hasRecording = hasRecording;
      this.message = message;
      this.clearClock();
      if (state === 'recording') {
        this.seconds = 0;
        this.startedAt = Date.now();
        this.clock = setInterval(() => {
          this.seconds = Math.min(10, Math.floor((Date.now() - this.startedAt) / 1000));
        }, 250);
      }
    });
  }

  private clearClock(): void { if (this.clock >= 0) { clearInterval(this.clock); this.clock = -1; } }
  private busy(): boolean {
    return this.status === 'starting' || this.status === 'recording' || this.status === 'stopping' ||
      this.status === 'playing' || this.status === 'original';
  }

  private async enable(): Promise<void> {
    if (this.permission === 'requesting' || !this.active || !this.visible) { return; }
    const generation = this.generation;
    this.permission = 'requesting';
    try {
      const granted = await this.recorder.requestPermission(this.context());
      if (!this.active || generation !== this.generation) { return; }
      this.permission = granted ? 'granted' : 'denied';
      this.message = granted ? '按住下方按钮跟读，松开结束' : '未开启麦克风权限，仍可正常查看和朗读单词';
    } catch (_) {
      if (!this.active || generation !== this.generation) { return; }
      this.permission = 'denied';
      this.message = '麦克风暂不可用，仍可正常查看和朗读单词';
    }
  }

  private begin(): void {
    if (!this.active || !this.visible || !this.appVisible || this.permission !== 'granted' || this.busy()) { return; }
    this.recorder.start(this.context()).catch(() => {});
  }

  private end(): void { this.recorder.stop().catch(() => {}); }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('跟读').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text('最长 10 秒').fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      Text('录音仅留在本机，离开单词详情即删除。').fontSize(13).lineHeight(21)
        .fontColor($r('app.color.text_secondary')).width('100%')
      if (this.permission === 'unknown' || this.permission === 'requesting') {
        Button(this.permission === 'requesting' ? '正在申请麦克风权限…' : '开启跟读')
          .width('100%').height(48).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.soft_surface'))
          .enabled(this.permission !== 'requesting').onClick(() => { this.enable(); })
      } else if (this.permission === 'granted') {
        Button(this.status === 'recording' ? `正在录音 ${this.seconds}s · 松开结束` :
          this.status === 'starting' ? '正在准备麦克风…' : this.status === 'stopping' ? '正在保存录音…' : '按住跟读')
          .width('100%').height(52).backgroundColor($r('app.color.glow')).fontColor($r('app.color.text_primary'))
          .accessibilityText('按住跟读，松开停止录音，最长十秒')
          .enabled(this.status !== 'stopping' && this.status !== 'playing' && this.status !== 'original')
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down) { this.begin(); }
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.end(); }
          })
        if (this.hasRecording && this.status !== 'recording' && this.status !== 'starting' && this.status !== 'stopping') {
          Row({ space: 10 }) {
            Button('听我的跟读').layoutWeight(1).height(46).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.text_primary')).enabled(!this.busy())
              .onClick(() => { this.recorder.play().catch(() => {}); })
            Button('原音 → 我的跟读').layoutWeight(1).height(46).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.text_primary')).enabled(!this.busy())
              .onClick(() => { this.recorder.play(this.word).catch(() => {}); })
          }.width('100%')
        }
        if (this.status === 'playing' || this.status === 'original') {
          Button(this.status === 'original' ? '正在播放原音 · 点击停止' : '正在回放跟读 · 点击停止')
            .width('100%').height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.success'))
            .onClick(() => { this.recorder.stopPlayback().catch(() => {}); })
        }
      }
      if (this.message) {
        Text(this.message).fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(22)
  }
}
