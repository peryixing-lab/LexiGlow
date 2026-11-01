import { PracticeJournal } from '../service/ExperienceService';
import { common } from '@kit.AbilityKit';
import { PracticeResult, Word } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { OriginalExampleService } from '../service/OriginalExampleService';
import { HapticService } from '../service/HapticService';
import { buildClozeRound, ClozeOption, ClozeQuestion } from '../utils/ClozeBuilder';
import { PracticeClock } from '../utils/PracticeClock';
import { bottomContentOffset } from '../utils/SafeAreaUtils';
import { pageHorizontalPadding } from '../utils/ResponsiveLayout';

@ComponentV2
export struct ClozeChallengePage {
  @Param preferredIds: number[] = [];
  @Local evidenceBusy: boolean = false;
  @Local evidenceError: string = '';
  private journal: PracticeJournal = new PracticeJournal();
  @Param topInset: number = 0;
  @Event onLearn: () => void = () => {};
  @Event onLearnedWords: () => void = () => {};
  @Local questions: ClozeQuestion[] = [];
  @Local index: number = 0;
  @Local selectedId: number = 0;
  @Local correctCount: number = 0;
  @Local complete: boolean = false;
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local saved: boolean = false;
  @Local error: string = '';
  @Local contentWarning: string = '';
  @Local historyError: string = '';
  @Local results: PracticeResult[] = [];
  @Local pageWidth: number = 0;
  private active: boolean = false;
  private visible: boolean = true;
  private foreground: boolean = true;
  private version: number = 0;
  private readonly clock: PracticeClock = new PracticeClock();
  private readonly service: LearningService = LearningService.getInstance();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.foreground = visible;
    this.updateClock();
  };

  aboutToAppear(): void {
    this.active = true;
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.start();
  }

  aboutToDisappear(): void {
    this.journal.pause();
    this.active = false;
    this.version++;
    this.clock.pause();
    this.context().eventHub.off('appVisibility', this.visibilityListener);
  }

  private updateClock(): void {
    if (this.active && this.visible && this.foreground && !this.loading && !this.complete && this.questions.length > 0) {
      this.clock.resume(); this.journal.resume();
    } else { this.clock.pause(); this.journal.pause(); }
  }

  private async start(): Promise<void> {
    if (this.saving || this.evidenceBusy || !!this.evidenceError) { return; }
    const version = ++this.version;
    this.loading = true;
    this.clock.reset();
    this.error = ''; this.contentWarning = ''; this.historyError = '';
    this.questions = []; this.index = 0; this.selectedId = 0;
    this.correctCount = 0; this.complete = false; this.saved = false;
    try {
      let words: Word[] = await this.service.getChallengeWords(1000);
      if (!this.active || version !== this.version) { return; }
      try { words = await OriginalExampleService.supplement(this.context(), words); }
      catch {
        if (this.active && version === this.version) {
          this.contentWarning = '补充例句暂未载入，这轮使用词条已有的例句。';
        }
      }
      if (!this.active || version !== this.version) { return; }
      if (this.preferredIds.length > 0) {
        const targeted = await this.service.getTargetedWords(this.preferredIds);
        const supplemented = await OriginalExampleService.supplement(this.context(), targeted);
        if (!this.active || version !== this.version) { return; }
        words = supplemented.concat(words.filter((word: Word) => this.preferredIds.indexOf(word.id) < 0));
      }
      this.questions = buildClozeRound(words, this.preferredIds.length > 0 ? this.preferredIds.length : 10, this.preferredIds);
      this.journal.beginQuestion(); this.evidenceError = ''; this.evidenceBusy = false;
      await this.loadResults(version);
    } catch {
      if (this.active && version === this.version) { this.error = '练习词暂时没能载入，请重试。'; }
    } finally {
      if (this.active && version === this.version) { this.loading = false; this.updateClock(); }
    }
  }

  private current(): ClozeQuestion { return this.questions[this.index] || new ClozeQuestion(); }

  private select(option: ClozeOption): void {
    if (this.selectedId > 0 || this.loading || this.complete || !this.visible || !this.foreground) { return; }
    this.selectedId = option.wordId;
    if (option.wordId === this.current().correctId) { this.correctCount++; }
    HapticService.pulse(this.service.getSettings().hapticsEnabled);
    this.saveEvidence();
  }

  private async saveEvidence(): Promise<void> {
    if (this.evidenceBusy || this.selectedId === 0) { return; }
    const version = this.version; this.evidenceBusy = true; this.evidenceError = '';
    try { await this.journal.record(this.current().word.id, 'cloze', this.selectedId === this.current().correctId, false); }
    catch { if (this.active && version === this.version) { this.evidenceError = '这一题暂未保存，请重试。'; } }
    finally { if (this.active && version === this.version) { this.evidenceBusy = false; } }
  }

  private next(): void {
    if (this.evidenceBusy || this.evidenceError) { return; }
    if (this.selectedId === 0 || this.complete || this.loading) { return; }
    if (this.index + 1 >= this.questions.length) {
      this.complete = true; this.clock.pause(); this.saveResult();
    } else { this.index++; this.selectedId = 0; this.journal.beginQuestion(); }
  }

  private async saveResult(): Promise<void> {
    if (this.saved || this.saving || !this.complete) { return; }
    this.saving = true;
    const version = this.version;
    try {
      await this.service.savePracticeResult('cloze', this.correctCount, this.questions.length, this.clock.duration());
      if (this.active && version === this.version) { this.saved = true; this.error = ''; await this.loadResults(version); }
    } catch {
      if (this.active && version === this.version) { this.error = '本轮成绩暂未保存，可再次保存。'; }
    } finally { this.saving = false; }
  }

  private async loadResults(version: number = this.version): Promise<void> {
    try {
      const results = await this.service.getPracticeResults(100);
      if (this.active && version === this.version) {
        this.results = results.filter((result: PracticeResult) => result.mode === 'cloze').slice(0, 5);
        this.historyError = '';
      }
    } catch {
      if (this.active && version === this.version) { this.historyError = '最近练习暂时没能载入，可以重试。'; }
    }
  }

  @Builder
  private action(label: string, callback: () => void) {
    Button(label).height(52).width('100%').backgroundColor($r('app.color.brand_ink'))
      .fontColor($r('app.color.inverse_text')).enabled(!this.loading && !this.saving).onClick(callback)
  }

  @Builder
  private option(option: ClozeOption) {
    Button(option.text, { type: ButtonType.Normal }).height(56).width('100%').fontSize(20).borderRadius(18)
      .backgroundColor(this.selectedId > 0 && option.wordId === this.current().correctId ? $r('app.color.glow') :
        option.wordId === this.selectedId ? $r('app.color.brand_ink') : $r('app.color.surface'))
      .fontColor(option.wordId === this.selectedId && option.wordId !== this.current().correctId ?
        $r('app.color.inverse_text') : $r('app.color.text_primary'))
      .enabled(this.selectedId === 0).accessibilityText(`选项 ${option.text}`)
      .onClick(() => { this.select(option); })
  }

  build() {
    Scroll() {
      Column({ space: 22 }) {
        if (this.evidenceError) {
          Text(this.evidenceError).fontSize(14).fontColor($r('app.color.text_secondary'))
          Button('重新保存这一题').height(44).enabled(!this.evidenceBusy)
            .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
            .onClick(() => { this.saveEvidence(); })
        }
        if (this.evidenceBusy) { Text('正在保存这一题…').fontSize(13).fontColor($r('app.color.text_secondary')) }
        if (this.loading) {
          LoadingProgress().width(36).height(36)
          Text('正在从已学单词中出题…').fontColor($r('app.color.text_secondary'))
        } else if (this.questions.length === 0) {
          Text('例句暂不足').fontSize(26).fontColor($r('app.color.text_primary'))
          Text(this.error || '需要至少 4 个不同的已学词，并有包含目标词的双语例句。继续学几个词，再回来试试。')
            .fontSize(16).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
          this.action('重新载入', () => { this.start(); })
          this.action('去学习几个词', this.onLearn)
          Button('查看已学单词').height(44).fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.soft_surface')).onClick(this.onLearnedWords)
        } else if (this.complete) {
          Text('在句子里，又记住了一次。').fontSize(26).fontColor($r('app.color.text_primary'))
          Text(`${this.correctCount} / ${this.questions.length}`).fontSize(56).fontColor($r('app.color.success'))
          Text('语境练习独立计分，日常复习按原来的节奏继续。').fontSize(15).lineHeight(25)
            .fontColor($r('app.color.text_secondary'))
          if (this.error) {
            Text(this.error).fontColor($r('app.color.text_secondary'))
            this.action('再次保存成绩', () => { this.saveResult(); })
          }
          this.action('再练一轮', () => { this.start(); })
        } else {
          Row() {
            Text(`${this.index + 1} / ${this.questions.length}`).fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`已答对 ${this.correctCount} 词`).fontColor($r('app.color.success'))
          }.width('100%')
          Text('选出适合这句话的单词').fontSize(15).fontColor($r('app.color.text_secondary')).width('100%')
          Text(this.current().sentence).fontSize(25).lineHeight(39).fontColor($r('app.color.text_primary'))
            .padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
          Column({ space: 10 }) {
            ForEach(this.current().options, (option: ClozeOption) => { this.option(option); },
              (option: ClozeOption) => `${this.index}-${option.wordId}`)
          }.width('100%')
          if (this.selectedId > 0) {
            Column({ space: 12 }) {
              Text(this.selectedId === this.current().correctId ? '选对了。' : '再读一次，看看它在句子里的用法。')
                .fontSize(18).fontColor($r('app.color.success')).width('100%')
              Text(this.current().originalSentence).fontSize(18).lineHeight(28)
                .fontColor($r('app.color.text_primary')).width('100%')
              Text(this.current().translation).fontSize(16).lineHeight(26)
                .fontColor($r('app.color.text_secondary')).width('100%')
              Text(`${this.current().word.word} · ${this.current().word.meaning}`).fontSize(16).lineHeight(26)
                .fontColor($r('app.color.text_primary')).width('100%')
            }.padding(22).width('100%').backgroundColor($r('app.color.soft_surface')).borderRadius(24)
            this.action(this.index + 1 === this.questions.length ? '查看成绩' : '下一句 →', () => { this.next(); })
          }
        }
        if (this.contentWarning) {
          Text(this.contentWarning).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary'))
        }
        if (!this.loading && (this.complete || this.questions.length === 0)) {
          if (this.historyError) {
            Text(this.historyError).fontColor($r('app.color.text_secondary'))
            this.action('重新载入最近练习', () => { this.loadResults(); })
          }
          if (this.results.length > 0) {
            Text('最近语境练习').fontSize(18).fontColor($r('app.color.text_primary'))
            ForEach(this.results, (result: PracticeResult) => {
              Text(`${new Date(result.completedAt).toLocaleDateString()} · ${result.correct} / ${result.total}`)
                .fontColor($r('app.color.text_secondary'))
            }, (result: PracticeResult) => `${result.id}`)
          }
        }
      }.padding(pageHorizontalPadding(this.pageWidth)).width('100%').constraintSize({ maxWidth: 760 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
      .contentStartOffset(56 + this.topInset).contentEndOffset(bottomContentOffset(this.getUIContext()))
      .onVisibleAreaChange([0, 1], (visible: boolean) => { this.visible = visible; this.updateClock(); })
      .onAreaChange((_oldArea: Area, area: Area) => { this.pageWidth = Number(area.width); })
  }
}
