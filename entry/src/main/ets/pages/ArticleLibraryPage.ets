import { common } from '@kit.AbilityKit';
import { ArticleSummary, ReadingRecommendation } from '../model/ArticleModels';
import { ArticleService } from '../service/ArticleService';
import { ArticleImportService } from '../service/ArticleImportService';
import { MAX_ARTICLE_CHARACTERS, MAX_ARTICLES } from '../utils/ArticleTokenizer';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';
import { PAGE_MAX_WIDTH, pageHorizontalPadding } from '../utils/ResponsiveLayout';
import { dateKey } from '../utils/TimeUtils';

@ComponentV2
export struct ArticleLibraryPage {
  @Param topInset: number = 0;
  @Event onOpenArticle: (id: number) => void = () => {};
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  @Local pageWidth: number = 0;
  @Local recommendations: ReadingRecommendation[] = [];
  @Local recommendationError: string = '';
  @Local articles: ArticleSummary[] = [];
  @Local draftTitle: string = '';
  @Local draftBody: string = '';
  @Local ready: boolean = false;
  @Local busy: boolean = false;
  @Local error: string = '';
  private requestVersion: number = 0;

  aboutToAppear(): void { this.load(); this.loadRecommendations(); }
  aboutToDisappear(): void { this.requestVersion++; this.busy = false; }

  private async load(): Promise<void> {
    const version = ++this.requestVersion;
    this.error = '';
    try {
      const articles = await ArticleService.getInstance().list();
      if (version === this.requestVersion) { this.articles = articles; }
    } catch (error) {
      if (version === this.requestVersion) { this.error = (error as Error).message || '文章库暂时没能载入，请重试。'; }
    } finally { if (version === this.requestVersion) { this.ready = true; } }
  }

  private async loadRecommendations(): Promise<void> {
    const version = this.requestVersion;
    try {
      const recommendations = await ArticleService.getInstance().recommendations();
      if (version === this.requestVersion) { this.recommendations = recommendations; this.recommendationError = ''; }
    } catch { if (version === this.requestVersion) { this.recommendationError = '精选推荐暂未载入，点此重试'; } }
  }

