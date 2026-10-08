import { LearnedDate, LearnedWord } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { dateKey } from '../utils/TimeUtils';
import { strengthName } from '../utils/MemoryUtils';
import { bottomContentOffset } from '../utils/SafeAreaUtils';
import { PAGE_MAX_WIDTH, pageHorizontalPadding, wordListColumnCount } from '../utils/ResponsiveLayout';
import { deviceInfo } from '@kit.BasicServicesKit';

@ComponentV2
export struct LearnedWordsPage {
  @Event onOpenWord: (id: number, bookId: string) => void = () => {};
  @Event onChallenge: () => void = () => {};
  @Param topInset: number = 0;
  @Local pageWidth: number = 0;
  @Local dates: LearnedDate[] = [];
  @Local selectedDate: string = '';
  @Local query: string = '';
  @Local words: LearnedWord[] = [];
  @Local totalLearned: number = 0;
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local hasMore: boolean = false;
  @Local error: string = '';
  private readonly listScroller: Scroller = new Scroller();
  private requestVersion: number = 0;
  private searchTimer: number = -1;

  aboutToAppear(): void { this.initialize(); }

  aboutToDisappear(): void {
    this.requestVersion++;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
  }

  private async initialize(): Promise<void> {
    const version = ++this.requestVersion;
    this.ready = false;
    this.error = '';
    try {
      const dates = await LearningService.getInstance().getLearnedDates();
      if (version !== this.requestVersion) { return; }
      this.dates = dates;
      this.totalLearned = this.dates.reduce((total: number, day: LearnedDate) => total + day.count, 0);
      this.selectedDate = this.dates.length > 0 ? this.dates[0].date : '';
      this.ready = true;
      if (this.dates.length > 0) { await this.loadWords(true); }
    } catch (error) {
      if (version !== this.requestVersion) { return; }
      this.error = '已学单词暂时没能载入，请重试。';
      this.ready = true;
    }
  }

  private async loadWords(reset: boolean): Promise<void> {
    if (!reset && (this.loading || !this.hasMore)) { return; }
    const version = ++this.requestVersion;
    const offset = reset ? 0 : this.words.length;
    this.loading = true;
    this.error = '';
    if (reset) { this.words = []; this.hasMore = false; }
    try {
      const items = await LearningService.getInstance().getLearnedWords(this.selectedDate, this.query, offset);
      if (version !== this.requestVersion) { return; }
      this.words = reset ? items : this.words.concat(items);
      this.hasMore = items.length === 50;
      if (reset) { this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
    } catch (error) {
      if (version === this.requestVersion) { this.error = '这一天的单词暂时没能载入，请重试。'; }
    } finally {
      if (version === this.requestVersion) { this.loading = false; }
    }
  }

  private selectDate(date: string): void {
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.selectedDate = date;
    this.loadWords(true);
  }

  private search(value: string): void {
    this.query = value;
    // Invalidate in-flight results as soon as the query changes.
    this.requestVersion++;
    this.words = [];
    this.hasMore = false;
    this.loading = true;
    this.error = '';
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => { this.loadWords(true); }, 180);
  }

  private asDate(key: string): Date {
    const parts = key.split('-').map((part: string) => Number(part));
    return new Date(parts[0], parts[1] - 1, parts[2]);
  }

  private pickDate(): void {
    const known = this.dates.filter((day: LearnedDate) => day.date.length > 0);
    if (known.length === 0) { return; }
    this.getUIContext().showDatePickerDialog({
      start: this.asDate(known[known.length - 1].date),
      end: this.asDate(known[0].date),
      selected: this.asDate(this.selectedDate || known[0].date),
      lunar: false,
      onDateAccept: (value: Date) => { this.selectDate(dateKey(value.getTime())); }
    });
  }

  private dateLabel(): string { return this.selectedDate || '日期未记录'; }

  private selectedCount(): number {
    const day = this.dates.find((item: LearnedDate) => item.date === this.selectedDate);
    return day ? day.count : 0;
  }

  private pagePadding(): number { return pageHorizontalPadding(this.pageWidth); }

  private usesLargeWordList(): boolean {
    return deviceInfo.deviceType === 'tablet' || deviceInfo.deviceType === '2in1';
  }

  private columnCount(): number {
    const contentWidth = Math.max(0, Math.min(this.pageWidth, PAGE_MAX_WIDTH) - this.pagePadding() * 2);
    return wordListColumnCount(contentWidth, 14);
  }

  @Builder
  private dateChip(day: LearnedDate) {
    Button(`${day.date || '日期未记录'} · ${day.count}`, { type: ButtonType.Normal })
      .fontSize(12).height(42).padding({ left: 14, right: 14 }).borderRadius(14)
      .backgroundColor(day.date === this.selectedDate ? $r('app.color.glow') : $r('app.color.surface'))
      .fontColor($r('app.color.text_primary')).hoverEffect(HoverEffect.Auto)
      .onClick(() => { this.selectDate(day.date); })
  }

