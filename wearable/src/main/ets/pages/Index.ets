import { common } from '@kit.AbilityKit';
import { ArcList, ArcListItem, LengthMetrics } from '@kit.ArkUI';
import { AppSnapshot, ReviewResult, StudySession, Word, WordBook } from '../model/AppModels';
import { LearningService } from '../service/LearningService';

/** Round-screen product layer. Persistence and review scheduling use the phone's verified core. */
@Entry
@Component
struct Index {
  @State private snapshot: AppSnapshot = new AppSnapshot();
  @State private session: StudySession = new StudySession();
  @State private selectedWord: Word = new Word();
  @State private screen: string = 'home';
  @State private revealed: boolean = false;
  @State private busy: boolean = true;
  @State private error: string = '';
  private service: LearningService = LearningService.getInstance();
  private scroller: Scroller = new Scroller();
  private ready: boolean = false;
  private answeredAt: number = 0;

  aboutToAppear(): void {
    this.initialize();
  }

  onPageShow(): void {
    if (this.ready && !this.busy) {
      this.reloadSnapshot();
    }
  }

  onBackPress(): boolean {
    if (this.busy) {
      return true;
    }
    if (this.screen !== 'home') {
      this.showHome();
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      if (!canIUse('SystemCapability.DistributedDataManager.RelationalStore.Core') ||
        !canIUse('SystemCapability.DistributedDataManager.Preferences.Core')) {
        throw new Error('当前手表不支持离线学习存储');
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.service.initialize(context);
      const settings = this.service.getSettings();
      if (!settings.onboarded) {
        settings.dailyNewTarget = 5;
        settings.autoPronounce = false;
        settings.onboarded = true;
        await this.service.updateSettings(settings);
      }
      // The watch has its own device-local plan: five new words, at most fifteen
      // reviews. The service still applies the same backlog protection and schedule.
      await this.service.setBudget('busy');
      await this.reloadSnapshot();
      this.ready = true;
    } catch (error) {
      this.error = (error as Error).message || '学习数据加载失败，请重试';
    } finally {
      this.busy = false;
    }
  }

  private async reloadSnapshot(): Promise<void> {
    try {
      this.snapshot = await this.service.getSnapshot();
      this.session = this.service.getSession();
    } catch (error) {
      this.error = (error as Error).message || '今日计划加载失败';
    }
  }

  private async showHome(): Promise<void> {
    this.screen = 'home';
    this.error = '';
    await this.reloadSnapshot();
  }

  private hasSession(): boolean {
    return this.session.index < this.session.items.length;
  }

  private currentWord(): Word {
    return this.hasSession() ? this.session.items[this.session.index].word : new Word();
  }

  private bookName(book: WordBook): string {
    return book.name.replace(' · ECDICT 词书', '');
  }

  private currentBookName(): string {
    const book = this.snapshot.books.find((item: WordBook) => item.id === this.snapshot.settings.currentBookId);
    return book ? this.bookName(book) : '四级';
  }

  private focus(id: string): void {
    // Conditional pages need explicit focus restoration for native crown scrolling.
    try {
      this.getUIContext().getFocusController().requestFocus(id);
    } catch (_) {
      // Touch scrolling remains available on devices without a rotating crown.
    }
  }

  private async start(mode: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await this.service.setBudget('busy');
      this.session = await this.service.startSession(mode);
      this.revealed = false;
      this.answeredAt = Date.now();
      this.screen = this.hasSession() ? 'study' : 'complete';
    } catch (error) {
      this.error = (error as Error).message || '无法开始学习，请重试';
    } finally {
      this.busy = false;
    }
  }

  private resume(): void {
    if (this.busy || !this.hasSession()) {
      return;
    }
    this.error = '';
    this.revealed = false;
    this.answeredAt = Date.now();
    this.screen = 'study';
  }

