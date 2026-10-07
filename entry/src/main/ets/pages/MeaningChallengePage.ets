import { Word } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { ChallengeService } from '../service/ChallengeService';
import { AudioService } from '../service/AudioService';
import { meaningAnswers } from '../utils/MeaningMatcher';

@ComponentV2
export struct MeaningChallengePage {
  @Event onLearn: () => void = () => {};
  @Event onLearnedWords: () => void = () => {};
  @Local loading: boolean = false;
  @Local error: string = '';
  @Local word: Word = new Word();
  @Local answer: string = '';
  @Local index: number = 0;
  @Local total: number = 0;
  @Local correctCount: number = 0;
  @Local answered: boolean = false;
  @Local correct: boolean = false;
  @Local complete: boolean = false;
  private readonly challenge: ChallengeService = new ChallengeService();
  private readonly inputController: TextInputController = new TextInputController();
  private active: boolean = false;
  private requestVersion: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.startRound();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
    this.loading = false;
    this.inputController.stopEditing();
    AudioService.getInstance().stop();
  }

  private async startRound(): Promise<void> {
    if (this.loading) { return; }
    const version = ++this.requestVersion;
    this.loading = true;
    this.error = '';
    try {
      const candidates = await LearningService.getInstance().getChallengeWords(50);
      if (!this.active || version !== this.requestVersion) { return; }
      this.challenge.start(candidates.filter((item: Word) => meaningAnswers(item.meaning).length > 0).slice(0, 10));
      this.syncQuestion();
    } catch (error) {
      if (this.active && version === this.requestVersion) { this.error = '挑战词暂时没能载入，请重试。'; }
    } finally {
      if (this.active && version === this.requestVersion) { this.loading = false; }
    }
  }

  private syncQuestion(): void {
    this.word = this.challenge.currentWord() || new Word();
    this.index = this.challenge.getIndex();
    this.total = this.challenge.getTotal();
    this.correctCount = this.challenge.getCorrectCount();
    this.answered = this.challenge.isAnswered();
    this.complete = this.challenge.isComplete();
    this.correct = false;
    this.answer = '';
    this.error = '';
  }

  private submit(): void {
    if (this.answered || this.loading || this.complete) { return; }
    try {
      this.correct = this.challenge.submit(this.answer);
      this.answered = true;
      this.correctCount = this.challenge.getCorrectCount();
      this.error = '';
      this.inputController.stopEditing();
    } catch (error) {
      this.error = (error as Error).message || '请输入一个中文意思。';
    }
  }

  private next(): void {
    if (!this.answered) { return; }
    this.challenge.next();
    this.syncQuestion();
  }

  private async pronounce(): Promise<void> {
    try { await AudioService.getInstance().speak(this.word.word); }
    catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '当前设备暂时无法播放英文发音。' });
    }
  }

  @Builder
  private action(label: string, primary: boolean, callback: () => void) {
    Button(label, { type: ButtonType.Normal }).width('100%').height(52).fontSize(16)
      .borderRadius(18).backgroundColor(primary ? $r('app.color.brand_ink') : $r('app.color.soft_surface'))
      .fontColor(primary ? $r('app.color.inverse_text') : $r('app.color.text_primary'))
      .enabled(!this.loading).onClick(callback)
  }

  build() {
    Scroll() {
      Column({ space: 22 }) {
        if (this.loading) {
          LoadingProgress().width(32).height(32).color($r('app.color.success'))
          Text('正在从已学单词中出题…').fontSize(15).fontColor($r('app.color.text_secondary'))
        } else if (this.total === 0) {
          Text('先记几个词，再来挑战。').fontSize(26).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          Text(this.error || '学习过的单词会成为你的题库。写出一个中文义项，就能通过。')
            .fontSize(16).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
          if (this.error) { this.action('重试', true, () => { this.startRound(); }); }
          else { this.action('去学习几个词', true, this.onLearn); }
          this.action('查看已学单词', false, this.onLearnedWords)
        } else if (this.complete) {
          Text('这轮挑战完成了。').fontSize(27).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          Column({ space: 12 }) {
            Text(`${this.correctCount} / ${this.total}`).fontSize(48).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('答对的单词').fontSize(15).fontColor($r('app.color.text_secondary'))
          }.padding(28).width('100%').backgroundColor($r('app.color.glow')).borderRadius(26)
          Text('再见一次，就是多一次巩固。').fontSize(15).fontColor($r('app.color.text_secondary'))
          this.action('再挑战一轮', true, () => { this.startRound(); })
          this.action('查看已学单词', false, this.onLearnedWords)
          if (this.error) { Text(this.error).fontSize(14).fontColor($r('app.color.text_secondary')); }
        } else {
          Row() {
            Text(`${this.index + 1} / ${this.total}`).fontSize(15).fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`已答对 ${this.correctCount} 词`).fontSize(14).fontColor($r('app.color.success'))
          }.width('100%')
          Progress({ value: this.index, total: this.total, type: ProgressType.Linear })
            .color($r('app.color.success')).backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 4 })
          Column({ space: 16 }) {
            Text(this.word.word).fontSize(38).fontWeight(FontWeight.Medium).fontFamily('serif')
              .fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
            Row({ space: 12 }) {
              Text(this.word.phonetic).fontSize(16).fontColor($r('app.color.text_secondary'))
              Button('♪').width(44).height(44).fontSize(23).backgroundColor($r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).accessibilityText('播放英文发音')
                .onClick(() => { this.pronounce(); })
            }
          }.padding({ top: 30, bottom: 22 }).width('100%')
          Text('写出它的任意一个中文意思').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).width('100%')
          TextInput({ text: this.answer, placeholder: '例如：放弃', controller: this.inputController })
            .fontSize(18).height(58).maxLength(120).borderRadius(18)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
            .enabled(!this.answered).enterKeyType(EnterKeyType.Done)
            .onChange((value: string) => { this.answer = value; this.error = ''; })
            .onSubmit(() => { this.submit(); })
          if (this.answered) {
            Column({ space: 12 }) {
              Text(this.correct ? '答对了。' : '这次没答对，再看一眼释义。')
                .fontSize(18).fontWeight(FontWeight.Medium)
                .fontColor(this.correct ? $r('app.color.success') : $r('app.color.text_primary')).width('100%')
              Text('词典释义').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
              Text(this.word.meaning).fontSize(18).lineHeight(28).fontColor($r('app.color.text_primary')).width('100%')
            }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
            this.action(this.index + 1 >= this.total ? '查看本轮结果' : '下一词 →', true, () => { this.next(); })
          } else {
            if (this.error) { Text(this.error).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%'); }
            this.action('检查答案', true, () => { this.submit(); })
          }
          Text('题目来自你的已学单词 · 独立练习计分').fontSize(12)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }
      }.padding(24).width('100%').constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%').contentStartOffset(56).scrollBar(BarState.Off)
      .backgroundColor($r('app.color.background'))
  }
}