  private async selectFile(): Promise<void> {
    if (this.busy) { return; }
    const version = this.requestVersion;
    this.busy = true; this.error = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const draft = await ArticleImportService.importFile(context);
      if (version !== this.requestVersion || !draft) { return; }
      this.draftTitle = draft.title; this.draftBody = draft.body;
    } catch (error) {
      if (version === this.requestVersion) { this.error = (error as Error).message || '文章无法读取，请重试。'; }
    } finally { if (version === this.requestVersion) { this.busy = false; } }
  }

  private async saveDraft(): Promise<void> {
    if (this.busy) { return; }
    const version = this.requestVersion;
    this.busy = true; this.error = '';
    try {
      const id = await ArticleService.getInstance().save(this.draftTitle, this.draftBody);
      if (version !== this.requestVersion) { return; }
      this.draftTitle = ''; this.draftBody = '';
      const articles = await ArticleService.getInstance().list();
      if (version === this.requestVersion) { this.articles = articles; this.busy = false; this.onOpenArticle(id); }
    } catch (error) {
      if (version === this.requestVersion) { this.error = (error as Error).message || '文章未能保存，请重试。'; }
    } finally { if (version === this.requestVersion) { this.busy = false; } }
  }

  private confirmRemove(article: ArticleSummary): void {
    if (this.busy) { return; }
    this.getUIContext().showAlertDialog({
      title: '删除文章', message: `删除「${article.title}」？已收藏的原句、备注和生词会保留，但无法再跳回这篇文章。`,
      buttons: [
        { value: '保留', action: () => {} },
        { value: '删除', fontColor: $r('app.color.strength_low'), action: () => { this.remove(article.id); } }
      ]
    });
  }

  private async remove(id: number): Promise<void> {
    if (this.busy) { return; }
    const version = this.requestVersion;
    this.busy = true; this.error = '';
    try {
      await ArticleService.getInstance().remove(id);
      const articles = await ArticleService.getInstance().list();
      if (version === this.requestVersion) { this.articles = articles; }
    } catch (error) {
      if (version === this.requestVersion) { this.error = (error as Error).message || '文章未能删除，请重试。'; }
    } finally { if (version === this.requestVersion) { this.busy = false; } }
  }

  @Builder
  private importEditor() {
    Column({ space: 14 }) {
      Text('在文章里遇见单词').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text('粘贴英文文章或导入 TXT / DOCX，点词查看本机词典。每篇最多 60,000 字符，可保存 20 篇。')
        .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.draftTitle, placeholder: '文章标题（可选）' }).height(48).maxLength(80)
        .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).borderRadius(14)
        .onChange((value: string) => { this.draftTitle = value; })
      TextArea({ text: this.draftBody, placeholder: '在这里粘贴文章正文…' }).height(190).maxLength(60001)
        .fontSize(16).backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
        .borderRadius(16).onChange((value: string) => { this.draftBody = value; })
        .accessibilityText('粘贴文章正文')
      Row() {
        Text(`${this.draftBody.length.toLocaleString()} / 60,000`).fontSize(12)
          .fontColor(this.draftBody.length > MAX_ARTICLE_CHARACTERS ? $r('app.color.strength_low') : $r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(`${this.articles.length} / ${MAX_ARTICLES} 篇`).fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      Row({ space: 12 }) {
        Button('选择文件', { type: ButtonType.Normal }).height(48).layoutWeight(1).borderRadius(14)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).enabled(!this.busy)
          .onClick(() => { this.selectFile(); })
        Button(this.busy ? '正在处理…' : '保存并阅读', { type: ButtonType.Normal }).height(48).layoutWeight(1)
          .borderRadius(14).backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
          .enabled(!this.busy && this.ready && this.draftBody.trim().length > 0)
          .onClick(() => { this.saveDraft(); })
      }.width('100%')
      if (this.error) {
        Text(this.error).fontSize(14).lineHeight(23).fontColor($r('app.color.strength_low')).width('100%')
      }
      Text('我的文章').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .padding({ top: 16 }).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 12 })
  }

  @Builder
  private articleRow(article: ArticleSummary) {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 9 }) {
          Text(article.title).fontSize(19).fontWeight(FontWeight.Medium).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_primary'))
          Text(`${article.characterCount.toLocaleString()} 字符 · ${dateKey(article.createdAt)}`).fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).padding({ top: 18, bottom: 18, left: 18, right: 4 }).backgroundColor(Color.Transparent)
        .accessibilityText(`阅读 ${article.title}`).onClick(() => { if (!this.busy) { this.onOpenArticle(article.id); } })
      Button('删除', { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(12)
        .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).enabled(!this.busy)
        .accessibilityText(`删除 ${article.title}`).onClick(() => { this.confirmRemove(article); })
    }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(18).padding({ right: 8 })
  }

  build() {
    Column() {
      List({ space: 12 }) {
        ListItem() {
          Column({ space: 14 }) {
            Text('今日读得懂').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Text('从学过的词出发，读一小段生活。覆盖率按不同词形计算，只反映已学记录，不代表理解程度。')
              .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%')
            if (this.recommendationError) { Button(this.recommendationError).onClick(() => { this.loadRecommendations(); }) }
          }.width('100%')
        }
        ForEach(this.recommendations, (item: ReadingRecommendation) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 12 }) {
                Text(item.article.title).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                Text(`${item.learnedCount} 个词形有已学记录 · 覆盖 ${item.coverage}%`).fontSize(14).fontColor($r('app.color.text_secondary'))
                Text(`留意这几个词：${item.focusWords.join(' · ')}`).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary'))
                Text(item.completed ? '已读完 · 再读一次 →' : item.paragraphIndex > 0 ? '接着上次读 →' : '开始阅读 · 约 2 分钟 →')
                  .fontSize(15).fontColor($r('app.color.success'))
              }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
              .onClick(() => { this.onOpenArticle(item.article.id); })
          }
        }, (item: ReadingRecommendation) => item.article.id.toString())
        ListItem() { this.importEditor() }
        if (!this.ready) {
          ListItem() { LoadingProgress().width(32).height(32).color($r('app.color.success')) }
        } else if (this.articles.length === 0) {
          ListItem() {
            Text('还没有文章。导入一篇，开始阅读吧。').fontSize(15).lineHeight(25).padding(24)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        ForEach(this.articles, (article: ArticleSummary) => {
          ListItem() { this.articleRow(article) }
        }, (article: ArticleSummary) => article.id.toString())
      }.width('100%').height(LayoutPolicy.matchParent).constraintSize({ maxWidth: PAGE_MAX_WIDTH })
        .padding({ left: pageHorizontalPadding(this.pageWidth), right: pageHorizontalPadding(this.pageWidth) })
        .contentEndOffset(24 + this.windowState.bottomInset)
        .scrollBar(this.pageWidth >= 600 ? BarState.Auto : BarState.Off)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    }.width('100%').height(LayoutPolicy.matchParent).alignItems(HorizontalAlign.Center)
      .padding({ top: 66 + this.topInset })
      .background($r('app.color.background')).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .onVisibleAreaChange([0, 1], (visible: boolean) => { if (visible && this.ready) { this.loadRecommendations(); } })
      .onAreaChange((_oldArea: Area, area: Area) => { this.pageWidth = Number(area.width); })
  }
}
