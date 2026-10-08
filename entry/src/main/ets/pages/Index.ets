import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { CommonModifier, LengthMetrics, uiMaterial } from '@kit.ArkUI';
import { AppSnapshot, Word, WordProgress, WordBook, ReviewRecord, ReviewResult, StudySession, StudyItem, UserSettings, DaySummary } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { AudioService } from '../service/AudioService';
import { FormService } from '../service/FormService';
import { ReminderService } from '../service/ReminderService';
import { TransferService } from '../service/TransferService';
import { ImmersiveDock } from '../components/ImmersiveDock';
import { PrimaryNavigation } from '../components/PrimaryNavigation';
import { dailyPlanProgress, isDailyPlanComplete } from '../utils/DailyPlanUtils';
import { strengthName } from '../utils/MemoryUtils';
import { MeaningChallengePage } from './MeaningChallengePage';
import { LearnedWordsPage } from './LearnedWordsPage';
import { bottomContentOffset } from '../utils/SafeAreaUtils';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';
import { PAGE_MAX_WIDTH, pageHorizontalPadding, primaryNavigationRailWidth, responsiveColumnCount, responsiveCardWidth, usesTopNavigation, wordListColumnCount } from '../utils/ResponsiveLayout';

interface ActionOptions { label: string; action: () => void; primary: boolean; }
interface HeadingOptions { title: string; subtitle: string; id?: string; }
interface HeaderOptions { title: string; action: () => void; }
interface StatOptions { value: string; label: string; highlighted?: boolean; }
interface ChipOptions { label: string; selected: boolean; action: () => void; }
interface BookCardOptions { book: WordBook; }
interface WordRowOptions { word: Word; }

/** lg breakpoint (>= 840vp): tablet landscape / 2in1 / folded-wide; two-column layouts. */
const BREAKPOINT_LG: number = 840;
/** md breakpoint (>= 600vp): tablet portrait / unfolded; wider single column. */
const BREAKPOINT_MD: number = 600;