  @Builder
  private wordRow(item: LearnedWord) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 7 }) {
          if (this.usesLargeWordList()) {
            Text(item.word.word).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.word.meaning).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
              .width('100%').height(44).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text(item.word.word).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(item.word.meaning).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary')).maxLines(2)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text(strengthName(item.strength)).fontSize(12).fontColor($r('app.color.success'))
          Text('›').fontSize(26).fontColor($r('app.color.text_secondary'))
        }
      }
    }.padding(20).width('100%').height(this.usesLargeWordList() ? 120 : undefined)
      .backgroundColor($r('app.color.surface')).borderRadius(20).focusable(true)
      .hoverEffect(HoverEffect.Auto).accessibilityText(`${item.word.word}，${item.word.meaning}，查看单词详情`)
      .onClick(() => { this.onOpenWord(item.word.id, item.word.sourceBookId); })
  }

  @Builder
  private listHeader() {
    Column({ space: 14 }) {
      if (!this.ready) {
        LoadingProgress().width(32).height(32).color($r('app.color.success'))
      } else if (this.dates.length === 0) {
        Column({ space: 18 }) {
          Text(this.error || '还没有已学单词。').fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('完成第一次学习后，单词会按首次学习日期留在这里。').fontSize(15).lineHeight(25)
            .fontColor($r('app.color.text_secondary'))
          if (this.error) {
            Button('重试').height(48).backgroundColor($r('app.color.brand_ink'))
              .fontColor($r('app.color.inverse_text')).onClick(() => { this.initialize(); })
          }
        }.padding({ top: 26, bottom: 26 }).width('100%')
      } else {
        Row() {
          Text(`已学 ${this.totalLearned} 词`).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Button('释义挑战 →').height(42).fontSize(13).backgroundColor($r('app.color.glow'))
            .fontColor($r('app.color.text_primary')).hoverEffect(HoverEffect.Auto).onClick(this.onChallenge)
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Button(`${this.dateLabel()}  ▾`, { type: ButtonType.Normal }).height(46).fontSize(15)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
            .borderRadius(14).margin({ right: 10 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.pickDate(); })
          Text(`首次学习 ${this.selectedCount()} 词`).fontSize(13).fontColor($r('app.color.text_secondary'))
            .padding({ top: 8, bottom: 8 })
        }.width('100%')
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.dates.filter((day: LearnedDate) => day.date.length > 0).slice(0, 7), (day: LearnedDate) => {
              this.dateChip(day)
            }, (day: LearnedDate) => day.date)
            ForEach(this.dates.filter((day: LearnedDate) => day.date.length === 0), (day: LearnedDate) => {
              this.dateChip(day)
            }, (day: LearnedDate) => 'unknown')
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44)
        TextInput({ text: this.query, placeholder: '搜索这一天的单词或中文释义' }).height(50).fontSize(15)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).borderRadius(16)
          .accessibilityText('搜索已学单词').onChange((value: string) => { this.search(value); })
      }
    }.width('100%').padding({ bottom: 10 })
  }

  @Builder
  private listFooter() {
    Column() {
      if (this.ready && this.dates.length > 0) {
        if (this.error) {
          Button(`${this.error} 点此重试`).fontSize(14).constraintSize({ minHeight: 48 })
            .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
            .onClick(() => { this.loadWords(this.words.length === 0); })
        } else if (this.loading) {
          Text('正在查找…').fontSize(14).padding(20).fontColor($r('app.color.text_secondary'))
        } else if (this.words.length === 0) {
          Text(this.query ? '这一天没有匹配的单词，试试其他关键词。' : '这一天没有首次学习的单词，可以选择其他日期。')
            .fontSize(15).lineHeight(25).padding(22).fontColor($r('app.color.text_secondary'))
        } else if (this.hasMore) {
          Button('加载更多单词').fontSize(14).height(46).backgroundColor($r('app.color.soft_surface'))
            .fontColor($r('app.color.text_primary')).hoverEffect(HoverEffect.Auto)
            .onClick(() => { this.loadWords(false); })
        }
      }
    }.width('100%').padding({ top: 10 })
  }

  build() {
    Column() {
      List({ space: 10, scroller: this.listScroller }) {
        ListItemGroup({ header: this.listHeader(), footer: this.listFooter(), space: 10 }) {
          ForEach(this.words, (item: LearnedWord) => {
            ListItem() { this.wordRow(item); }
          }, (item: LearnedWord) => `${item.word.id}`)
        }
      }.lanes(this.columnCount(), 14)
        .padding({ left: this.pagePadding(), right: this.pagePadding() }).width('100%').height('100%')
        .constraintSize({ maxWidth: PAGE_MAX_WIDTH }).scrollBar(this.pageWidth >= 600 ? BarState.Auto : BarState.Off)
        .contentStartOffset(66 + this.topInset).contentEndOffset(bottomContentOffset(this.getUIContext()))
        .onReachEnd(() => {
          if (this.ready && this.dates.length > 0) { this.loadWords(false); }
        })
    }.width('100%').height('100%').alignItems(HorizontalAlign.Center)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.background'))
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.pageWidth = Number(area.width);
      })
  }
}
