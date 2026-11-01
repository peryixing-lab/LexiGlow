import { Word } from '../model/AppModels';
import { AlphabetWordIndex, AlphabetWordRow, WORD_ALPHABET, alphabetRowForLetter, buildWordAlphabet } from '../utils/WordAlphabet';

class AlphabetWordSource implements IDataSource {
  private rows: AlphabetWordRow[] = [];
  private listeners: DataChangeListener[] = [];
  private revision: number = 0;
  totalCount(): number { return this.rows.length; }
  getData(index: number): AlphabetWordRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  setData(rows: AlphabetWordRow[]): void {
    this.revision++;
    rows.forEach((row: AlphabetWordRow) => { row.key = `${this.revision}:${row.key}`; });
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}

/** One scrolling list owns its header and virtual rows, so several thousand words stay accessible. */
@ComponentV2
export struct AlphabetWordList {
  @Param words: Word[] = [];
  @Param columns: number = 1;
  @Param contentStartOffset: number = 0;
  @Param contentEndOffset: number = 24;
  @Param loading: boolean = false;
  @Event onOpenWord: (id: number) => void = () => {};
  @BuilderParam header: () => void = this.emptyHeader;
  @Local alphabet: string[] = WORD_ALPHABET.slice();
  @Local selectedLetter: number = 0;
  @Local rowCount: number = 0;
  private index: AlphabetWordIndex = new AlphabetWordIndex();
  private source: AlphabetWordSource = new AlphabetWordSource();
  private scroller: Scroller = new Scroller();
  private listMounted: boolean = false;

  aboutToAppear(): void { this.reload(); }
  aboutToDisappear(): void { this.listMounted = false; }

  @Monitor('words', 'columns')
  private onWordsChanged(): void { this.reload(); }

  private reload(): void {
    this.index = buildWordAlphabet(this.words, this.columns);
    this.alphabet = this.index.letters;
    this.rowCount = this.index.rows.length;
    this.selectedLetter = this.rowCount > 0 ? this.alphabet.indexOf(this.index.rows[0].letter) : 0;
    this.source.setData(this.index.rows);
    if (this.listMounted) { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
  }

  private jumpTo(index: number): void {
    if (index < 0 || index >= this.alphabet.length) { return; }
    const row = alphabetRowForLetter(this.index, this.alphabet[index]);
    if (row < 0) { return; }
    this.selectedLetter = this.alphabet.indexOf(this.index.rows[row].letter);
    // The optional header always occupies the first ListItem.
    this.scroller.scrollToIndex(row + 1, false, ScrollAlign.START);
  }

  private syncLetter(start: number): void {
    if (this.rowCount === 0) { return; }
    const row = this.index.rows[Math.min(this.rowCount - 1, Math.max(0, start - 1))];
    const selected = this.alphabet.indexOf(row.letter);
    if (selected >= 0 && selected !== this.selectedLetter) { this.selectedLetter = selected; }
  }

  @Builder
  private emptyHeader() { Row().height(0) }

  @Builder
  private wordCard(word: Word) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text(word.word).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(word.meaning || '释义暂缺').fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
          .width('100%').height(44).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height(118).padding(18).backgroundColor($r('app.color.surface')).borderRadius(18)
      .hoverEffect(HoverEffect.Auto).focusable(true).accessibilityText(`${word.word}，${word.meaning}，查看单词详情`)
      .onClick(() => { this.onOpenWord(word.id); })
  }

  @Builder
  private wordRow(row: AlphabetWordRow) {
    Column({ space: 8 }) {
      if (row.firstInLetter) {
        Text(row.letter).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
          .width('100%').padding({ top: 10, bottom: 2 }).accessibilityText(`${row.letter} 开头的单词`)
      }
      Row({ space: 12 }) {
        ForEach(row.words, (word: Word) => {
          Column() { this.wordCard(word) }.layoutWeight(1)
        }, (word: Word) => word.id.toString())
        if (row.words.length < this.columns) {
          ForEach([0, 1, 2].slice(row.words.length, Math.max(1, Math.min(3, Math.floor(this.columns)))), (slot: number) => {
            Column().layoutWeight(1)
          }, (slot: number) => slot.toString())
        }
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Row({ space: 4 }) {
      List({ space: 10, scroller: this.scroller }) {
        ListItem() { this.header() }
        LazyForEach(this.source, (row: AlphabetWordRow) => {
          ListItem() { this.wordRow(row) }
        }, (row: AlphabetWordRow) => row.key)
        if (!this.loading && this.rowCount === 0) {
          ListItem() {
            Text('没有匹配的单词，试试其他英文或中文关键词。').fontSize(15).lineHeight(25)
              .fontColor($r('app.color.text_secondary')).padding({ top: 36, bottom: 36 }).width('100%')
          }
        }
        if (!this.loading && this.rowCount > 0) {
          ListItem() {
            Text(`共 ${this.words.length.toLocaleString()} 个单词`).fontSize(12).fontColor($r('app.color.text_secondary'))
              .width('100%').padding({ top: 10, bottom: 12 })
          }
        }
      }.layoutWeight(1).height(LayoutPolicy.matchParent).cachedCount(3).scrollBar(BarState.Auto)
        .contentStartOffset(this.contentStartOffset).contentEndOffset(this.contentEndOffset)
        .onAppear(() => { this.listMounted = true; }).onDisAppear(() => { this.listMounted = false; })
        .onScrollIndex((start: number, _end: number, _center: number) => { this.syncLetter(start); })
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      if (this.rowCount > 0) {
        Column() {
          AlphabetIndexer({ arrayValue: this.alphabet, selected: this.selectedLetter })
            .selected(this.selectedLetter).itemSize(20).font({ size: 11, weight: FontWeight.Medium })
            .color($r('app.color.text_secondary')).selectedColor($r('app.color.text_primary'))
            .selectedBackgroundColor($r('app.color.glow')).popupColor($r('app.color.text_primary'))
            .popupBackground($r('app.color.surface')).usingPopup(true).autoCollapse(true)
            .alignStyle(IndexerAlign.Right).height('92%').onSelect((index: number) => { this.jumpTo(index); })
            .accessibilityText('A 至 Z 单词快速定位，滑动或点按字母跳转')
        }.width(30).height('100%').justifyContent(FlexAlign.Center)
          .padding({ top: Math.min(100, this.contentStartOffset), bottom: Math.min(60, this.contentEndOffset) })
      }
    }.width('100%').height(LayoutPolicy.matchParent).alignItems(VerticalAlign.Top)
  }
}