@Entry
@ComponentV2
struct Index {
  @Local snapshot: AppSnapshot = new AppSnapshot();
  @Local ready: boolean = false;
  @Local error: string = '';
  @Local busy: boolean = false;
  @Local tab: number = 0;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local wordListWidth: number = 0;
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  @Local titleCollapsed: boolean[] = [false, false, false, false];
  @Local welcomeStep: number = 0;
  @Local selectedBook: string = 'cet4';
  @Local selectedTarget: number = 20;
  @Local foundation: string = 'beginner';
  @Local session: StudySession = new StudySession();
  @Local answerVisible: boolean = false;
  @Local answerOpacity: number = 0;
  @Local currentWord: Word = new Word();
  @Local currentProgress: WordProgress = new WordProgress();
  @Local history: ReviewRecord[] = [];
  @Local words: Word[] = [];
  @Local searchText: string = '';
  @Local listTitle: string = '';
  @Local listBookId: string = '';
  @Local listFilter: string = 'all';
  @Local loadingWords: boolean = false;
  @Local reminderHour: string = '21';
  @Local reminderMinute: string = '00';
  @Local examDate: string = '';
  @Local importName: string = '我的词书';
  @Local importText: string = '';
  @Local pendingWords: Word[] = [];
  @Local detailBookId: string = '';
  @Local renameText: string = '';
  @Local editIndex: number = -1;
  @Local editId: number = 0;
  @Local editHeadword: string = '';
  @Local editPhonetic: string = '';
  @Local editMeaning: string = '';
  @Local editExample: string = '';
  @Local editTranslation: string = '';
  private readonly tabScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];
  private readonly primaryTabsController: TabsController = new TabsController();
  private readonly immersivePrimaryNavigation: CommonModifier = new CommonModifier()
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  private readonly defaultPrimaryNavigation: CommonModifier = new CommonModifier();
  private readonly titleButtonMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true,
    lightEffect: { color: $r('app.color.glow_deep') }
  });
  private openingStudy: boolean = false;
  @Local summaryWords: Word[] = [];
  private pathStack: NavPathStack = new NavPathStack();
  private service: LearningService = LearningService.getInstance();
  private startedAt: number = Date.now();
  private searchTimer: number = -1;
  private searchVersion: number = 0;
  private routeListener: (route: string, wordId: number) => void = (route: string, wordId: number): void => {
    this.handleRoute(route, wordId);
  };

  aboutToAppear(): void {
    this.context().eventHub.on('openRoute', this.routeListener);
    this.initialize();
  }

  aboutToDisappear(): void {
    this.context().eventHub.off('openRoute', this.routeListener);
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    AudioService.getInstance().release();
  }

  onPageShow(): void {
    if (this.ready) { this.refresh().catch(() => {}); }
  }

  dispatchInitialRoute(): void {
    const route = AppStorage.get<string>('launchRoute') || '';
    const wordId = AppStorage.get<number>('launchWordId') || 0;
    if (route) { this.handleRoute(route, wordId); }
  }

  context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2400 });
  }

  async initialize(): Promise<void> {
    this.error = '';
    try {
      await this.service.initialize(this.context());
      await this.refresh();
      this.reminderHour = `${this.snapshot.settings.reminderHour}`;
      this.reminderMinute = this.snapshot.settings.reminderMinute.toString().padStart(2, '0');
      this.examDate = this.snapshot.settings.examDate;
      this.applyTheme();
      this.ready = true;
    } catch (err) {
      this.error = '本地词库暂时没能打开，请重试。你的学习记录会保留。';
    }
  }

  async refresh(): Promise<void> {
    this.snapshot = await this.service.getSnapshot();
    FormService.update(this.snapshot, this.context()).catch(() => {});
  }

  applyTheme(): void {
    const mode = this.snapshot.settings.themeMode;
    this.context().getApplicationContext().setColorMode(mode === 'dark' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK : mode === 'light' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  handleRoute(route: string, wordId: number): void {
    if (!this.ready || !this.snapshot.settings.onboarded) { return; }
    AppStorage.setOrCreate('launchRoute', '');
    this.pathStack.clear();
    if (route === 'word') { this.openWord(wordId || this.snapshot.dailyWord.id); }
    else if (route === 'review' || route === 'quick' || route === 'today') { this.beginStudy(route); }
  }

  async finishOnboarding(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const settings = this.copySettings();
      settings.currentBookId = this.selectedBook;
      settings.dailyNewTarget = this.selectedTarget;
      settings.foundation = this.foundation;
      settings.learningMode = this.foundation === 'sprint' ? 'exam' : 'normal';
      settings.onboarded = true;
      await this.service.updateSettings(settings);
      await this.refresh();
      await this.beginStudy('onboarding');
    } catch (err) { this.toast('设置没有保存成功，请再试一次。'); }
    this.busy = false;
  }

  async beginStudy(mode: string): Promise<void> {
    if (!this.ready || this.openingStudy) { return; }
    this.openingStudy = true;
    try {
      this.session = await this.service.startSession(mode);
      this.answerVisible = false;
      if (this.session.items.length === 0) {
        this.toast(mode === 'review' ? '今天暂时没有到期词，可以学几个新词。' : '这本词书已经学完，可以换一本或稍后复习。');
        this.openingStudy = false;
        return;
      }
      await this.loadStudyWord();
      this.pathStack.pushPathByName('Learn', mode);
    } catch (err) { this.toast('学习队列没能载入，请重试。'); }
    this.openingStudy = false;
  }

  async loadStudyWord(): Promise<void> {
    if (this.session.index < this.session.items.length) {
      this.currentWord = this.session.items[this.session.index].word;
      this.currentProgress = await this.service.getProgress(this.currentWord.id);
      this.answerVisible = false;
      this.answerOpacity = 0;
      this.startedAt = Date.now();
      if (this.snapshot.settings.autoPronounce) {
        AudioService.getInstance().speak(this.currentWord.word).catch(() => {});
      }
    }
  }

  showAnswer(): void {
    this.answerVisible = true;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.answerOpacity = 1; });
  }

  async judge(result: ReviewResult): Promise<void> {
    if (this.busy || !this.answerVisible) { return; }
    this.busy = true;
    try {
      this.session = await this.service.record(result, Date.now() - this.startedAt);
    } catch (err) {
      this.toast('这一词还没有保存，请再点一次。'); this.busy = false; return;
    }
    this.answerVisible = false;
    await this.refresh().catch(() => {});
    if (this.session.index >= this.session.items.length) {
      AudioService.getInstance().stop();
      this.pathStack.replacePathByName('Summary', this.session.mode);
    } else {
      await this.loadStudyWord().catch(() => { this.toast('下一词暂时没能载入，可以返回后继续。'); });
    }
    this.busy = false;
  }

  async leaveStudy(): Promise<void> {
    AudioService.getInstance().stop();
    this.pathStack.pop();
    await this.refresh().catch(() => {});
  }

  async leaveSummary(): Promise<void> {
    try {
      await this.service.clearSession();
      this.summaryWords = [];
      this.pathStack.clear();
      await this.refresh();
    } catch (err) { this.toast('请再试一次。'); }
  }

  async toggleFavorite(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.service.setFavorite(this.currentWord.id, !this.currentProgress.favorite);
      this.currentProgress = await this.service.getProgress(this.currentWord.id);
      await this.refresh();
    } catch (err) { this.toast('收藏没有保存成功。'); }
    this.busy = false;
  }

  async toggleNewWord(): Promise<void> {
    try {
      await this.service.setNewWord(this.currentWord.id, !this.currentProgress.isNewWord);
      this.currentProgress = await this.service.getProgress(this.currentWord.id);
      await this.refresh();
    } catch (err) { this.toast('生词本没有保存成功。'); }
  }

  async pronounce(text: string): Promise<void> {
    try { await AudioService.getInstance().speak(text); }
    catch (err) { this.toast((err as Error).message || '当前设备的英文语音暂不可用，仍可继续学习。'); }
  }

  async copyWord(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.currentWord.word));
      this.toast('单词已复制');
    } catch (err) { this.toast('暂时无法复制'); }
  }

  async openWord(id: number, bookId: string = ''): Promise<void> {
    try {
      this.detailBookId = bookId;
      this.currentWord = bookId ? await this.service.getBookWord(bookId, id) : await this.service.getWord(id);
      this.currentProgress = await this.service.getProgress(id);
      this.history = await this.service.getHistory(id);
      this.pathStack.pushPathByName('WordDetail', id);
    } catch (err) { this.toast('这个单词暂时无法打开。'); }
  }

  async openList(title: string, bookId: string, filter: string): Promise<void> {
    this.listTitle = title;
    this.listBookId = bookId;
    this.renameText = title;
    this.listFilter = filter;
    this.searchText = '';
    this.pathStack.pushPathByName('WordList', bookId);
    await this.search();
  }

  scheduleSearch(value: string): void {
    this.searchText = value;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => { this.search(); }, 180);
  }

  async search(): Promise<void> {
    const version = ++this.searchVersion;
    this.loadingWords = true;
    try {
      const result = await this.service.getWords(this.listBookId, this.listFilter, this.searchText);
      if (version === this.searchVersion) { this.words = result; }
    } catch (err) { this.toast('搜索暂时不可用，请重试。'); }
    if (version === this.searchVersion) { this.loadingWords = false; }
  }

  copySettings(): UserSettings {
    return JSON.parse(JSON.stringify(this.snapshot.settings)) as UserSettings;
  }

  async setBook(bookId: string): Promise<void> {
    const settings = this.copySettings();
    settings.currentBookId = bookId;
    try {
      await this.service.clearSession();
      await this.service.updateSettings(settings);
      await this.refresh();
      this.toast('已切换词书，掌握进度会保留');
    } catch (err) { this.toast('切换没有完成，请再试一次。'); }
  }

  async saveTarget(target: number): Promise<void> {
    const settings = this.copySettings();
    settings.dailyNewTarget = target;
    await this.saveSettings(settings);
  }

  async saveSettings(settings: UserSettings): Promise<boolean> {
    try {
      await this.service.updateSettings(settings);
      const snapshot = JSON.parse(JSON.stringify(this.snapshot)) as AppSnapshot;
      snapshot.settings = settings; this.snapshot = snapshot;
      await this.refresh().catch(() => {});
      this.applyTheme(); return true;
    } catch (err) { this.toast('设置没有保存成功，请重试。'); return false; }
  }

  async changeTheme(theme: string): Promise<void> {
    const settings = this.copySettings(); settings.themeMode = theme; await this.saveSettings(settings);
  }

  async changeAutoPronounce(enabled: boolean): Promise<void> {
    const settings = this.copySettings(); settings.autoPronounce = enabled; await this.saveSettings(settings);
  }

  async changeMode(mode: string): Promise<void> {
    const settings = this.copySettings(); settings.learningMode = mode; await this.saveSettings(settings);
  }

  async changeBudget(budget: string): Promise<void> {
    try { await this.service.setBudget(budget); await this.refresh(); }
    catch (err) { this.toast('今日计划暂时没能更新。'); }
  }

  async saveReminder(enabled: boolean): Promise<void> {
    if (this.busy) { return; }
    const hour = Number(this.reminderHour); const minute = Number(this.reminderMinute);
    if (!Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59) {
      this.toast('请填写有效的时间：小时 0–23，分钟 0–59。'); return;
    }
    this.busy = true;
    try {
      await ReminderService.configure(this.context(), enabled, hour, minute);
      const settings = this.copySettings();
      settings.reminderEnabled = enabled; settings.reminderHour = hour; settings.reminderMinute = minute;
      const saved = await this.saveSettings(settings);
      if (!saved) { throw new Error('提醒偏好未保存，请重新设置。'); }
      this.toast(enabled ? '学习提醒已开启' : '学习提醒已关闭');
    } catch (err) { this.toast((err as Error).message || '提醒未能设置，请检查通知权限和设备支持。'); }
    this.busy = false;
  }

  async saveExamDate(): Promise<void> {
    const value = this.examDate.trim();
    if (value && (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value)))) {
      this.toast('请用 YYYY-MM-DD 填写日期。'); return;
    }
    if (value) {
      const parts = value.split('-').map((part: string) => Number(part));
      const date = new Date(parts[0], parts[1] - 1, parts[2]);
      if (date.getFullYear() !== parts[0] || date.getMonth() !== parts[1] - 1 || date.getDate() !== parts[2]) {
        this.toast('这个日期不存在，请检查月份和天数。'); return;
      }
    }
    const settings = this.copySettings(); settings.examDate = value;
    if (await this.saveSettings(settings)) { this.toast('考试日期已保存'); }
  }

  examDays(): number {
    if (!this.snapshot.settings.examDate) { return -1; }
    const parts = this.snapshot.settings.examDate.split('-').map((part: string) => Number(part));
    const now = new Date();
    return Math.ceil((new Date(parts[0], parts[1] - 1, parts[2]).getTime() -
      new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()) / 86400000);
  }

  async prepareImport(name: string, words: Word[]): Promise<void> {
    this.importName = name;
    this.pendingWords = await this.service.resolveImportWords(words);
    this.pathStack.pushPathByName('ImportPreview', '');
  }

  async importFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const book = await TransferService.importFile(this.context());
      if (book.words.length > 0) { await this.prepareImport(book.name, book.words); }
    } catch (err) {
      const message = (err as Error).message || '';
      if (!message.startsWith('已取消')) { this.toast(message || '导入未完成，请检查文件格式。'); }
    }
    this.busy = false;
  }

  async importPasted(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const book = TransferService.parse(this.importText, this.importName);
      await this.prepareImport(book.name, book.words);
    } catch (err) { this.toast((err as Error).message || '请检查单词列表格式。'); }
    this.busy = false;
  }

  unresolvedCount(): number {
    return this.pendingWords.filter((word: Word) => word.meaning.trim().length === 0).length;
  }

  previewWords(): Word[] {
    return this.unresolvedCount() > 0 ? this.pendingWords.filter((word: Word) => !word.meaning.trim()).slice(0, 100) :
      this.pendingWords.slice(0, 100);
  }

  async confirmImport(): Promise<void> {
    if (this.busy) { return; }
    if (this.unresolvedCount() > 0) { this.toast('还有单词没有释义，点开补充后再导入。'); return; }
    this.busy = true;
    try {
      const count = await this.service.importWords(this.importName, this.pendingWords);
      this.pendingWords = []; this.importText = ''; await this.refresh();
      this.pathStack.clear(); this.tab = 1; this.toast(`已导入 ${count} 个词`);
    } catch (err) { this.toast((err as Error).message || '导入未完成，请重试。'); }
    this.busy = false;
  }

  async renameBook(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      await this.service.renameBook(this.listBookId, this.renameText);
      this.listTitle = this.renameText.trim(); await this.refresh(); this.toast('词书名称已保存');
    } catch (err) { this.toast((err as Error).message || '名称没有保存成功。'); }
    this.busy = false;
  }

  editWord(word: Word, index: number = -1): void {
    this.editIndex = index; this.editId = word.id;
    this.editHeadword = word.word; this.editPhonetic = word.phonetic; this.editMeaning = word.meaning;
    this.editExample = word.example; this.editTranslation = word.translation;
    this.pathStack.pushPathByName('EditWord', '');
  }

  async saveEditedWord(): Promise<void> {
    if (this.busy) { return; }
    if (!this.editHeadword.trim() || !this.editMeaning.trim()) {
      this.toast('请填写单词和释义。'); return;
    }
    if (this.editIndex >= 0 && this.pendingWords.some((word: Word, index: number) =>
      index !== this.editIndex && word.word.toLowerCase() === this.editHeadword.trim().toLowerCase())) {
      this.toast('导入列表已经有这个单词，可以修改原来的词条。'); return;
    }
    this.busy = true;
    const word = new Word(); word.id = this.editId;
    word.word = this.editHeadword.trim(); word.phonetic = this.editPhonetic.trim(); word.meaning = this.editMeaning.trim();
    word.example = this.editExample.trim(); word.translation = this.editTranslation.trim();
    try {
      if (this.editIndex >= 0) {
        const next = this.pendingWords.slice(); next[this.editIndex] = word; this.pendingWords = next;
      } else {
        this.currentWord = await this.service.updateBookWord(this.detailBookId, this.editId, word);
        this.editId = this.currentWord.id;
        this.currentProgress = await this.service.getProgress(this.currentWord.id);
        this.history = await this.service.getHistory(this.currentWord.id);
        await this.search();
        await this.refresh();
      }
      this.pathStack.pop(); this.toast('单词内容已保存');
    } catch (err) { this.toast((err as Error).message || '内容没有保存成功。'); }
    this.busy = false;
  }

  async exportBook(format: string): Promise<void> {
    if (!this.listBookId || this.busy) { return; } this.busy = true;
    try {
      const words = await this.service.exportBook(this.listBookId);
      const path = await TransferService.exportBookFile(this.context(), this.listTitle, words, format);
      if (path) { this.toast('词书已导出'); }
    } catch (err) {
      const message = (err as Error).message || '';
      if (!message.startsWith('已取消')) { this.toast(message || '导出未完成，请重试。'); }
    }
    this.busy = false;
  }

  async exportData(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const path = await TransferService.exportFile(this.context(), await this.service.exportData());
      if (path) { this.toast('学习数据已导出'); }
    } catch (err) {
      const message = (err as Error).message || '';
      if (!message.startsWith('已取消')) { this.toast(message || '导出未完成，可以稍后重试。'); }
    }
    this.busy = false;
  }

  activeBookName(): string {
    const book = this.snapshot.books.find((book: WordBook) => book.id === this.snapshot.settings.currentBookId);
    return book ? book.name : '核心词汇';
  }

  progressValue(): number {
    return dailyPlanProgress(this.snapshot.plan);
  }

  todayComplete(): boolean {
    return isDailyPlanComplete(this.snapshot.plan);
  }

  todayActionLabel(): string {
    if (this.todayComplete()) { return '今天已完成，再学一点  →'; }
    return '继续学习  →';
  }

  strengthName(strength: number): string {
    return strengthName(strength);
  }

  resultName(result: number): string { return result === 2 ? '认识' : result === 1 ? '模糊' : '不认识'; }

  isWide(): boolean { return this.viewportWidth >= BREAKPOINT_LG; }

  isMedium(): boolean { return this.viewportWidth >= BREAKPOINT_MD; }

  useTopNavigation(): boolean { return usesTopNavigation(this.viewportWidth, deviceInfo.deviceType); }

  selectTab(index: number): void {
    if (index === this.tab) { return; }
    this.tab = index;
    this.refresh().catch(() => {});
  }

  mainPaneWidth(): number {
    // Hidden Tabs can report stale Scroll sizes; derive the pane from the current navigation layout.
    return Math.max(0, this.viewportWidth - primaryNavigationRailWidth(this.viewportWidth, deviceInfo.deviceType));
  }

  mainPagePadding(): number {
    return this.isMedium() ? pageHorizontalPadding(this.mainPaneWidth()) : 24;
  }

  mainContentWidth(): number {
    const paneWidth = this.mainPaneWidth();
    return Math.max(0, Math.min(PAGE_MAX_WIDTH, paneWidth) - this.mainPagePadding() * 2);
  }

  useHomeColumns(): boolean { return this.mainContentWidth() >= 720; }

  compactMainPage(): boolean { return this.isMedium() && this.viewportHeight < 600; }

  mainTitlePadding(): number {
    return this.mainPagePadding() + Math.max(0, (this.mainPaneWidth() - PAGE_MAX_WIDTH) / 2);
  }

  /** Exact gap-aware widths prevent a wrapped half-width card in small windows. */
  cardGridWidth(gap: number = 16, minimumWidth: number = 300, maximumColumns: number = 2): number | string {
    const width = this.mainContentWidth();
    return width > 0 ? responsiveCardWidth(width,
      responsiveColumnCount(width, minimumWidth, maximumColumns, gap), gap) : '100%';
  }

  usesLargeWordList(): boolean {
    return deviceInfo.deviceType === 'tablet' || deviceInfo.deviceType === '2in1';
  }

  wordListColumns(): number {
    if (!this.usesLargeWordList()) { return this.isWide() ? 2 : 1; }
    const width = Math.min(this.wordListWidth || this.viewportWidth, PAGE_MAX_WIDTH);
    return wordListColumnCount(Math.max(0, width - 48), 12);
  }

  wordRows(): Word[][] {
    const rows: Word[][] = [];
    const columns = this.wordListColumns();
    for (let i = 0; i < this.words.length; i += columns) {
      rows.push(this.words.slice(i, i + columns));
    }
    return rows;
  }

  handleStudyKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (this.busy) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_ENTER) {
      if (!this.answerVisible && this.session.index < this.session.items.length) { this.showAnswer(); return true; }
      return false;
    }
    if (!this.answerVisible) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_1) { this.judge(ReviewResult.FORGET); return true; }
    if (event.keyCode === KeyCode.KEYCODE_2) { this.judge(ReviewResult.FUZZY); return true; }
    if (event.keyCode === KeyCode.KEYCODE_3) { this.judge(ReviewResult.KNOW); return true; }
    return false;
  }

  completedCount(type: string): number {
    return this.session.items.slice(0, this.session.index).filter((item: StudyItem) => item.type === type).length;
  }

  @Builder
  Action($$: ActionOptions) {
    Button($$.label, { type: ButtonType.Normal })
      .fontSize(16).fontWeight(FontWeight.Medium).height(52).width('100%').borderRadius(18)
      .backgroundColor($$.primary ? $r('app.color.brand_ink') : $r('app.color.soft_surface'))
      .fontColor($$.primary ? $r('app.color.inverse_text') : $r('app.color.text_primary'))
      .enabled(!this.busy).onClick($$.action)
  }

  @Builder
  PageHeading($$: HeadingOptions) {
    Column({ space: 7 }) {
      Text($$.title).fontSize(this.compactMainPage() ? 24 : 28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text($$.subtitle).fontSize(14).fontColor($r('app.color.text_secondary')).lineHeight(22)
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: this.compactMainPage() ? 4 : 12 }).id($$.id || '')
  }

  @Builder
  BackHeader($$: HeaderOptions) {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([$r('app.color.text_primary')])
      }.width(40).height(40).padding(0)
        .systemMaterial(this.titleButtonMaterial).accessibilityText('返回').onClick($$.action)
      Text($$.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').height('100%').padding({ left: 20, right: 20 }).expandSafeArea([SafeAreaType.SYSTEM])
  }

  @Builder
  SmallStat($$: StatOptions) {
    Column({ space: 6 }) {
      Text($$.value).fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text($$.label).fontSize(12).fontColor($$.highlighted ? $r('app.color.glow_secondary') : $r('app.color.text_secondary'))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  Chip($$: ChipOptions) {
    Button($$.label, { type: ButtonType.Normal }).fontSize(14).height(44).borderRadius(14).layoutWeight(1)
      .backgroundColor($$.selected ? $r('app.color.glow') : $r('app.color.surface'))
      .fontColor($r('app.color.text_primary')).onClick($$.action)
  }

  @Builder
  Welcome() {
    Scroll() {
    Row() {
      Column({ space: 24 }) {
        Row() {
          Text('LexiGlow').fontSize(13).letterSpacing(3).fontColor($r('app.color.text_secondary'))
          Blank()
          Text(`${this.welcomeStep + 1} / 4`).fontSize(13).fontColor($r('app.color.text_secondary'))
        }.width('100%')
        if (this.welcomeStep === 0) {
          Column({ space: 24 }) {
            Image($r('app.media.ciying_icon')).width(112).height(112).borderRadius(30)
            Text('词萤').fontSize(42).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text('让单词一点一点亮起来').fontSize(21).fontColor($r('app.color.text_primary'))
            Text('每天一点光，慢慢记住更多词。\n从 3 个词开始，也是一份进步。')
              .fontSize(16).fontColor($r('app.color.text_secondary')).lineHeight(29).textAlign(TextAlign.Center)
          }.width('100%').padding({ top: 50, bottom: 48 })
          this.Action({ label: '开始点亮第一个词  →', action: () => { this.welcomeStep = 1; }, primary: true })
          Text('无需注册 · 学习记录保存在本机').fontSize(13).fontColor($r('app.color.text_secondary'))
        } else if (this.welcomeStep === 1) {
          this.PageHeading({ title: '你想向哪里出发？', subtitle: '选一本词书，之后随时可以换。' })
          ForEach(this.snapshot.books.filter((book: WordBook) => !book.id.startsWith('custom')), (book: WordBook) => {
            Button({ type: ButtonType.Normal }) {
              Row() {
                Column({ space: 5 }) {
                  Text(book.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text(`${book.totalCount} 个词`).fontSize(13).fontColor(this.selectedBook === book.id ? $r('app.color.glow_secondary') : $r('app.color.text_secondary'))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(this.selectedBook === book.id ? '●' : '○').fontSize(22).fontColor($r('app.color.text_primary'))
              }.width('100%').padding(20)
            }.width('100%').borderRadius(20).backgroundColor(this.selectedBook === book.id ?
              $r('app.color.glow') : $r('app.color.surface')).onClick(() => { this.selectedBook = book.id; })
          }, (book: WordBook) => JSON.stringify(book))
          this.Action({ label: '继续', action: () => { this.welcomeStep = 2; }, primary: true })
        } else if (this.welcomeStep === 2) {
          this.PageHeading({ title: '从你现在的节奏开始', subtitle: '没有测试，也没有标准答案。' })
          this.FoundationOption('beginner', '刚开始', '先熟悉核心词，每次只学一点。')
          this.FoundationOption('regular', '有一点基础', '新词和复习，保持一个舒服的比例。')
          this.FoundationOption('sprint', '正在冲刺', '优先稳住到期词，再认识新词。')
          this.Action({ label: '继续', action: () => { this.welcomeStep = 3; }, primary: true })
        } else {
          this.PageHeading({ title: '每天留一点时间给自己', subtitle: '先定一个小目标，忙的时候可以临时减量。' })
          Row({ space: 8 }) {
            ForEach([10, 20, 30, 50], (target: number) => {
              this.Chip({ label: `${target} 词`, selected: this.selectedTarget === target, action: () => { this.selectedTarget = target; } })
            }, (target: number) => `${target}`)
          }.width('100%')
          Column({ space: 12 }) {
            Text(`约 ${Math.ceil(this.selectedTarget * 0.4)} 分钟 / 天`).fontSize(26).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('提醒默认关闭。体验之后，可以在“我的”里选一个适合你的时间。')
              .fontSize(15).fontColor($r('app.color.text_secondary')).lineHeight(25)
          }.padding(24).width('100%').alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.surface')).borderRadius(24)
          this.Action({ label: '先体验 3 个词  →', action: () => { this.finishOnboarding(); }, primary: true })
          Text('先回忆，再看答案。忘记也是学习的一部分。').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        if (this.welcomeStep > 0) {
          Button('上一步').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
            .onClick(() => { this.welcomeStep--; })
        }
      }.padding(26).width('100%').constraintSize({ maxWidth: 620 })
    }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  @Builder
  FoundationOption(value: string, title: string, subtitle: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 9 }) {
        Text(title).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(subtitle).fontSize(14).fontColor(this.foundation === value ? $r('app.color.glow_secondary') : $r('app.color.text_secondary')).lineHeight(23)
      }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }.width('100%').borderRadius(22).backgroundColor(this.foundation === value ?
      $r('app.color.glow') : $r('app.color.surface')).onClick(() => { this.foundation = value; })
  }

  @Builder
  HomeDueCard() {
    if (this.snapshot.dueCount > 0) {
      Row({ space: 15 }) {
        Column({ space: 6 }) {
          Text('该和老朋友见面了').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(`${this.snapshot.dueCount} 个到期词 · 分几次完成也可以`).fontSize(13).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('复习 →').height(46).fontSize(14).backgroundColor($r('app.color.brand_ink'))
          .fontColor($r('app.color.inverse_text')).onClick(() => { this.beginStudy('review'); })
      }.padding(22).borderRadius(24).backgroundColor($r('app.color.surface')).width('100%')
    }
  }

  @Builder
  HomePlanCard() {
    Column({ space: this.compactMainPage() ? 14 : 18 }) {
      Row() {
        Text('今日计划').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.activeBookName()).fontSize(12).fontColor($r('app.color.glow_secondary')).maxLines(1)
      }.width('100%')
      Row({ space: 8 }) {
        Text(`${this.snapshot.plan.newDone + this.snapshot.plan.reviewDone}`).fontSize(this.compactMainPage() ? 46 : 54).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`/ ${this.snapshot.plan.newTarget + this.snapshot.plan.reviewTarget}`).fontSize(23)
          .fontColor($r('app.color.glow_secondary')).margin({ top: 18 })
        Blank()
        Text('一点点\n亮起来').fontSize(13).lineHeight(21).fontColor($r('app.color.glow_secondary'))
      }.width('100%')
      Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
        .color($r('app.color.brand_ink')).backgroundColor($r('app.color.glow_track')).style({ strokeWidth: 6 })
      Row() {
        Text(`新词 ${this.snapshot.plan.newDone}/${this.snapshot.plan.newTarget} · 复习 ${this.snapshot.plan.reviewDone}/${this.snapshot.plan.reviewTarget} 次`)
          .fontSize(13).fontColor($r('app.color.glow_secondary'))
        Blank()
        Text(`约 ${this.snapshot.plan.estimatedMinutes} 分钟`).fontSize(13).fontColor($r('app.color.glow_secondary'))
      }.width('100%')
      this.Action({ label: this.todayActionLabel(), action: () => { this.beginStudy(this.todayComplete() ? 'quick' : 'today'); }, primary: true })
    }.padding(this.compactMainPage() ? 20 : 24).width('100%').backgroundColor($r('app.color.glow')).borderRadius(28)
  }

  @Builder
  HomeQuickCards() {
    Flex({
      direction: FlexDirection.Row,
      alignItems: ItemAlign.Stretch,
      space: { main: LengthMetrics.vp(12) }
    }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 9 }) {
          Text('↗').fontSize(26).fontColor($r('app.color.text_primary'))
          Text('3 分钟速学').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text('等车、排队，刚刚好').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).backgroundColor($r('app.color.surface')).borderRadius(24).onClick(() => { this.beginStudy('quick'); })
      Button({ type: ButtonType.Normal }) {
        Column({ space: 9 }) {
          Text('✦').fontSize(26).fontColor($r('app.color.success'))
          Text('每日一词').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.snapshot.dailyWord.word).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1)
          if (this.useHomeColumns()) {
            Text(this.snapshot.dailyWord.meaning).fontSize(13).lineHeight(21)
              .fontColor($r('app.color.text_secondary')).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).backgroundColor($r('app.color.surface')).borderRadius(24)
        .onClick(() => { this.openWord(this.snapshot.dailyWord.id); })
    }.width('100%')
  }

  @Builder
  HomeChallengeCard() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 14 }) {
        Text('译').fontSize(26).fontWeight(FontWeight.Medium).fontColor($r('app.color.success'))
        Column({ space: 7 }) {
          Text('中文释义挑战').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text('从已学单词中出题，写出一个意思就过关').fontSize(12).lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('→').fontSize(22).fontColor($r('app.color.text_primary'))
      }.padding(22).width('100%')
    }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      .onClick(() => { this.pathStack.pushPathByName('MeaningChallenge', ''); })
  }

  @Builder
  HomeBudgetSection() {
    Column({ space: 12 }) {
      Text('今天有多忙？').fontSize(14).fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        this.Chip({ label: '很忙', selected: this.snapshot.plan.budget === 'busy', action: () => { this.changeBudget('busy'); } })
        this.Chip({ label: '正常', selected: this.snapshot.plan.budget === 'normal', action: () => { this.changeBudget('normal'); } })
        this.Chip({ label: '有空', selected: this.snapshot.plan.budget === 'free', action: () => { this.changeBudget('free'); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  HomeOverviewCard() {
    Column({ space: 18 }) {
      Text('积累的一点光').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row({ space: 12 }) {
        this.SmallStat({ value: `${this.snapshot.stats.totalLearned}`, label: '已学单词' })
        this.SmallStat({ value: `${this.snapshot.stats.mastered}`, label: '已掌握' })
        this.SmallStat({ value: `${this.snapshot.stats.streak}`, label: '连续学习天' })
      }.width('100%')
    }.width('100%').padding(this.compactMainPage() ? 20 : 24)
      .alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  Home() {
    Column({ space: this.compactMainPage() ? 14 : 18 }) {
      this.PageHeading({ id: 'tab-heading-0', title: '今天，也只学一点点。', subtitle: this.snapshot.stats.streak > 0 ?
        `连续学习 ${this.snapshot.stats.streak} 天 · 每一次回忆都在积累` : '欢迎回来。今天从几个词开始就好。' })
      if (this.useHomeColumns()) {
        Row({ space: 24 }) {
          Column({ space: 18 }) {
            this.HomeDueCard()
            this.HomePlanCard()
            this.HomeOverviewCard()
          }.layoutWeight(1.15).alignItems(HorizontalAlign.Start)
          Column({ space: 18 }) {
            this.HomeQuickCards()
            this.HomeChallengeCard()
            this.HomeBudgetSection()
            if (this.examDays() >= 0) {
              Text(`距离考试 ${this.examDays()} 天 · ${this.examDays() <= 14 ? '稳住复习，就在前进' : '按自己的节奏继续'}`)
                .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            }
            Text(`本周真正掌握 +${this.snapshot.stats.weekMastered} 词`).fontSize(13).fontColor($r('app.color.success'))
              .width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        this.HomeDueCard()
        this.HomePlanCard()
        this.HomeQuickCards()
        this.HomeChallengeCard()
        this.HomeBudgetSection()
        if (this.examDays() >= 0) {
          Text(`距离考试 ${this.examDays()} 天 · ${this.examDays() <= 14 ? '稳住复习，就在前进' : '按自己的节奏继续'}`)
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }
        Text(`本周真正掌握 +${this.snapshot.stats.weekMastered} 词`).fontSize(13).fontColor($r('app.color.success'))
          .width('100%').margin({ bottom: 6 })
      }
    }.width('100%')
  }

  @Builder
  BookCard($$: BookCardOptions) {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 5 }) {
          Text($$.book.name).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(`${$$.book.learnedCount} / ${$$.book.totalCount} 词已学习`).fontSize(13)
            .fontColor($$.book.id === this.snapshot.settings.currentBookId ? $r('app.color.glow_secondary') : $r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if ($$.book.id === this.snapshot.settings.currentBookId) {
          Text('学习中').fontSize(12).fontColor($r('app.color.success'))
        } else {
          Button('选用').fontSize(13).height(40).backgroundColor($r('app.color.soft_surface'))
            .fontColor($r('app.color.text_primary')).onClick(() => { this.setBook($$.book.id); })
        }
      }.width('100%')
      Progress({ value: $$.book.learnedCount, total: Math.max(1, $$.book.totalCount), type: ProgressType.Linear })
        .color($r('app.color.success')).backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 4 })
      Text($$.book.description).fontSize(12)
        .fontColor($$.book.id === this.snapshot.settings.currentBookId ? $r('app.color.glow_secondary') : $r('app.color.text_secondary'))
        .lineHeight(20).width('100%').maxLines(3)
      Button('浏览单词  →', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .fontSize(14).height(40).systemMaterial(uiMaterial.Material.empty).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_primary')).onClick(() => { this.openList($$.book.name, $$.book.id, 'all'); })
    }.width(this.cardGridWidth(12, 320, 3)).padding(22)
      .backgroundColor($$.book.id === this.snapshot.settings.currentBookId ?
        $r('app.color.glow') : $r('app.color.surface')).borderRadius(24)
  }

  @Builder
  Books() {
    Column({ space: 18 }) {
      this.PageHeading({ id: 'tab-heading-1', title: '每一本，都慢慢读。', subtitle: '词书可以切换，记忆不会重新归零。' })
      Flex({ direction: this.useHomeColumns() ? FlexDirection.Row : FlexDirection.Column,
        space: { main: LengthMetrics.vp(this.useHomeColumns() ? 12 : 18) } }) {
        Column() {
          this.Action({ label: '⌕  搜索单词或中文释义', action: () => { this.openList('搜索词典', '', 'all'); }, primary: false })
        }.width(this.useHomeColumns() ? this.cardGridWidth(12, 300, 2) : '100%')
        Column() {
          this.Action({ label: `已学单词 ${this.snapshot.stats.totalLearned} · 按日期查看  →`, action: () => {
            this.pathStack.pushPathByName('LearnedWords', '');
          }, primary: false })
        }.width(this.useHomeColumns() ? this.cardGridWidth(12, 300, 2) : '100%')
      }.width('100%')
      Text('正在学习').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(14) } }) {
        ForEach(this.snapshot.books, (book: WordBook) => {
          this.BookCard({ book: book })
        }, (book: WordBook) => JSON.stringify(book))
      }.width('100%')
      Row({ space: 12 }) {
        this.Chip({ label: `生词本 ${this.snapshot.newWordCount}`, selected: false, action: () => { this.openList('我的生词本', '', 'new'); } })
        this.Chip({ label: `收藏 ${this.snapshot.favoriteCount}`, selected: false, action: () => { this.openList('我的收藏', '', 'favorites'); } })
      }.width('100%')
      this.Action({ label: '+  导入自己的词书', action: () => { this.pathStack.pushPathByName('Import', ''); }, primary: false })
      Text('内置考试标签词库以来源说明为准，也可导入自己的词书。').fontSize(12)
        .fontColor($r('app.color.text_secondary')).lineHeight(20).width('100%')
    }.width('100%')
  }

  @Builder
  StatTodayCard() {
    Column({ space: 18 }) {
      Text('今天的一点光').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row() {
        this.SmallStat({ value: `${this.snapshot.plan.newDone}`, label: '新词' })
        this.SmallStat({ value: `${this.snapshot.plan.reviewDone}`, label: '复习次数' })
        this.SmallStat({ value: `${Math.round(this.snapshot.stats.successRate)}%`, label: '本周复习成功率' })
      }.width('100%')
    }.alignItems(HorizontalAlign.Start).padding(24)
      .width(this.cardGridWidth()).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  StatStrengthCard() {
    Column({ space: 18 }) {
      Row() {
        Text('记忆强度').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text('回忆越稳定，光越亮').fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      ForEach([0, 1, 2, 3], (index: number) => {
        Row({ space: 12 }) {
          Text(['陌生', '模糊', '熟悉', '掌握'][index]).fontSize(14).fontColor($r('app.color.text_secondary')).width(42)
          Progress({ value: this.snapshot.stats.strengthCounts[index] || 0,
            total: Math.max(1, this.snapshot.stats.totalLearned), type: ProgressType.Linear })
            .color([$r('app.color.strength_low'), $r('app.color.strength_mid'), $r('app.color.glow_deep'), $r('app.color.success')][index])
            .backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 10 }).layoutWeight(1)
          Text(`${this.snapshot.stats.strengthCounts[index] || 0}`).fontSize(14).fontColor($r('app.color.text_primary')).width(30)
        }.width('100%')
      }, (index: number) => `${index}`)
    }.padding(24).width(this.cardGridWidth()).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  StatWeekCard() {
    Column({ space: 18 }) {
      Text('最近 7 天 · 学习与复习').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row({ space: 8 }) {
        ForEach(this.snapshot.stats.days.slice(-7), (day: DaySummary) => {
          Column({ space: 9 }) {
            Text(`${day.totalCount}`).fontSize(13).fontColor($r('app.color.text_primary'))
            Column() {}.width('100%').height(Math.max(8, Math.min(92, day.totalCount * 3)))
              .backgroundColor(day.totalCount > 0 ? $r('app.color.success') : $r('app.color.soft_surface')).borderRadius(7)
            Text(day.date.slice(5)).fontSize(10).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).justifyContent(FlexAlign.End).height(128)
        }, (day: DaySummary) => JSON.stringify(day))
      }.width('100%')
      Text('完成 5 个复习词，也是一个轻学习日。').fontSize(12).fontColor($r('app.color.text_secondary'))
    }.alignItems(HorizontalAlign.Start).padding(24)
      .width(this.cardGridWidth()).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  StatCalendarCard() {
    Column({ space: 14 }) {
      Text('学习日历 · 最近 28 天').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Grid() {
        ForEach(this.snapshot.stats.days.slice(-28), (day: DaySummary) => {
          GridItem() {
            Text(day.date.slice(8)).fontSize(12).width('100%').height(36).textAlign(TextAlign.Center)
              .fontColor(day.newCount > 0 || day.reviewCount > 0 ? $r('app.color.inverse_text') : $r('app.color.text_secondary'))
              .backgroundColor(day.newCount > 0 || day.reviewCount > 0 ? $r('app.color.success') : $r('app.color.soft_surface')).borderRadius(8)
              .accessibilityText(`${day.date} 新词 ${day.newCount} 个，复习 ${day.reviewCount} 次`)
          }
        }, (day: DaySummary) => JSON.stringify(day))
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').columnsGap(6).rowsGap(6).height(164)
    }.alignItems(HorizontalAlign.Start).padding(24)
      .width(this.cardGridWidth()).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  StatisticsPage() {
    Column({ space: 20 }) {
      this.PageHeading({ id: 'tab-heading-2', title: '记住的，正在变多。', subtitle: '每一次认真回忆，都算数。' })
      Row({ space: 16 }) {
        this.SmallStat({ value: `${this.snapshot.stats.totalLearned}`, label: '已学习', highlighted: true })
        this.SmallStat({ value: `${this.snapshot.stats.mastered}`, label: '已掌握', highlighted: true })
        this.SmallStat({ value: `${this.snapshot.stats.streak}`, label: '连续学习天', highlighted: true })
      }.width('100%').padding(24).backgroundColor($r('app.color.glow')).borderRadius(24)
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(16), cross: LengthMetrics.vp(20) } }) {
        this.StatTodayCard()
        this.StatStrengthCard()
        this.StatWeekCard()
        this.StatCalendarCard()
      }.width('100%')
      Text(this.snapshot.stats.totalLearned === 0 ? '先点亮 3 个词，这里就会留下你的第一份记录。' :
        `这周，你真正掌握了 ${this.snapshot.stats.weekMastered} 个词。`)
        .fontSize(14).fontColor($r('app.color.success')).lineHeight(22).width('100%')
    }.width('100%')
  }

  @Builder
  ProfileTargetCard() {
    Column({ space: 16 }) {
      Text('每日新词目标').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row({ space: 7 }) {
        ForEach([10, 20, 30, 50], (target: number) => {
          this.Chip({ label: `${target} 词`, selected: this.snapshot.settings.dailyNewTarget === target, action: () => { this.saveTarget(target); } })
        }, (target: number) => `${target}`)
      }.width('100%')
      Text('复习优先。到期词多的时候，会自动减少新词。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
    }.width(this.cardGridWidth()).padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  ProfilePreferenceCard() {
    Column({ space: 16 }) {
      Text('学习偏好').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row() {
        Text('自动读出单词').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.snapshot.settings.autoPronounce })
          .selectedColor($r('app.color.success')).onChange((value: boolean) => { this.changeAutoPronounce(value); })
      }.width('100%')
      Row({ space: 8 }) {
        this.Chip({ label: '日常学习', selected: this.snapshot.settings.learningMode === 'normal', action: () => { this.changeMode('normal'); } })
        this.Chip({ label: '考试冲刺', selected: this.snapshot.settings.learningMode === 'exam', action: () => { this.changeMode('exam'); } })
      }.width('100%')
    }.width(this.cardGridWidth()).padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  ProfileAppearanceCard() {
    Column({ space: 16 }) {
      Text('外观').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Row({ space: 8 }) {
        this.Chip({ label: '跟随系统', selected: this.snapshot.settings.themeMode === 'system', action: () => { this.changeTheme('system'); } })
        this.Chip({ label: '浅色', selected: this.snapshot.settings.themeMode === 'light', action: () => { this.changeTheme('light'); } })
        this.Chip({ label: '深色', selected: this.snapshot.settings.themeMode === 'dark', action: () => { this.changeTheme('dark'); } })
      }.width('100%')
    }.width(this.cardGridWidth()).padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  ProfileExamCard() {
    Column({ space: 12 }) {
      Text('考试日期（可选）').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      TextInput({ text: this.examDate, placeholder: 'YYYY-MM-DD，例如 2026-12-12' })
        .fontSize(14).height(48).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
        .onChange((value: string) => { this.examDate = value; })
      this.Action({ label: '保存日期', action: () => { this.saveExamDate(); }, primary: false })
    }.width(this.cardGridWidth()).padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  Profile() {
    Column({ space: 20 }) {
      this.PageHeading({ id: 'tab-heading-3', title: '按自己的节奏来。', subtitle: '这里的设置，都是为了学得更舒服。' })
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(16), cross: LengthMetrics.vp(20) } }) {
        this.ProfileTargetCard()
        this.ProfilePreferenceCard()
        this.ProfileAppearanceCard()
        this.ProfileExamCard()
      }.width('100%')
      this.Action({ label: '学习提醒  ·  ' + (this.snapshot.settings.reminderEnabled ? '已开启' : '未开启'), action: () => { this.pathStack.pushPathByName('Reminders', ''); }, primary: false })
      this.Action({ label: '导出学习数据', action: () => { this.exportData(); }, primary: false })
      this.Action({ label: '数据与隐私', action: () => { this.pathStack.pushPathByName('Privacy', ''); }, primary: false })
      Text('词萤 LexiGlow  1.0.0\n让单词一点一点亮起来').fontSize(12).lineHeight(21)
        .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center).width('100%').margin({ top: 8 })
    }.width('100%')
  }

  @Builder
  LearnPage() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([$r('app.color.text_primary')])
        }.width(48).height(48).padding(0).systemMaterial(this.titleButtonMaterial)
          .accessibilityText('保存进度并返回').onClick(() => { this.leaveStudy(); })
        Text(`${Math.min(this.session.index + 1, this.session.items.length)} / ${this.session.items.length}`)
          .fontSize(15).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.currentProgress.favorite ? '★' : '☆').width(48).height(48).fontSize(25)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
          .accessibilityText(this.currentProgress.favorite ? '取消收藏' : '收藏单词').onClick(() => { this.toggleFavorite(); })
      }.padding({ left: 14, right: 14 }).width('100%')
      Progress({ value: this.session.index, total: Math.max(1, this.session.items.length), type: ProgressType.Linear })
        .color($r('app.color.success')).backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 3 })
        .padding({ left: 26, right: 26 })
      Scroll() {
        Row() {
          Column({ space: 24 }) {
            Text(this.session.items[this.session.index]?.type === 'review' ? '再次见面' : '认识一个新词')
              .fontSize(13).letterSpacing(2).fontColor($r('app.color.text_secondary'))
            Text(this.currentWord.word).fontSize(this.isWide() ? 52 : 40).fontWeight(FontWeight.Medium).fontFamily('serif')
              .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center).maxLines(2)
              .gesture(LongPressGesture().onAction(() => { this.copyWord(); }))
            Row({ space: 12 }) {
              Text(this.currentWord.phonetic).fontSize(16).fontColor($r('app.color.text_secondary'))
              Button('♪').width(48).height(48).fontSize(24).backgroundColor($r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).accessibilityText('播放英文发音').onClick(() => { this.pronounce(this.currentWord.word); })
            }
            if (this.answerVisible) {
              Column({ space: 20 }) {
                Text(this.currentWord.meaning).fontSize(22).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary')).lineHeight(32).width('100%')
                if (this.currentWord.example) {
                Divider().color($r('app.color.divider'))
                Text(this.currentWord.example).fontSize(18).fontColor($r('app.color.text_primary')).lineHeight(29).width('100%')
                Text(this.currentWord.translation).fontSize(15).fontColor($r('app.color.text_secondary')).lineHeight(25).width('100%')
                }
              }.padding(26).width('100%').backgroundColor($r('app.color.surface')).borderRadius(26)
                .opacity(this.answerOpacity).translate({ y: (1 - this.answerOpacity) * 8 })
            } else {
              Text('先想一想，它的意思是什么？').fontSize(16).fontColor($r('app.color.text_secondary')).margin({ top: 36 })
            }
          }.width('100%').padding({ left: 26, right: 26, top: this.viewportHeight < 480 ? 12 : 46, bottom: 24 })
            .constraintSize({ maxWidth: 640 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Column({ space: 14 }) {
        if (this.answerVisible) {
          Row({ space: 9 }) {
            this.Judgment('不认识', '早点再见一次', ReviewResult.FORGET)
            this.Judgment('模糊', '再巩固一下', ReviewResult.FUZZY)
            this.Judgment('认识', '能回忆核心意思', ReviewResult.KNOW)
          }.width('100%')
        } else { this.Action({ label: '显示释义', action: () => { this.showAnswer(); }, primary: true }); }
        if (this.viewportHeight >= 480) {
          Text(this.isWide() ? '键盘：空格显示释义 · 1 不认识 · 2 模糊 · 3 认识' :
            '忘记也没关系，我们会安排下次见面。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.padding({ left: 24, right: 24, bottom: Math.max(16, this.windowState.bottomInset), top: this.viewportHeight < 480 ? 6 : 12 }).width('100%').constraintSize({ maxWidth: 640 })
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
      .focusable(true).defaultFocus(true).onKeyEvent((event: KeyEvent): boolean => { return this.handleStudyKey(event); })
  }

  @Builder
  Judgment(title: string, subtitle: string, result: ReviewResult) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(subtitle).fontSize(10).fontColor($r('app.color.text_secondary'))
      }.padding({ top: 18, bottom: 18 }).width('100%')
    }.layoutWeight(1).borderRadius(18).backgroundColor(result === ReviewResult.KNOW ?
      $r('app.color.glow') : $r('app.color.surface')).enabled(!this.busy).onClick(() => { this.judge(result); })
  }

  @Builder
  SummaryPage() {
    Scroll() {
      Row() {
        Column({ space: 24 }) {
          Text('✦').fontSize(60).fontColor($r('app.color.success')).margin({ top: 40 })
          Text('今天的光，已经亮起来。').fontSize(27).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center)
          Text(`学习新词 ${this.completedCount('new')} 个 · 复习 ${this.completedCount('review')} 次\n每次判断，都在安排下一次更好的相遇。`)
            .fontSize(15).lineHeight(25).textAlign(TextAlign.Center).fontColor($r('app.color.text_secondary'))
          Column({ space: 14 }) {
            Text('再看一眼，今天遇见的词').fontSize(15).fontColor($r('app.color.text_secondary')).width('100%')
            ForEach(this.session.items.slice(Math.max(0, this.session.index - 3), this.session.index), (item: StudyItem) => {
              Row({ space: 12 }) {
                Text(item.word.word).fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
                Text(item.word.meaning).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2).width('50%')
              }.width('100%')
            }, (item: StudyItem) => `${item.word.id}`)
          }.padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
          this.Action({ label: '回到首页', action: () => { this.leaveSummary(); }, primary: true })
          this.Action({ label: '再来 3 分钟', action: () => {
            this.service.clearSession().then(() => { this.pathStack.clear(); this.beginStudy('quick'); })
              .catch(() => { this.toast('学习暂时没能开始，请重试。'); });
          }, primary: false })
        }.padding(26).width('100%').constraintSize({ maxWidth: 620 })
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor($r('app.color.background'))
  }

  @Builder
  WordRowCard($$: WordRowOptions) {
    Row({ space: 12 }) {
      Column({ space: 7 }) {
        if (this.usesLargeWordList()) {
          Text($$.word.word).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($$.word.meaning).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
            .width('100%').height(44).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text($$.word.word).fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text($$.word.meaning).fontSize(14).fontColor($r('app.color.text_secondary')).maxLines(2)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(26).fontColor($r('app.color.text_secondary'))
    }.padding(21).width('100%').height(this.usesLargeWordList() ? 120 : undefined)
      .backgroundColor($r('app.color.surface')).borderRadius(21)
      .focusable(true).hoverEffect(HoverEffect.Highlight)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type === KeyType.Down && (event.keyCode === KeyCode.KEYCODE_ENTER ||
          event.keyCode === KeyCode.KEYCODE_SPACE)) {
          this.openWord($$.word.id, this.listBookId); return true;
        }
        return false;
      })
      .onClick(() => { this.openWord($$.word.id, this.listBookId); })
  }

  @Builder
  WordListPage() {
    Row() {
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 10 }) {
          TextInput({ text: this.searchText, placeholder: '输入英文单词或中文释义' }).height(52).fontSize(16)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).borderRadius(18)
            .onChange((value: string) => { this.scheduleSearch(value); })
          if (this.listBookId.startsWith('custom')) {
            Row({ space: 8 }) {
              TextInput({ text: this.renameText, placeholder: '自定义词书名称' }).height(44).layoutWeight(1)
                .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
                .onChange((value: string) => { this.renameText = value; })
              Button('改名').height(44).backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
                .enabled(!this.busy).onClick(() => { this.renameBook(); })
            }.width('100%')
          }
          if (this.listBookId) {
            Row({ space: 8 }) {
              this.Chip({ label: '导出 JSON', selected: false, action: () => { this.exportBook('json'); } })
              this.Chip({ label: '导出 CSV', selected: false, action: () => { this.exportBook('csv'); } })
              this.Chip({ label: '导出 TXT', selected: false, action: () => { this.exportBook('txt'); } })
            }.width('100%')
          }
          if (this.loadingWords) {
            Text('正在查找…').fontSize(14).fontColor($r('app.color.text_secondary')).padding(20)
          }
        }.width('100%')
      }
      if (this.wordListColumns() > 1) {
        ForEach(this.wordRows(), (words: Word[]) => {
          ListItem() {
            Row({ space: 12 }) {
              ForEach(words, (word: Word) => {
                Column() { this.WordRowCard({ word: word }); }.layoutWeight(1)
              }, (word: Word) => `${word.id}`)
              ForEach([0, 1, 2].slice(words.length, this.wordListColumns()), (_slot: number) => {
                Column().layoutWeight(1)
              }, (slot: number) => `${slot}`)
            }.width('100%').alignItems(this.usesLargeWordList() ? VerticalAlign.Top : VerticalAlign.Center)
          }
        }, (words: Word[]) => words.map((word: Word) => word.id).join('-'))
      } else {
        ForEach(this.words, (word: Word) => {
          ListItem() {
            this.WordRowCard({ word: word })
          }
        }, (word: Word) => JSON.stringify(word))
      }
      if (!this.loadingWords && this.words.length === 0) {
        ListItem() {
          Column({ space: 14 }) {
            Text('还没有遇见这个词。').fontSize(20).fontColor($r('app.color.text_primary'))
            Text('可以导入自定义词书，把它加入下一段学习。').fontSize(14).lineHeight(24)
              .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
            this.Action({ label: '添加自定义词书', action: () => { this.pathStack.pushPathByName('Import', ''); }, primary: false })
          }.padding({ top: 60, bottom: 30 }).width('100%')
        }
      }
      if (this.words.length >= 80) {
        ListItem() { Text('显示前 80 个结果，输入更多字符缩小范围。').fontSize(12).fontColor($r('app.color.text_secondary')).padding(12) }
      }
    }.padding({ left: 24, right: 24 }).width('100%')
      .constraintSize({ maxWidth: this.usesLargeWordList() ? PAGE_MAX_WIDTH : 1040 }).height('100%').scrollBar(BarState.Auto)
      .onAreaChange((_old: Area, area: Area) => { this.wordListWidth = Number(area.width); })
      .contentStartOffset(66).contentEndOffset(bottomContentOffset(this.getUIContext()))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.background'))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  WordMeaningCard() {
    Column({ space: 18 }) {
      Text(this.currentWord.meaning).fontSize(22).fontColor($r('app.color.text_primary')).lineHeight(32).width('100%')
      if (this.currentWord.example) {
      Divider().color($r('app.color.divider'))
      Text(this.currentWord.example).fontSize(18).fontColor($r('app.color.text_primary')).lineHeight(28).width('100%')
      Text(this.currentWord.translation).fontSize(15).fontColor($r('app.color.text_secondary')).lineHeight(25).width('100%')
      }
    }.padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  WordStrengthCard() {
    Column({ space: 14 }) {
      Row() {
        Text('记忆强度').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.strengthName(this.currentProgress.strength)} · ${this.currentProgress.strength}`)
          .fontSize(14).fontColor($r('app.color.success'))
      }.width('100%')
      Progress({ value: this.currentProgress.strength, total: 100, type: ProgressType.Linear })
        .color($r('app.color.success')).backgroundColor($r('app.color.soft_surface')).style({ strokeWidth: 7 })
      Text(this.currentProgress.reviewCount > 0 ? `下次见面：${new Date(this.currentProgress.nextReviewAt).toLocaleString()}` :
        '还没有学习记录，下一次学习会开始安排复习。').fontSize(12).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  WordHistoryCard() {
    Column({ space: 14 }) {
      Text('最近 5 次回忆').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      ForEach(this.history, (record: ReviewRecord) => {
        Row() {
          Text(new Date(record.reviewAt).toLocaleDateString()).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Text(this.resultName(record.result)).fontSize(14).fontColor($r('app.color.text_primary'))
        }.width('100%')
      }, (record: ReviewRecord) => `${record.id}`)
      Text(this.history.length === 0 ? '还没有记录，从第一次回忆开始。' :
        this.history.filter((record: ReviewRecord) => record.result === 0).length >= 2 ?
          '最近几次不太稳定。试着把它放进例句里，下次再见一次。' : '回忆正在累积。先想意思，再看释义，会记得更牢。')
        .fontSize(13).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  WordDetailPage() {
    Column() {
      Scroll() {
        Column({ space: 22 }) {
          Row() {
            Text(this.currentWord.word).fontSize(this.isWide() ? 46 : 35).fontFamily('serif').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(2)
              .gesture(LongPressGesture().onAction(() => { this.copyWord(); }))
            Button('♪').height(48).width(48).fontSize(23).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.text_primary')).accessibilityText('播放发音').onClick(() => { this.pronounce(this.currentWord.word); })
          }.width('100%')
          Text(this.currentWord.phonetic).fontSize(16).fontColor($r('app.color.text_secondary')).width('100%')
          if (this.detailBookId.startsWith('custom')) {
            this.Action({ label: '编辑这个单词', action: () => { this.editWord(this.currentWord); }, primary: false })
          }
          if (this.isWide()) {
            Row({ space: 24 }) {
              Column({ space: 22 }) {
                this.WordMeaningCard()
                Row({ space: 10 }) {
                  this.Chip({ label: this.currentProgress.favorite ? '★ 已收藏' : '☆ 收藏', selected: this.currentProgress.favorite, action: () => { this.toggleFavorite(); } })
                  this.Chip({ label: this.currentProgress.isNewWord ? '已加入生词本' : '+ 生词本', selected: this.currentProgress.isNewWord, action: () => { this.toggleNewWord(); } })
                }.width('100%')
              }.layoutWeight(1.15).alignItems(HorizontalAlign.Start)
              Column({ space: 22 }) {
                this.WordStrengthCard()
                this.WordHistoryCard()
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(VerticalAlign.Top)
          } else {
            this.WordMeaningCard()
            Row({ space: 10 }) {
              this.Chip({ label: this.currentProgress.favorite ? '★ 已收藏' : '☆ 收藏', selected: this.currentProgress.favorite, action: () => { this.toggleFavorite(); } })
              this.Chip({ label: this.currentProgress.isNewWord ? '已加入生词本' : '+ 生词本', selected: this.currentProgress.isNewWord, action: () => { this.toggleNewWord(); } })
            }.width('100%')
            this.WordStrengthCard()
            this.WordHistoryCard()
          }
        }.padding(24).width('100%').constraintSize({ maxWidth: this.isWide() ? 1040 : 680 })
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center).scrollBar(BarState.Off)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  RemindersPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 22 }) {
            this.PageHeading({ title: '在你喜欢的时间，轻轻提醒。', subtitle: '提醒默认关闭。只有你主动开启时，才申请通知权限。' })
          Row({ space: 14 }) {
            TextInput({ text: this.reminderHour, placeholder: '21' }).type(InputType.Number).layoutWeight(1)
              .fontSize(28).height(70).textAlign(TextAlign.Center).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.text_primary')).onChange((value: string) => { this.reminderHour = value; })
            Text(':').fontSize(28).fontColor($r('app.color.text_primary'))
            TextInput({ text: this.reminderMinute, placeholder: '00' }).type(InputType.Number).layoutWeight(1)
              .fontSize(28).height(70).textAlign(TextAlign.Center).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.text_primary')).onChange((value: string) => { this.reminderMinute = value; })
          }.width('100%')
          this.Action({ label: '开启 / 更新每日提醒', action: () => { this.saveReminder(true); }, primary: true })
          this.Action({ label: '关闭学习提醒', action: () => { this.saveReminder(false); }, primary: false })
          Text('每天最多一次定时提醒，不追着你催。\n系统提醒能力需要设备及应用权限支持。')
            .fontSize(14).lineHeight(25).fontColor($r('app.color.text_secondary')).width('100%')
          }.padding(26).width('100%').constraintSize({ maxWidth: 620 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center)
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  ImportPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 18 }) {
            this.PageHeading({ title: '把遇见的单词，留在这里。', subtitle: '读取 DOCX、TXT、JSON 或 CSV，确认内容后再导入。' })
          this.Action({ label: '选择词库文件', action: () => { this.importFile(); }, primary: true })
          Text('也可以直接粘贴').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
          TextInput({ text: this.importName, placeholder: '词书名称' }).height(48).backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary')).onChange((value: string) => { this.importName = value; })
          TextArea({ text: this.importText, placeholder: 'word,phonetic,meaning,example,translation\nshine,/ʃaɪn/,v. 发光,Stars shine.,星星发光。' })
            .fontSize(14).height(230).backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
            .onChange((value: string) => { this.importText = value; })
          this.Action({ label: '导入粘贴内容', action: () => { this.importPasted(); }, primary: false })
          Text('DOCX / TXT 支持一行一词、单词加中文释义，或五列表格。只有单词时，会匹配本地词典；没找到的可以在预览中补充。\nJSON / CSV 支持 word、meaning，以及 phonetic、example、translation。请导入有使用权的内容。')
            .fontSize(13).fontColor($r('app.color.text_secondary')).lineHeight(23).width('100%')
          }.padding(24).width('100%').constraintSize({ maxWidth: 680 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  ImportPreviewPage() {
    Row() {
      Column({ space: 14 }) {
        TextInput({ text: this.importName, placeholder: '词书名称' }).height(48)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary'))
          .margin({ left: 24, right: 24 }).onChange((value: string) => { this.importName = value; })
        Text(`识别 ${this.pendingWords.length} 个词 · ${this.unresolvedCount()} 个需要补充释义`)
          .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 24, right: 24 })
        List({ space: 9 }) {
          ForEach(this.previewWords(), (word: Word) => {
            ListItem() {
              Row() {
                Column({ space: 6 }) {
                  Text(word.word).fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text(word.meaning || '点开补充中文释义').fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('编辑 ›').fontSize(13).fontColor($r('app.color.text_secondary'))
              }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(18)
                .onClick(() => { this.editWord(word, this.pendingWords.indexOf(word)); })
            }
          }, (word: Word) => JSON.stringify(word))
          ListItem() {
            Text('点开词条可修改内容；有待补释义时优先显示这些词，最多显示 100 条。').fontSize(12)
              .fontColor($r('app.color.text_secondary')).lineHeight(22).padding(12)
          }
        }.layoutWeight(1).width('100%').padding({ left: 24, right: 24 }).scrollBar(BarState.Off)
        Column() { this.Action({ label: `导入 ${this.pendingWords.length} 个词`, action: () => { this.confirmImport(); }, primary: true }); }
          .width('100%').padding({ left: 24, right: 24, top: 8, bottom: 20 })
      }.padding({ top: 56 }).height('100%').width('100%').constraintSize({ maxWidth: 760 })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.background'))
  }

  @Builder
  EditWordPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 16 }) {
          Text('单词').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          TextInput({ text: this.editHeadword, placeholder: '英文单词' }).height(52)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.editHeadword = value; })
          Text('中文释义').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          TextArea({ text: this.editMeaning, placeholder: '词性和含义' }).height(110)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.editMeaning = value; })
          Text('音标（可选）').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          TextInput({ text: this.editPhonetic, placeholder: '/.../' }).height(52)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.editPhonetic = value; })
          Text('例句与译文（可选）').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          TextArea({ text: this.editExample, placeholder: '英文例句' }).height(95)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.editExample = value; })
          TextArea({ text: this.editTranslation, placeholder: '例句译文' }).height(95)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.editTranslation = value; })
          this.Action({ label: '保存内容', action: () => { this.saveEditedWord(); }, primary: true })
          }.padding(24).width('100%').constraintSize({ maxWidth: 680 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  PrivacyPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 24 }) {
          this.PageHeading({ title: '你的记忆，留在你的设备。', subtitle: '本版本无需账号，核心学习不依赖网络。' })
          Text('单词、学习进度和回忆记录保存在应用本机数据库；目标、外观等偏好保存在本机首选项。应用不包含广告、行为追踪或云端 AI 请求。')
            .fontSize(16).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
          Text('文件选择仅在你主动导入或导出时打开。提醒权限仅在主动开启提醒时申请。发音调用设备语音能力，语音资源可用性由设备决定。')
            .fontSize(16).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
          Text('卸载应用可能删除本机记录。更换设备前，可以主动导出 JSON 文件，妥善保存。当前导出用于备份与查看，进度恢复和账号同步将在后续版本提供。')
            .fontSize(14).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
          this.Action({ label: '导出我的学习数据', action: () => { this.exportData(); }, primary: false })
          }.padding(26).width('100%').constraintSize({ maxWidth: 680 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  RouteBuilder(name: string) {
    NavDestination() {
      if (name === 'Learn') { this.LearnPage(); }
      else if (name === 'Summary') { this.SummaryPage(); }
      else if (name === 'WordList') { this.WordListPage(); }
      else if (name === 'WordDetail') { this.WordDetailPage(); }
      else if (name === 'Reminders') { this.RemindersPage(); }
      else if (name === 'Import') { this.ImportPage(); }
      else if (name === 'ImportPreview') { this.ImportPreviewPage(); }
      else if (name === 'EditWord') { this.EditWordPage(); }
      else if (name === 'MeaningChallenge') {
        MeaningChallengePage({
          onLearn: () => { this.pathStack.pop(); this.beginStudy('today'); },
          onLearnedWords: () => { this.returnToLearnedWords(); }
        })
      }
      else if (name === 'LearnedWords') {
        LearnedWordsPage({
          onOpenWord: (id: number, bookId: string) => { this.openWord(id, bookId); },
          onChallenge: () => { this.pathStack.pushPathByName('MeaningChallenge', ''); }
        })
      }
      else { this.PrivacyPage(); }
    }.hideTitleBar(name === 'Learn' || name === 'Summary').hideBackButton(true)
      .title({ builder: () => { this.RouteTitleBar(name); }, height: 56 }, {
        barStyle: BarStyle.STACK,
        scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
      })
      .backgroundColor($r('app.color.background'))
      .expandSafeArea([SafeAreaType.SYSTEM], name === 'WordList' || name === 'LearnedWords' ?
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : [SafeAreaEdge.TOP])
      .onBackPressed(() => {
        if (name === 'Learn') { this.leaveStudy(); return true; }
        if (name === 'Summary') { this.leaveSummary(); return true; }
        if (name === 'WordDetail') { this.leaveRoute(name); return true; }
        return false;
      })
  }

  private updateTitleCollapse(index: number): void {
    let collapsed = this.tabScrollers[index].currentOffset().yOffset > 100;
    try {
      const utils = this.getUIContext().getComponentUtils();
      const heading = utils.getRectangleById(`tab-heading-${index}`);
      const title = utils.getRectangleById(`tab-title-${index}`);
      if (heading.size.height > 0 && title.size.height > 0) {
        // Both rectangles use window pixel coordinates; no vp/px mixing.
        collapsed = heading.windowOffset.y + heading.size.height <= title.windowOffset.y + title.size.height;
      }
    } catch {}
    if (this.titleCollapsed[index] !== collapsed) {
      const states = this.titleCollapsed.slice(); states[index] = collapsed; this.titleCollapsed = states;
    }
  }

  primaryTitleIndex(index: number): number {
    return this.useTopNavigation() ? this.tab : index;
  }

  @Builder
  SharedPrimaryTitleBar() {
    if (this.useTopNavigation()) { this.PrimaryTitleBar(0); }
  }

  @Builder
  PrimaryTitleBar(index: number) {
    Row({ space: 12 }) {
      if (this.useTopNavigation()) {
        PrimaryNavigation({ selectedIndex: this.tab,
          onSelect: (selected: number) => { this.primaryTabsController.changeIndex(selected); } })
          .layoutWeight(1)
      } else {
        Text(this.titleCollapsed[index] ? ['今日学习', '词库', '学习统计', '我的设置'][index] : 'LexiGlow')
          .fontSize(this.titleCollapsed[index] ? 18 : 24).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(1)
      }
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        if (this.primaryTitleIndex(index) === 0) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([$r('app.color.brand_ink')])
        } else {
          Text(this.primaryTitleIndex(index) === 1 ? '+' : this.primaryTitleIndex(index) === 2 ? '↗' : '◐')
            .fontSize(24).fontColor($r('app.color.brand_ink'))
        }
      }.width(40).height(40).padding(0).systemMaterial(this.titleButtonMaterial)
        .accessibilityText(this.primaryTitleIndex(index) === 1 ? '导入自定义词书' :
          this.primaryTitleIndex(index) === 2 ? '导出学习数据' :
            this.primaryTitleIndex(index) === 3 ? '切换深浅色' : '搜索单词')
        .onClick(() => {
          if (this.primaryTitleIndex(index) === 1) { this.pathStack.pushPathByName('Import', ''); }
          else if (this.primaryTitleIndex(index) === 2) { this.exportData(); }
          else if (this.primaryTitleIndex(index) === 3) {
            this.changeTheme(this.context().config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'light' : 'dark');
          }
          else { this.openList('搜索词典', '', 'all'); }
        })
    }.width('100%').height('100%').padding({ left: this.mainTitlePadding(), right: this.mainTitlePadding() })
      .expandSafeArea([SafeAreaType.SYSTEM])
      .id(`tab-title-${this.primaryTitleIndex(index)}`)
  }

  routeTitle(name: string): string {
    if (name === 'WordList') { return this.listTitle; }
    if (name === 'WordDetail') { return '单词详情'; }
    if (name === 'Reminders') { return '学习提醒'; }
    if (name === 'Import') { return '导入自定义词书'; }
    if (name === 'ImportPreview') { return '确认导入内容'; }
    if (name === 'EditWord') { return this.editIndex >= 0 ? '补充 / 修改导入单词' : '编辑自定义词条'; }
    if (name === 'MeaningChallenge') { return '中文释义挑战'; }
    if (name === 'LearnedWords') { return '已学单词'; }
    return '数据与隐私';
  }

  @Builder
  RouteTitleBar(name: string) {
    this.BackHeader({ title: this.routeTitle(name), action: () => { this.leaveRoute(name); } })
  }

  private leaveRoute(name: string): void {
    this.pathStack.pop();
    if (name === 'WordDetail') { this.search(); }
  }

  private returnToLearnedWords(): void {
    if (this.pathStack.getAllPathName().indexOf('LearnedWords') >= 0) {
      this.pathStack.popToName('LearnedWords');
    } else {
      this.pathStack.replacePathByName('LearnedWords', '');
    }
  }

  @Builder
  PrimaryTabScroll(index: number) {
    Scroll(this.tabScrollers[index]) {
      Column() {
        if (index === 0) { this.Home(); }
        else if (index === 1) { this.Books(); }
        else if (index === 2) { this.StatisticsPage(); }
        else { this.Profile(); }
      }
        .padding({ left: this.mainPagePadding(), right: this.mainPagePadding(),
          top: this.compactMainPage() ? 16 : 24, bottom: this.isWide() ? 32 : 116 }).width('100%')
        .constraintSize({ maxWidth: PAGE_MAX_WIDTH })
    }.width('100%').height('100%').contentStartOffset(56)
      .align(this.isMedium() ? Alignment.Top : Alignment.Center)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)
      .onDidScroll((_x: number, _y: number, _state: ScrollState) => { this.updateTitleCollapse(index); })
  }

  @Builder
  PrimaryTabContent(index: number) {
    if (this.useTopNavigation()) {
      // The shared native title stays outside Tabs while this Scroll drives its immersive effect.
      this.PrimaryTabScroll(index)
    } else {
      Navigation() {
        this.PrimaryTabScroll(index)
      }.mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
        .title({ builder: () => { this.PrimaryTitleBar(index); }, height: 56 }, {
          barStyle: BarStyle.STACK,
          scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
        })
        .width('100%').height('100%').backgroundColor($r('app.color.background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }


  build() {
    Stack() {
      if (this.error) {
        Column({ space: 22 }) {
          Text('词萤').fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.error).fontSize(16).lineHeight(26).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          this.Action({ label: '重试', action: () => { this.initialize(); }, primary: true })
        }.padding(36).width('100%').constraintSize({ maxWidth: 520 })
      } else if (!this.ready) {
        Column({ space: 18 }) {
          Image($r('app.media.ciying_icon')).width(88).height(88)
          Text('让单词一点一点亮起来').fontSize(18).fontColor($r('app.color.text_primary'))
          LoadingProgress().width(28).height(28).color($r('app.color.success'))
        }
      } else {
        Navigation(this.pathStack) {
          if (!this.snapshot.settings.onboarded) { this.Welcome(); }
          else {
            ImmersiveDock({
              selectedIndex: this.tab,
              availableWidth: this.viewportWidth,
              tabsController: this.primaryTabsController,
              onSelect: (index: number) => { this.selectTab(index); },
              homeContent: () => { this.PrimaryTabContent(0); },
              booksContent: () => { this.PrimaryTabContent(1); },
              statisticsContent: () => { this.PrimaryTabContent(2); },
              profileContent: () => { this.PrimaryTabContent(3); }
            }).width('100%').height('100%')
          }
        }.mode(NavigationMode.Stack).hideTitleBar(!this.useTopNavigation() || !this.snapshot.settings.onboarded)
          .hideBackButton(true).hideToolBar(true).navDestination(this.RouteBuilder)
          .title({ builder: () => { this.SharedPrimaryTitleBar(); }, height: 56 }, {
            barStyle: BarStyle.STACK,
            scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
          })
          .width('100%').height('100%').backgroundColor($r('app.color.background'))
          .attributeModifier(this.useTopNavigation() ? this.immersivePrimaryNavigation : this.defaultPrimaryNavigation)
          .onAppear(() => { this.dispatchInitialRoute(); })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
      .onAreaChange((_old: Area, area: Area) => {
        this.viewportWidth = Number(area.width);
        this.viewportHeight = Number(area.height);
      })
  }
}
