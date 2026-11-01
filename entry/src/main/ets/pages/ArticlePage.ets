import { SentenceMemory } from '../model/ExperienceModels';
import { ExperienceService } from '../service/ExperienceService';
import { ReadingRecallPanel } from '../components/ReadingRecallPanel';
import { originalSentence, experienceId } from '../utils/ExperienceUtils';
import { Article } from '../model/ArticleModels';
import { Word, WordProgress } from '../model/AppModels';
import { ArticleService } from '../service/ArticleService';
import { LearningService } from '../service/LearningService';
import { AudioService } from '../service/AudioService';
import { ArticleParagraph, ArticleToken, articleParagraphs } from '../utils/ArticleTokenizer';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';
import { PAGE_MAX_WIDTH, pageHorizontalPadding } from '../utils/ResponsiveLayout';

class ArticleParagraphSource implements IDataSource {
  private paragraphs: ArticleParagraph[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.paragraphs.length; }
  getData(index: number): ArticleParagraph { return this.paragraphs[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  setData(paragraphs: ArticleParagraph[]): void {
    this.paragraphs = paragraphs;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}

@ComponentV2
struct ArticleParagraphView {
  @Param paragraph: ArticleParagraph = new ArticleParagraph('', []);
  @Event onOpenWord: (spelling: string, paragraphKey: string, tokenStart: number) => void = () => {};
  @Local mastered: string[] = [];
  private requestVersion: number = 0;
  aboutToAppear(): void { this.loadStrengths(); }
  aboutToDisappear(): void { this.requestVersion++; }

  private async loadStrengths(): Promise<void> {
    const version = ++this.requestVersion;
    const spellings = this.paragraph.tokens.filter((token: ArticleToken) => token.spelling.length > 0)
      .map((token: ArticleToken) => token.spelling);
    try {
      const strengths = await ArticleService.getInstance().paragraphStrengths(spellings);
      if (version !== this.requestVersion) { return; }
      const mastered: string[] = [];
      strengths.forEach((strength: number, spelling: string) => { if (strength >= 75) { mastered.push(spelling); } });
      this.mastered = mastered;
    } catch (_) { /* Reading remains available if learning marks cannot be loaded. */ }
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      ForEach(this.paragraph.tokens, (token: ArticleToken) => {
        if (token.spelling) {
          Text(token.text).fontSize(19).lineHeight(34).fontColor($r('app.color.text_primary'))
            .decoration({ type: this.mastered.indexOf(token.spelling) >= 0 ? TextDecorationType.Underline : TextDecorationType.None,
              color: $r('app.color.divider') })
            .constraintSize({ maxWidth: '100%' }).focusable(true)
            .accessibilityText(`${token.text}，点按查看释义${this.mastered.indexOf(token.spelling) >= 0 ? '，已掌握' : ''}`)
            .onClick(() => { this.onOpenWord(token.spelling, this.paragraph.key, token.start); })
        } else {
          Text(token.text).fontSize(19).lineHeight(34).fontColor($r('app.color.text_primary'))
            .constraintSize({ maxWidth: '100%' })
        }
      }, (token: ArticleToken) => token.start.toString())
    }.width('100%').padding({ bottom: 14 })
  }
}

@ComponentV2
export struct ArticlePage {
  @Param sourceKey: string = '';
  @Local initialParagraph: number = 0;
  @Local memory: SentenceMemory = new SentenceMemory();
  @Local noteDraft: string = '';
  @Local memorySaved: boolean = false;
  @Local memorySaving: boolean = false;
  @Local positionError: string = '';
  private lastParagraph: number = 0;
  private readingScroller: Scroller = new Scroller();
  private restoreTimer: number = -1;
  private positionRestored: boolean = false;
  private positionTimer: number = -1;
  @Param articleId: number = 0;
  @Param topInset: number = 0;
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  @Local pageWidth: number = 0;
  @Local article: Article = new Article();
  @Local ready: boolean = false;
  @Local error: string = '';
  @Local sheetOpen: boolean = false;
  @Local spelling: string = '';
  @Local selectedWord: Word = new Word();
  @Local selectedProgress: WordProgress = new WordProgress();
  @Local lookupLoading: boolean = false;
  @Local lookupError: string = '';
  @Local flagSaving: boolean = false;
  private source: ArticleParagraphSource = new ArticleParagraphSource();
  private requestVersion: number = 0;
  private wordVersion: number = 0;
  private ownsSpeech: boolean = false;
  private speechVersion: number = 0;

  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void {
    if (this.restoreTimer >= 0) { clearTimeout(this.restoreTimer); this.restoreTimer = -1; }
    this.flushPosition();
    this.requestVersion++; this.wordVersion++; this.sheetOpen = false;
    this.stopSpeech();
  }

  private async load(): Promise<void> {
    const version = ++this.requestVersion;
    if (this.restoreTimer >= 0) { clearTimeout(this.restoreTimer); this.restoreTimer = -1; }
    this.ready = false; this.error = ''; this.positionRestored = false;
    try {
      const article = await ArticleService.getInstance().get(this.articleId);
      if (version !== this.requestVersion) { return; }
      if (!article) { this.error = '这篇文章已不存在，可以返回文章库重新选择。'; return; }
      const progress = await ExperienceService.getInstance().reading(article.id);
      if (version !== this.requestVersion) { return; }
      const paragraphs = articleParagraphs(article.body);
      const sourceIndex = paragraphs.findIndex((paragraph: ArticleParagraph) => paragraph.key === this.sourceKey);
      this.initialParagraph = sourceIndex >= 0 ? sourceIndex : Math.min(progress.paragraphIndex, Math.max(0, paragraphs.length - 1));
      this.lastParagraph = this.initialParagraph;
      this.article = article; this.source.setData(paragraphs);
    } catch (error) {
      if (version === this.requestVersion) { this.error = (error as Error).message || '文章未能载入，请重试。'; }
    } finally { if (version === this.requestVersion) { this.ready = true; } }
  }

  private async openWord(spelling: string, paragraphKey: string = '0:0', tokenStart: number = 0): Promise<void> {
    this.stopSpeech();
    const version = ++this.wordVersion;
    this.memory = new SentenceMemory(); this.memorySaved = false; this.memorySaving = false; this.noteDraft = '';
    this.spelling = spelling; this.selectedWord = new Word(); this.selectedProgress = new WordProgress();
    this.lookupLoading = true; this.lookupError = ''; this.flagSaving = false; this.sheetOpen = true;
    try {
      const word = await ArticleService.getInstance().lookup(spelling);
      if (version !== this.wordVersion) { return; }
      if (!word) { this.lookupError = '词典未收录该单词或变形。常见词尾会自动尝试还原，不规则变形暂不支持。'; return; }
      this.selectedWord = word;
      const progress = await LearningService.getInstance().getProgress(word.id);
      const sentence = originalSentence(this.article.body, paragraphKey, tokenStart);
      const memories = await ExperienceService.getInstance().sentences(word.id);
      if (version !== this.wordVersion) { return; }
      this.selectedProgress = progress;
      const existing = memories.find((item: SentenceMemory) => item.articleId === this.article.id && item.paragraphKey === paragraphKey && item.sentence === sentence);
      const memory = existing || new SentenceMemory();
      if (!existing) {
        memory.id = experienceId('sentence'); memory.wordId = word.id; memory.articleId = this.article.id;
        memory.articleTitle = this.article.title; memory.paragraphKey = paragraphKey; memory.sentence = sentence; memory.createdAt = Date.now();
      }
      this.memory = memory; this.memorySaved = existing !== undefined; this.noteDraft = memory.note;
    } catch (error) {
      if (version === this.wordVersion) { this.lookupError = (error as Error).message || '释义未能载入，请再点一次。'; }
    } finally { if (version === this.wordVersion) { this.lookupLoading = false; } }
  }

  private closeWord(): void {
    this.wordVersion++; this.sheetOpen = false;
    this.stopSpeech();
  }

  private stopSpeech(): void {
    this.speechVersion++;
    if (this.ownsSpeech) { AudioService.getInstance().stop(); this.ownsSpeech = false; }
  }

  private async speak(): Promise<void> {
    const version = this.wordVersion;
    const speechVersion = ++this.speechVersion;
    this.ownsSpeech = true;
    try { await AudioService.getInstance().speak(this.selectedWord.word || this.spelling, 'en-US'); }
    catch (error) {
      if (version === this.wordVersion) { this.lookupError = (error as Error).message || '发音暂时无法播放'; }
    } finally { if (speechVersion === this.speechVersion) { this.ownsSpeech = false; } }
  }

  private async setFlag(favorite: boolean): Promise<void> {
    if (this.flagSaving || this.selectedWord.id <= 0 || this.lookupLoading) { return; }
    const version = this.wordVersion;
    const id = this.selectedWord.id;
    this.flagSaving = true; this.lookupError = '';
    try {
      const service = LearningService.getInstance();
      if (favorite) { await service.setFavorite(id, !this.selectedProgress.favorite); }
      else { await service.setNewWord(id, !this.selectedProgress.isNewWord); }
      const progress = await service.getProgress(id);
      if (version === this.wordVersion) { this.selectedProgress = progress; }
    } catch (error) {
      if (version === this.wordVersion) { this.lookupError = (error as Error).message || '单词未能保存，请重试。'; }
    } finally { if (version === this.wordVersion) { this.flagSaving = false; } }
  }

  private async saveMemory(): Promise<void> {
    if (this.memorySaving || this.lookupLoading || !this.memory.sentence) { return; }
    const version = this.wordVersion; this.memorySaving = true; this.lookupError = '';
    const memory = JSON.parse(JSON.stringify(this.memory)) as SentenceMemory; memory.note = this.noteDraft;
    try {
      await ExperienceService.getInstance().saveSentence(memory);
      if (version === this.wordVersion) { this.memory = memory; this.memorySaved = true; }
    } catch (error) { if (version === this.wordVersion) { this.lookupError = (error as Error).message || '原句未能保存，请重试。'; } }
    finally { if (version === this.wordVersion) { this.memorySaving = false; } }
  }

  private restorePosition(): void {
    if (this.positionRestored || this.restoreTimer >= 0 || !this.ready) { return; }
    const version = this.requestVersion;
    this.restoreTimer = setTimeout(() => {
      this.restoreTimer = -1;
      if (version !== this.requestVersion || !this.ready) { return; }
      this.readingScroller.scrollToIndex(this.initialParagraph > 0 || this.sourceKey ? this.initialParagraph + 1 : 0,
        false, ScrollAlign.START);
      this.positionRestored = true;
    }, 100);
  }

  private moved(start: number): void {
    if (!this.positionRestored || !this.ready || !this.article.id) { return; }
    this.lastParagraph = Math.max(0, Math.min(this.source.totalCount() - 1, start - 1));
    if (this.positionTimer >= 0) { clearTimeout(this.positionTimer); }
    this.positionTimer = setTimeout(() => { this.flushPosition(); }, 350);
  }

  private flushPosition(): void {
    if (this.positionTimer >= 0) { clearTimeout(this.positionTimer); this.positionTimer = -1; }
    if (!this.ready || !this.article.id) { return; }
    const version = this.requestVersion;
    ArticleService.getInstance().savePosition(this.article.id, this.lastParagraph)
      .then(() => { if (version === this.requestVersion) { this.positionError = ''; } })
      .catch(() => { if (version === this.requestVersion) { this.positionError = '阅读位置暂未保存，点此重试'; } });
  }

  @Builder
  private wordSheet() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.selectedWord.word || this.spelling).fontSize(30).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        if (this.lookupLoading && this.selectedWord.id === 0) {
          LoadingProgress().width(30).height(30).color($r('app.color.success'))
        } else if (this.selectedWord.id > 0) {
          if (this.selectedWord.word.toLowerCase() !== this.spelling) {
            Text(`「${this.spelling}」匹配到 ${this.selectedWord.word}`).fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          Text(this.selectedWord.phonetic || '音标暂缺').fontSize(16).fontColor($r('app.color.text_secondary'))
          Text(this.selectedWord.meaning).fontSize(19).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
          if (this.selectedWord.example) {
            Text(this.selectedWord.example).fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
            if (this.selectedWord.translation) {
              Text(this.selectedWord.translation).fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          } else {
            Text('本机词典暂未收录例句。').fontSize(13).fontColor($r('app.color.text_secondary'))
          }
        }
        if (this.selectedWord.id > 0 && this.memory.sentence) {
          Text('把遇见它的这句话留下').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.memory.sentence).fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
          TextArea({ text: this.noteDraft, placeholder: '写一句自己的记忆备注（可选）' }).height(90).maxLength(500)
            .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
            .onChange((text: string) => { this.noteDraft = text; })
          Button(this.memorySaved ? '已收藏原句 · 保存备注' : '收藏这条原句').height(48).width('100%')
            .backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
            .enabled(!this.memorySaving && !this.lookupLoading).onClick(() => { this.saveMemory(); })
        }
        if (this.lookupError) {
          Text(this.lookupError).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('朗读').height(46).fontSize(14).backgroundColor($r('app.color.glow'))
            .fontColor($r('app.color.text_primary')).margin({ right: 10, bottom: 10 })
            .onClick(() => { this.speak(); })
          if (this.selectedWord.id > 0) {
            Button(this.selectedProgress.favorite ? '★ 已收藏' : '☆ 收藏').height(46).fontSize(14)
              .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
              .margin({ right: 10, bottom: 10 }).enabled(!this.flagSaving && !this.lookupLoading)
              .onClick(() => { this.setFlag(true); })
            Button(this.selectedProgress.isNewWord ? '已加入生词本' : '+ 生词本').height(46).fontSize(14)
              .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
              .margin({ right: 10, bottom: 10 }).enabled(!this.flagSaving && !this.lookupLoading)
              .onClick(() => { this.setFlag(false); })
          }
        }.width('100%')
      }.width('100%').padding({ left: 24, right: 24, top: 28, bottom: 24 + this.windowState.bottomInset })
        .alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  build() {
    Column() {
      if (this.ready && this.article.id !== 0) {
      List({ space: 4, scroller: this.readingScroller, initialIndex: this.initialParagraph > 0 || this.sourceKey ? this.initialParagraph + 1 : 0 }) {
        ListItem() {
          Column({ space: 12 }) {
            Text(this.article.title || '文章阅读').fontSize(28).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary')).width('100%')
            Text('点按英文单词查看释义 · 浅色下划线表示已掌握').fontSize(13).lineHeight(23)
              .fontColor($r('app.color.text_secondary')).width('100%')
            if (this.article.source) { Text(this.article.source).fontSize(12).fontColor($r('app.color.text_secondary')) }
            if (this.positionError) { Button(this.positionError).onClick(() => { this.flushPosition(); }) }
            if (!this.ready) { LoadingProgress().width(32).height(32).color($r('app.color.success')) }
            if (this.error) {
              Text(this.error).fontSize(15).lineHeight(25).fontColor($r('app.color.text_secondary'))
              Button('重新载入').height(46).backgroundColor($r('app.color.glow'))
                .fontColor($r('app.color.text_primary')).onClick(() => { this.load(); })
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding({ bottom: 20 })
        }
        LazyForEach(this.source, (paragraph: ArticleParagraph) => {
          ListItem() { ArticleParagraphView({ paragraph: paragraph, onOpenWord: (spelling: string, key: string, start: number) => { this.openWord(spelling, key, start); } }) }
        }, (paragraph: ArticleParagraph) => paragraph.key)
        ListItem() { ReadingRecallPanel({ article: this.article }) }
      }.width('100%').height(LayoutPolicy.matchParent).constraintSize({ maxWidth: PAGE_MAX_WIDTH }).cachedCount(2)
        .onAreaChange(() => { this.restorePosition(); })
        .onScrollIndex((start: number) => { this.moved(start); })
        .padding({ left: pageHorizontalPadding(this.pageWidth), right: pageHorizontalPadding(this.pageWidth) })
        .contentEndOffset(24 + this.windowState.bottomInset)
        .scrollBar(this.pageWidth >= 600 ? BarState.Auto : BarState.Off)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      } else {
        Column({ space: 18 }) {
          if (!this.ready) { LoadingProgress().width(36).height(36) }
          Text(this.error || '正在载入文章…').fontColor($r('app.color.text_secondary'))
          if (this.error) { Button('重新载入').onClick(() => { this.load(); }) }
        }.padding({ top: 100, left: 24, right: 24 })
      }
    }.width('100%').height(LayoutPolicy.matchParent).alignItems(HorizontalAlign.Center)
      .padding({ top: 66 + this.topInset })
      .background($r('app.color.background')).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .onAreaChange((_oldArea: Area, area: Area) => { this.pageWidth = Number(area.width); })
      .bindSheet(this.sheetOpen, this.wordSheet, {
        height: SheetSize.MEDIUM, detents: [SheetSize.MEDIUM, SheetSize.LARGE], preferType: SheetType.BOTTOM,
        showClose: true, dragBar: true, backgroundColor: $r('app.color.surface'),
        onDisappear: () => { this.closeWord(); }
      })
  }
}
