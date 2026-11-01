import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Word, WordEnrichment } from '../model/AppModels';
import { LearningService } from '../service/LearningService';

/** Read-only rehearsal. Timers stop whenever this destination or the ability becomes hidden. */
@ComponentV2
export struct QuietReviewPage {
  @Param words: Word[] = [];
  @Param mode: string = 'night';
  @Event onBack: () => void = () => {};
  @Local index: number = 0;
  @Local elapsed: number = 0;
  @Local complete: boolean = false;
  @Local paused: boolean = false;
  @Local interval: number = 30;
  @Local clock: string = '';
  @Local keepScreenOn: boolean = false;
  @Local enrichment: WordEnrichment = new WordEnrichment();
  private timer: number = -1;
  private active: boolean = false;
  private lastTick: number = 0;
  private elapsedBeforePause: number = 0;
  private appBackground: boolean = false;
  private destinationVisible: boolean = true;
  private screenRequest: number = 0;
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.appBackground = !visible;
    if (visible) { this.run(); }
    else { this.stopTimer(); }
  };

  aboutToAppear(): void {
    this.active = true;
    if (this.isNight()) { this.setNightTheme(true); }
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.loadHint();
    this.run();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.isNight()) { this.setNightTheme(false); }
    this.stopTimer();
    this.context().eventHub.off('appVisibility', this.visibilityListener);
    if (this.keepScreenOn) { this.setKeepScreen(false); }
  }

  private current(): Word { return this.words[this.index] || new Word(); }
  private isNight(): boolean { return this.mode === 'night'; }
  private setNightTheme(enabled: boolean): void {
    const preference = LearningService.getInstance().getSettings().themeMode;
    try {
      this.context().getApplicationContext().setColorMode(enabled || preference === 'dark' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK : preference === 'light' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch {}
  }
  private wordDuration(): number { return this.isNight() ? 30000 / Math.max(1, this.words.length) : this.interval * 1000; }

  private async loadHint(): Promise<void> {
    const id = this.current().id;
    this.enrichment = new WordEnrichment();
    if (!id) { return; }
    try {
      const hint = await LearningService.getInstance().getWordEnrichment(id);
      if (this.active && this.current().id === id) { this.enrichment = hint; }
    } catch {}
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      this.elapsedBeforePause += Date.now() - this.lastTick;
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private run(): void {
    if (!this.active || !this.destinationVisible || this.appBackground || this.paused || this.complete || this.words.length === 0 || this.timer >= 0) { return; }
    this.lastTick = Date.now();
    this.tick();
    if (!this.complete && this.active && this.destinationVisible && !this.appBackground && !this.paused) {
      this.timer = setInterval(() => { this.tick(); }, 250);
    }
  }

  private tick(): void {
    const now = Date.now();
    this.clock = `${new Date(now).getHours().toString().padStart(2, '0')}:${new Date(now).getMinutes().toString().padStart(2, '0')}`;
    const elapsed = this.elapsedBeforePause + now - this.lastTick;
    this.elapsed = elapsed;
    if (elapsed >= this.wordDuration()) {
      this.elapsedBeforePause = 0;
      this.lastTick = now;
      this.elapsed = 0;
      if (this.isNight() && this.index + 1 >= this.words.length) {
        this.complete = true;
        this.stopTimer();
      } else {
        this.index = (this.index + 1) % this.words.length;
        this.loadHint();
      }
    }
  }

  private togglePause(): void {
    this.paused = !this.paused;
    if (this.paused) { this.stopTimer(); }
    else { this.run(); }
  }

  private async setKeepScreen(value: boolean): Promise<void> {
    const request = ++this.screenRequest;
    try {
      const mainWindow = await window.getLastWindow(this.context());
      if (request !== this.screenRequest) { return; }
      await mainWindow.setWindowKeepScreenOn(value);
      if (value && !this.active) { await mainWindow.setWindowKeepScreenOn(false); return; }
      if (this.active) { this.keepScreenOn = value; }
    } catch {
      if (this.active) {
        this.keepScreenOn = false;
        this.getUIContext().getPromptAction().showToast({ message: '当前窗口暂时无法调整常亮设置。' });
      }
    }
  }

  private changeInterval(value: number): void {
    this.stopTimer();
    this.interval = value;
    this.elapsedBeforePause = 0;
    this.elapsed = 0;
    this.run();
  }

  build() {
    Scroll() {
      Column({ space: 24 }) {
        if (this.words.length === 0) {
          Text(this.isNight() ? '今天还没有需要复盘的词。' : '先学几个词，再开启静音伴读。')
            .fontSize(24).fontColor(this.isNight() ? '#E8ECE9' : $r('app.color.text_primary'))
        } else if (this.complete) {
          Text('今天的生词已温习完毕，晚安。').fontSize(26).lineHeight(40).fontColor('#E8ECE9')
          Button('回到首页').onClick(this.onBack).backgroundColor('#FFD45C').fontColor('#262D2A')
        } else {
          Text(this.isNight() ? `晚间复盘 · ${this.index + 1} / ${this.words.length}` : this.clock)
            .fontSize(this.isNight() ? 16 : 54).fontColor(this.isNight() ? '#A6ADA9' : $r('app.color.text_secondary'))
          Text(this.current().word).fontSize(48).fontFamily('serif').fontWeight(FontWeight.Medium)
            .fontColor(this.isNight() ? '#FFD45C' : $r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
          Text(this.current().phonetic).fontSize(18).fontColor(this.isNight() ? '#A6ADA9' : $r('app.color.text_secondary'))
          if (!this.isNight() || this.elapsed >= this.wordDuration() / 3) {
            Text(this.enrichment.coreMeanings.length > 0 ? this.enrichment.coreMeanings.join('；') : this.current().meaning)
              .fontSize(25).lineHeight(38).fontColor(this.isNight() ? '#E8ECE9' : $r('app.color.text_primary'))
              .width('100%').textAlign(TextAlign.Center)
          }
          if (this.isNight() && this.elapsed >= this.wordDuration() * 2 / 3) {
            Text(this.enrichment.analysis || this.current().example || '先回忆核心意思，让记忆慢慢亮起来。')
              .fontSize(16).lineHeight(27).fontColor('#A6ADA9').width('100%').textAlign(TextAlign.Center)
          }
          Progress({ value: this.elapsed, total: this.wordDuration(), type: ProgressType.Linear })
            .color(this.isNight() ? '#FFD45C' : $r('app.color.success')).width('100%')
          Button(this.paused ? '继续' : '暂停').height(48).backgroundColor(this.isNight() ? '#24282A' : $r('app.color.soft_surface'))
            .fontColor(this.isNight() ? '#E8ECE9' : $r('app.color.text_primary')).onClick(() => { this.togglePause(); })
          if (!this.isNight()) {
            Text('静音伴读 · 每词停留时间').fontColor($r('app.color.text_secondary'))
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
              ForEach([30, 60, 180, 300], (value: number) => {
                Button(value < 60 ? '30 秒' : `${value / 60} 分钟`).margin(4)
                  .backgroundColor(this.interval === value ? $r('app.color.glow') : $r('app.color.soft_surface'))
                  .fontColor($r('app.color.text_primary')).onClick(() => { this.changeInterval(value); })
              }, (value: number) => `${value}`)
            }.width('100%')
            Row({ space: 14 }) {
              Text('伴读期间保持屏幕常亮').fontColor($r('app.color.text_secondary'))
              Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn }).selectedColor($r('app.color.success'))
                .onChange((value: boolean) => { this.setKeepScreen(value); })
            }
          }
          Text(this.isNight() ? '只温习，不评分。30 秒后轻轻结束。' : '只展示已学词，不产生复习判断。')
            .fontSize(12).fontColor(this.isNight() ? '#A6ADA9' : $r('app.color.text_secondary'))
        }
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 28, right: 28, top: 86, bottom: 44 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor(this.isNight() ? '#1A1D1E' : $r('app.color.background'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => {
        this.destinationVisible = visible;
        if (visible) { this.run(); } else { this.stopTimer(); }
      })
  }
}