  private async answer(result: ReviewResult): Promise<void> {
    if (this.busy || !this.revealed || !this.hasSession()) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      // record() atomically commits progress, history, daily plan and resume cursor.
      // Its returned copy is applied only after commit, so a failed save keeps this word.
      this.session = await this.service.record(result, Math.max(0, Date.now() - this.answeredAt));
      this.revealed = false;
      this.answeredAt = Date.now();
      if (this.hasSession()) {
        this.scroller.scrollEdge(Edge.Top);
        this.focus('watch-study');
      } else {
        this.screen = 'complete';
        await this.reloadSnapshot();
      }
    } catch (error) {
      this.error = (error as Error).message || '保存失败，请重试当前单词';
    } finally {
      this.busy = false;
    }
  }

  private async selectBook(book: WordBook): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const settings = this.service.getSettings();
      if (settings.currentBookId !== book.id) {
        await this.service.clearSession();
        settings.currentBookId = book.id;
        await this.service.updateSettings(settings);
      }
      await this.service.setBudget('busy');
      await this.showHome();
    } catch (error) {
      this.error = (error as Error).message || '切换词书失败';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private message() {
    if (this.error.length > 0) {
      Text(this.error)
        .fontSize(14)
        .fontColor($r('app.color.watch_error'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .accessibilityText(this.error)
    }
  }

  @Builder
  private action(label: string, callback: () => void, primary: boolean = false) {
    Button(label, { type: ButtonType.Capsule })
      .width('100%')
      .constraintSize({ minHeight: 44 })
      .padding({ top: 10, bottom: 10, left: 8, right: 8 })
      .fontSize(16)
      .fontWeight(primary ? FontWeight.Medium : FontWeight.Regular)
      .backgroundColor(primary ? $r('app.color.watch_accent') : $r('app.color.watch_surface'))
      .fontColor(primary ? $r('app.color.watch_accent_text') : $r('app.color.watch_text'))
      .enabled(!this.busy)
      .onClick(callback)
  }

  @Builder
  private home() {
    ArcList() {
      ArcListItem() {
        Column({ space: 6 }) {
          Text('词萤 · 今日')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.watch_text'))
          Text(`新词 ${this.snapshot.plan.newDone}/${this.snapshot.plan.newTarget}  ·  复习 ${this.snapshot.plan.reviewDone}/${this.snapshot.plan.reviewTarget}`)
            .fontSize(14)
            .fontColor($r('app.color.watch_secondary'))
            .textAlign(TextAlign.Center)
          Progress({
            value: this.snapshot.plan.newDone + this.snapshot.plan.reviewDone,
            total: Math.max(1, this.snapshot.plan.newTarget + this.snapshot.plan.reviewTarget),
            type: ProgressType.Linear
          })
            .width('80%')
            .color($r('app.color.watch_accent'))
          this.message()
        }
        .width('76%')
        .padding({ top: 12, bottom: 12 })
      }
      .align(Alignment.Center)

      if (this.hasSession()) {
        ArcListItem() {
          Column() {
            this.action('继续学习', () => this.resume(), true)
          }.width('76%')
        }.align(Alignment.Center)
      }
      ArcListItem() {
        Column() {
          this.action('今日轻学习', () => { this.start('today'); }, !this.hasSession())
        }.width('76%')
      }.align(Alignment.Center)
      ArcListItem() {
        Column() {
          this.action(`到期复习 · ${this.snapshot.dueCount}`, () => { this.start('review'); })
        }.width('76%')
      }.align(Alignment.Center)
      ArcListItem() {
        Column() {
          this.action('3 分钟速学', () => { this.start('quick'); })
        }.width('76%')
      }.align(Alignment.Center)
      ArcListItem() {
        Column() {
          this.action('每日一词', () => {
            this.selectedWord = this.snapshot.dailyWord;
            this.screen = 'word';
          })
        }.width('76%')
      }.align(Alignment.Center)
      ArcListItem() {
        Column() {
          this.action(`词书 · ${this.currentBookName()}`, () => { this.screen = 'books'; })
        }.width('76%')
      }.align(Alignment.Center)
      ArcListItem() {
        Text('学习记录保存在这块手表\n与手机分别记录')
          .fontSize(13)
          .fontColor($r('app.color.watch_secondary'))
          .textAlign(TextAlign.Center)
          .width('68%')
          .padding({ top: 12, bottom: 18 })
      }.align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
    .space(LengthMetrics.vp(8))
    .scrollBar(BarState.Auto)
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
    .id('watch-home')
    .onAppear(() => this.focus('watch-home'))
  }

  @Builder
  private wordContent(word: Word, showMeaning: boolean) {
    Text(word.word)
      .fontSize(28)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.watch_text'))
      .textAlign(TextAlign.Center)
      .wordBreak(WordBreak.BREAK_ALL)
      .width('100%')
    if (word.phonetic.length > 0) {
      Text(word.phonetic)
        .fontSize(14)
        .fontColor($r('app.color.watch_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    if (showMeaning) {
      Text(word.meaning)
        .fontSize(18)
        .fontColor($r('app.color.watch_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (word.example.length > 0) {
        Text(word.example)
          .fontSize(15)
          .fontColor($r('app.color.watch_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      if (word.translation.length > 0) {
        Text(word.translation)
          .fontSize(14)
          .fontColor($r('app.color.watch_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
  }

  @Builder
  private study() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        Text(`${this.session.index + 1} / ${this.session.items.length}  ·  ${this.session.items[this.session.index].type === 'new' ? '新词' : '复习'}`)
          .fontSize(14)
          .fontColor($r('app.color.watch_secondary'))
          .textAlign(TextAlign.Center)
        this.wordContent(this.currentWord(), this.revealed)
        this.message()
        if (this.revealed) {
          this.action('认识', () => { this.answer(ReviewResult.KNOW); }, true)
          this.action('模糊', () => { this.answer(ReviewResult.FUZZY); })
          this.action('不认识', () => { this.answer(ReviewResult.FORGET); })
        } else {
          this.action('查看释义', () => {
            this.revealed = true;
            this.focus('watch-study');
          }, true)
        }
        this.action('稍后继续', () => { this.showHome(); })
      }
      .width('70%')
      .padding({ top: 30, bottom: 38 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
    .id('watch-study')
    .onAppear(() => {
      this.scroller.scrollEdge(Edge.Top);
      this.focus('watch-study');
    })
  }

  @Builder
  private wordDetail() {
    Scroll() {
      Column({ space: 12 }) {
        Text('每日一词')
          .fontSize(14)
          .fontColor($r('app.color.watch_secondary'))
        this.wordContent(this.selectedWord, true)
        this.action('返回今日', () => { this.showHome(); })
      }
      .width('70%')
      .padding({ top: 30, bottom: 38 })
    }
    .width('100%')
    .height('100%')
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
    .id('watch-word')
    .onAppear(() => this.focus('watch-word'))
  }

  @Builder
  private books() {
    ArcList() {
      ArcListItem() {
        Column({ space: 4 }) {
          Text('选择词书')
            .fontSize(18)
            .fontColor($r('app.color.watch_text'))
          Text('离线学习 · 每日 5 个新词')
            .fontSize(13)
            .fontColor($r('app.color.watch_secondary'))
          this.message()
        }.width('76%').padding({ top: 12, bottom: 12 })
      }.align(Alignment.Center)
      ForEach(this.snapshot.books, (book: WordBook) => {
        ArcListItem() {
          Column() {
            this.action(
              `${book.id === this.snapshot.settings.currentBookId ? '✓ ' : ''}${this.bookName(book)}`,
              () => { this.selectBook(book); },
              book.id === this.snapshot.settings.currentBookId
            )
          }.width('76%')
        }.align(Alignment.Center)
      }, (book: WordBook) => book.id)
      ArcListItem() {
        Column() {
          this.action('返回今日', () => { this.showHome(); })
        }.width('76%')
      }.align(Alignment.Center)
    }
    .space(LengthMetrics.vp(8))
    .width('100%')
    .height('100%')
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
    .id('watch-books')
    .onAppear(() => this.focus('watch-books'))
  }

  @Builder
  private completion() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.session.completed > 0 ? '这一轮完成了' : '暂时没有任务')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.watch_accent'))
          .textAlign(TextAlign.Center)
        Text(this.session.completed > 0 ? `完成 ${this.session.completed} 个学习判断\n进度已保存` : '到期后再来复习\n也可以开始速学')
          .fontSize(16)
          .fontColor($r('app.color.watch_text'))
          .textAlign(TextAlign.Center)
        this.message()
        this.action('返回今日', () => { this.showHome(); }, true)
      }
      .width('70%')
      .padding({ top: 38, bottom: 38 })
    }
    .width('100%')
    .height('100%')
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
    .id('watch-complete')
    .onAppear(() => this.focus('watch-complete'))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.ready) {
        Column({ space: 12 }) {
          Text('词萤')
            .fontSize(22)
            .fontColor($r('app.color.watch_accent'))
          if (this.busy) {
            LoadingProgress().width(36).height(36).color($r('app.color.watch_accent'))
            Text('准备离线词书…')
              .fontSize(14)
              .fontColor($r('app.color.watch_secondary'))
          } else {
            this.message()
            this.action('重新加载', () => { this.initialize(); }, true)
          }
        }.width('68%')
      } else if (this.screen === 'study' && this.hasSession()) {
        this.study()
      } else if (this.screen === 'word') {
        this.wordDetail()
      } else if (this.screen === 'books') {
        this.books()
      } else if (this.screen === 'complete') {
        this.completion()
      } else {
        this.home()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.watch_background'))
  }
}
