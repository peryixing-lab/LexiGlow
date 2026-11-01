import { PracticeJournal } from '../service/ExperienceService';
import { common } from '@kit.AbilityKit';
import { Word, PracticeResult } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { shuffledLetters, spellingHint, spellingMatches, dictationMatches } from '../utils/SpellingUtils';
import { HapticService } from '../service/HapticService';
import { AudioService } from '../service/AudioService';
import { PronunciationPresenter } from '../service/PronunciationPresenter';
import { PracticeClock } from '../utils/PracticeClock';

@ComponentV2
export struct SpellingChallengePage {
  @Param initialMode: string = 'spelling';
  @Param preferredIds: number[] = [];
  @Local evidenceBusy: boolean = false;
  @Local evidenceError: string = '';
  private journal: PracticeJournal = new PracticeJournal();
  @Param topInset: number = 0;
  @Local mode: string = 'spelling';
  @Local pronunciationMessage: string = '';
  @Local words: Word[] = [];
  @Local index: number = 0;
  @Local answer: string = '';
  @Local letters: string[] = [];
  @Local used: number[] = [];
  @Local correctCount: number = 0;
  @Local answered: boolean = false;
  @Local hintUsed: boolean = false;
  @Local correct: boolean = false;
  @Local complete: boolean = false;
  @Local loading: boolean = true;
  @Local remaining: number = 90;
  @Local error: string = '';
  @Local historyError: string = '';
  @Local saved: boolean = false;
  @Local results: PracticeResult[] = [];
  private active: boolean = false;
  private timer: number = -1;
  private readonly clock: PracticeClock = new PracticeClock();
  private readonly pronunciation: PronunciationPresenter = new PronunciationPresenter();
  private version: number = 0;
  @Local saving: boolean = false;
  private destinationVisible: boolean = true;
  private appBackground: boolean = false;
  private service: LearningService = LearningService.getInstance();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.appBackground = !visible;
    if (visible && !this.loading) { this.runTimer(); } else { this.pause(); }
  };

  aboutToAppear(): void {
    this.active = true;
    this.mode = this.initialMode === 'dictation' ? 'dictation' : 'spelling';
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.start();
  }
  aboutToDisappear(): void {
    this.active = false; this.version++; this.pause();
    this.context().eventHub.off('appVisibility', this.visibilityListener);
  }

  private clearTimer(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
  }

  private cancelAudio(): void {
    this.pronunciation.cancel();
    AudioService.getInstance().stop();
  }

  private pause(): void {
    this.clearTimer();
    this.clock.pause();
    this.journal.pause();
    this.cancelAudio();
  }

  private switchMode(mode: string): void {
    if (this.mode === mode || this.loading || this.saving || this.evidenceBusy || !!this.evidenceError) { return; }
    this.mode = mode;
    this.start();
  }

  private async pronounce(): Promise<void> {
    const version = this.version;
    const index = this.index;
    this.cancelAudio();
    await this.pronunciation.play(this.current().word, this.getUIContext(),
      (): boolean => this.active && this.destinationVisible && !this.appBackground && !this.complete &&
        version === this.version && index === this.index,
      (_state: string, message: string): void => { this.pronunciationMessage = message; });
  }

  private async start(): Promise<void> {
    if (this.saving || this.evidenceBusy || !!this.evidenceError) { return; }
    const version = ++this.version;
    this.pause();
    this.loading = true;
    this.error = '';
    this.historyError = '';
    try {
      const words = this.preferredIds.length > 0 ? await this.service.getTargetedWords(this.preferredIds) : await this.service.getSpellingWords(30);
      if (!this.active || version !== this.version) { return; }
      this.words = words.filter((word: Word) => /^[a-z]{3,30}$/i.test(word.word)).slice(0, 5);
      this.index = 0;
      this.correctCount = 0;
      this.complete = false;
      this.saved = false;
      this.remaining = 90;
      this.clock.reset();
      this.question();
      await this.loadResults(version);
      if (!this.active || version !== this.version) { return; }
      if (this.words.length > 0 && this.active && version === this.version) { this.runTimer(); }
    } catch { if (this.active && version === this.version) { this.error = '练习词暂时没能载入，请重试。'; } }
    finally { if (this.active && version === this.version) { this.loading = false; } }
  }

  private runTimer(): void {
    this.clearTimer();
    if (!this.active || !this.destinationVisible || this.appBackground || this.complete || this.words.length === 0) { return; }
    this.clock.resume();
    this.journal.resume();
    this.tick();
    if (!this.complete) { this.timer = setInterval(() => { this.tick(); }, 250); }
  }

  private tick(): void {
    this.remaining = this.clock.remaining(90);
    if (this.remaining === 0) { this.finish(); }
  }

  private question(): void {
    this.hintUsed = false;
    this.journal.beginQuestion(); this.evidenceError = ''; this.evidenceBusy = false;
    this.cancelAudio();
    this.pronunciationMessage = '';
    this.answer = '';
    this.used = [];
    this.answered = false;
    this.correct = false;
    this.letters = this.mode === 'dictation' ? [] : shuffledLetters(this.words[this.index]?.word || '');
    if (this.mode === 'dictation' && this.words.length > 0) { this.pronounce(); }
  }

  private current(): Word { return this.words[this.index] || new Word(); }

  private submit(): void {
    if (this.answered || this.complete || this.loading || this.words.length === 0 ||
      !this.destinationVisible || this.appBackground) { return; }
    this.tick();
    if (this.complete) { return; }
    this.correct = this.mode === 'dictation' || !this.hintUsed ? dictationMatches(this.current().word, this.answer) :
      spellingMatches(this.current().word, this.answer);
    this.answered = true;
    if (this.correct) { this.correctCount++; }
    HapticService.pulse(this.service.getSettings().hapticsEnabled);
    this.getUIContext().getFocusController().clearFocus();
    this.saveEvidence();
  }

  private async saveEvidence(): Promise<void> {
    if (this.evidenceBusy || !this.answered) { return; }
    this.evidenceBusy = true; this.evidenceError = '';
    const version = this.version;
    try { await this.journal.record(this.current().id, this.mode, this.correct, this.hintUsed); }
    catch { if (this.active && version === this.version) { this.evidenceError = '这一题暂未保存，请重试。'; } }
    finally { if (this.active && version === this.version) { this.evidenceBusy = false; } }
  }

  private next(): void {
    if (this.evidenceBusy || this.evidenceError) { return; }
    if (!this.answered || this.complete || !this.destinationVisible || this.appBackground) { return; }
    if (this.index + 1 >= this.words.length) { this.finish(); return; }
    this.index++;
    this.question();
  }

  private finish(): void {
    if (this.complete) { return; }
    this.complete = true;
    this.pause();
    this.saveResult();
  }

  private async saveResult(): Promise<void> {
    if (this.saved || this.saving) { return; }
    this.saving = true;
    const version = this.version;
    try {
      await this.service.savePracticeResult(this.mode, this.correctCount, this.words.length,
        Math.min(90000, this.clock.duration()));
      if (this.active && version === this.version) {
        this.saved = true; this.error = '';
        await this.loadResults(version);
      }
    } catch { if (this.active && version === this.version) { this.error = '本轮成绩暂未保存，可再次保存。'; } }
    finally { this.saving = false; }
  }

  private async loadResults(version: number = this.version): Promise<void> {
    try {
      const results = await this.service.getPracticeResults(100);
      if (this.active && version === this.version) {
        this.results = results.filter((result: PracticeResult) => result.mode === this.mode).slice(0, 5);
        this.historyError = '';
      }
    } catch {
      if (this.active && version === this.version) { this.historyError = '最近练习暂时没能载入，可以重试。'; }
    }
  }

  private tile(index: number): void {
    if (this.used.indexOf(index) >= 0 || this.answered) { return; }
    this.used = this.used.concat([index]);
    this.answer += this.letters[index];
  }

  @Builder
  private action(label: string, callback: () => void) {
    Button(label).height(50).width('100%').backgroundColor($r('app.color.brand_ink'))
      .fontColor($r('app.color.inverse_text')).enabled(!this.loading && !this.saving).onClick(callback)
  }

  build() {
    Scroll() {
      Column({ space: 22 }) {
        Row({ space: 8 }) {
          Button('看释义').layoutWeight(1).height(44).enabled(!this.loading && !this.saving)
            .backgroundColor(this.mode === 'spelling' ? $r('app.color.brand_ink') : $r('app.color.soft_surface'))
            .fontColor(this.mode === 'spelling' ? $r('app.color.inverse_text') : $r('app.color.text_primary'))
            .onClick(() => { this.switchMode('spelling'); })
          Button('听音写词').layoutWeight(1).height(44).enabled(!this.loading && !this.saving)
            .backgroundColor(this.mode === 'dictation' ? $r('app.color.brand_ink') : $r('app.color.soft_surface'))
            .fontColor(this.mode === 'dictation' ? $r('app.color.inverse_text') : $r('app.color.text_primary'))
            .onClick(() => { this.switchMode('dictation'); })
        }.width('100%')
        if (this.loading) { LoadingProgress().width(36).height(36) }
        else if (this.complete) {
          Text('主动回忆，又进了一步。').fontSize(26).fontColor($r('app.color.text_primary'))
          Text(`${this.correctCount} / ${this.words.length}`).fontSize(56).fontColor($r('app.color.success'))
          Text('练习成绩独立保存，按自己的节奏再来。').fontSize(14).fontColor($r('app.color.text_secondary'))
          if (this.error) {
            Text(this.error).fontColor($r('app.color.text_secondary'))
            this.action('再次保存成绩', () => { this.saveResult(); })
          }
          this.action('再练 5 个词', () => { this.start(); })
        } else if (this.words.length === 0) {
          Text(this.error || '先学几个词，再来练习拼写。').fontSize(22).fontColor($r('app.color.text_primary'))
          if (this.error) { this.action('重新载入', () => { this.start(); }) }
        } else {
          Row() {
            Text(`${this.index + 1} / ${this.words.length}`).fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`还有 ${this.remaining} 秒`).fontColor($r('app.color.text_secondary'))
          }.width('100%')
          if (this.mode === 'dictation') {
            Text('听发音，写出完整单词').fontSize(24).fontColor($r('app.color.text_primary'))
            Button('♪ 重播发音').height(52).width('100%').fontSize(18)
              .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
              .accessibilityText('重播本题的英文发音').onClick(() => { this.pronounce(); })
            if (this.pronunciationMessage) {
              Text(this.pronunciationMessage).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary'))
            }
          } else {
            Text(this.current().meaning).fontSize(24).lineHeight(34).fontColor($r('app.color.text_primary')).width('100%')
            if (this.hintUsed) {
              Text(spellingHint(this.current().word)).fontSize(27).fontFamily('monospace')
                .fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
            } else if (!this.answered) {
              Button('需要提示？看看首尾字母').height(44).backgroundColor($r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).onClick(() => { this.hintUsed = true; })
            }
          }
          TextInput({ text: this.answer,
            placeholder: this.mode === 'dictation' ? '写出听到的完整单词' : this.hintUsed ? '填写中间字母，或完整单词' : '先试着写出完整单词' }).maxLength(30)
            .height(58).fontSize(22).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .enabled(!this.answered).onChange((value: string) => { this.answer = value; this.used = []; })
            .onSubmit(() => { this.submit(); }).accessibilityText('拼写答案')
          if (!this.answered) {
            if (this.mode === 'spelling' && this.hintUsed) {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
              ForEach(this.letters, (letter: string, index: number) => {
                Button(letter).width(46).height(46).margin(4).fontSize(21).enabled(this.used.indexOf(index) < 0)
                  .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                  .onClick(() => { this.tile(index); })
              }, (_letter: string, index: number) => `${this.index}-${index}`)
              }.width('100%')
            }
            Button('清空').onClick(() => { this.answer = ''; this.used = []; })
              .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
            this.action('检查拼写', () => { this.submit(); })
          } else {
            Text(this.correct ? '拼对了。' : '再看一眼，下次会更熟悉。').fontSize(18).fontColor($r('app.color.success'))
            Text(this.current().word).fontSize(32).fontColor($r('app.color.text_primary'))
            if (this.mode === 'dictation') {
              Text(this.current().meaning).fontSize(18).lineHeight(28).fontColor($r('app.color.text_secondary'))
            }
            this.action(this.index + 1 === this.words.length ? '查看成绩' : '下一词', () => { this.next(); })
          }
        }
        if (this.evidenceError) {
          Text(this.evidenceError).fontSize(14).fontColor($r('app.color.text_secondary'))
          Button('重新保存这一题').height(44).enabled(!this.evidenceBusy)
            .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
            .onClick(() => { this.saveEvidence(); })
        }
        if (this.evidenceBusy) { Text('正在保存这一题…').fontSize(13).fontColor($r('app.color.text_secondary')) }
        if (this.historyError && !this.loading && (this.complete || this.words.length === 0)) {
          Text(this.historyError).fontSize(14).fontColor($r('app.color.text_secondary'))
          this.action('重新载入最近练习', () => { this.loadResults(); })
        }
        if (this.results.length > 0 && (this.complete || this.words.length === 0)) {
          Text('最近练习').fontSize(18).fontColor($r('app.color.text_primary'))
          ForEach(this.results, (result: PracticeResult) => {
            Text(`${new Date(result.completedAt).toLocaleDateString()}  ·  ${result.correct} / ${result.total}`)
              .fontColor($r('app.color.text_secondary'))
          }, (result: PracticeResult) => `${result.id}`)
        }
      }.padding({ left: 24, right: 24, top: 76 + this.topInset, bottom: 40 }).width('100%').constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => {
        this.destinationVisible = visible;
        if (visible && !this.loading) { this.runTimer(); }
        else { this.pause(); }
      })
  }
}
