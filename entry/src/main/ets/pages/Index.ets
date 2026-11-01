import { ExperienceService } from '../service/ExperienceService';
import { PracticeRecommendation } from '../model/ExperienceModels';
import { ReadingRecommendation } from '../model/ArticleModels';
import { ArticleService } from '../service/ArticleService';
import { recommendPractice } from '../utils/ExperienceUtils';
import { WordExperiencePanel } from '../components/WordExperiencePanel';
import { SentenceCollectionPage } from './SentenceCollectionPage';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { CommonModifier, LengthMetrics, curves, uiMaterial } from '@kit.ArkUI';
import { AppSnapshot, Word, WordProgress, WordBook, ReviewRecord, ReviewResult, StudySession, StudyItem, UserSettings, DaySummary, WordEnrichment, DataExport, DictionaryBook } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { AudioService } from '../service/AudioService';
import { PronunciationPresenter } from '../service/PronunciationPresenter';
import { AudioFlowService } from '../service/AudioFlowService';
import { HapticService } from '../service/HapticService';
import { LiveStudyService, StudyLiveState } from '../service/LiveStudyService';
import { FormService } from '../service/FormService';
import { ReminderService } from '../service/ReminderService';
import { TransferService } from '../service/TransferService';
import { AlphabetWordList } from '../components/AlphabetWordList';
import { ImmersiveDock } from '../components/ImmersiveDock';
import { PrimaryNavigation } from '../components/PrimaryNavigation';
import { dailyPlanProgress, isDailyPlanComplete } from '../utils/DailyPlanUtils';
import { strengthName } from '../utils/MemoryUtils';
import { dateKey } from '../utils/TimeUtils';
import { MeaningChallengePage } from './MeaningChallengePage';
import { LearnedWordsPage } from './LearnedWordsPage';
import { AudioFlowPage } from './AudioFlowPage';
import { QuietReviewPage } from './QuietReviewPage';
import { MistakeBookPage } from './MistakeBookPage';
import { ArticleLibraryPage } from './ArticleLibraryPage';
import { ArticlePage } from './ArticlePage';
import { ClozeChallengePage } from './ClozeChallengePage';
import { ReadAlongPanel } from '../components/ReadAlongPanel';
import { DailyStudyCard } from '../components/DailyStudyCard';
import { SpellingChallengePage } from './SpellingChallengePage';
import { ConstellationPage } from './ConstellationPage';
import { SharedWordsPage } from './SharedWordsPage';
import { WordKnowledgeCard } from '../components/WordKnowledgeCard';
import { PronunciationSettings } from '../components/PronunciationSettings';
import { HomeConstellationCard as ConstellationHomeCard } from '../components/HomeConstellationCard';
import { spellingHint, spellingMatches } from '../utils/SpellingUtils';
import { bottomContentOffset } from '../utils/SafeAreaUtils';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';
import { PAGE_MAX_WIDTH, primaryPageMaxWidth, dashboardUsesColumns, pageHorizontalPadding, primaryNavigationRailWidth, responsiveColumnCount, responsiveCardWidth, usesTopNavigation, wordListColumnCount } from '../utils/ResponsiveLayout';

interface ActionOptions { label: string; action: () => void; primary: boolean; }
interface HeadingOptions { title: string; subtitle: string; id?: string; }
interface HeaderOptions { title: string; action: () => void; }
interface StatOptions { value: string; label: string; highlighted?: boolean; }
interface ChipOptions { label: string; selected: boolean; action: () => void; }
interface BookCardOptions { book: WordBook; }

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
  @Local reduceMotion: boolean = true;
  @Local selectedBook: string = 'cet4';
  @Local selectedTarget: number = 10;
  @Local foundation: string = 'beginner';
  @Local session: StudySession = new StudySession();
  @Local answerVisible: boolean = false;
  @Local undoAvailable: boolean = false;
  @Local lastJudgedWord: string = '';
  @Local detailVisible: boolean = false;
  @Local mistakesVisible: boolean = false;
  @Local recommendation: PracticeRecommendation = new PracticeRecommendation();
  @Local readingPick: ReadingRecommendation = new ReadingRecommendation();
  @Local preferredIds: number[] = [];
  @Local articleSourceKey: string = '';
  @Local experienceError: string = '';
  private experienceVersion: number = 0;
  @Local articleId: number = 0;
  @Local restoreSkipped: number = 0;
  @Local answerOpacity: number = 0;
  @Local currentWord: Word = new Word();
  @Local currentProgress: WordProgress = new WordProgress();
  @Local enrichment: WordEnrichment = new WordEnrichment();
  @Local activityWords: Word[] = [];
  @Local sharedText: string = '';
  @Local nightAvailable: boolean = false;
  @Local spellingAnswer: string = '';
  @Local spellingFeedback: string = '';
  @Local pronunciationMessage: string = '';
  @Local quickRemaining: number = 180;
  @Local spellingEditing: boolean = false;
  @Local history: ReviewRecord[] = [];
  @Local words: Word[] = [];
  @Local searchText: string = '';
  @Local listTitle: string = '';
  @Local listBookId: string = '';
  @Local listFilter: string = 'all';
  @Local loadingWords: boolean = false;
  @Local reminderHour: string = '21';
  @Local reminderMinute: string = '00';
  @Local reminderStatusText: string = '';
  @Local reminderFeedback: string = '';
  @Local backupDate: string = '';
  @Local backupLearned: number = 0;
  @Local backupBooks: number = 0;
  @Local backupRecords: number = 0;
  @Local restoreFeedback: string = '';
  private pendingBackup?: DataExport;
  private restoring: boolean = false;
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
  private readonly welcomeScroller: Scroller = new Scroller();
  private animationReduceListening: boolean = false;
  private readonly animationReduceListener = (enabled: boolean): void => {
    if (this.active) {
      this.reduceMotion = enabled;
      this.pathStack.disableAnimation(enabled);
    }
  };
  private readonly immersivePrimaryNavigation: CommonModifier = new CommonModifier()
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  private readonly defaultPrimaryNavigation: CommonModifier = new CommonModifier();
  private readonly titleButtonMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true
  });
  private openingStudy: boolean = false;
  @Local summaryWords: Word[] = [];
  private pathStack: NavPathStack = new NavPathStack();
  private service: LearningService = LearningService.getInstance();
  private startedAt: number = Date.now();
  private searchTimer: number = -1;
  private searchVersion: number = 0;
  private quickTimer: number = -1;
  private homeTimer: number = -1;
  private currentDay: string = dateKey();
  private refreshVersion: number = 0;
  private reminderMutation: boolean = false;
  private activityOpening: boolean = false;
  private recalledMs: number = 0;
  private wordLoadVersion: number = 0;
  private studyNavigationVersion: number = 0;
  private appForeground: boolean = true;
  private active: boolean = false;
  private autoPronunciationNotice: string = '';
  private readonly pronunciation: PronunciationPresenter = new PronunciationPresenter();
  private studyWordBeforeDetail?: Word;
  private studyProgressBeforeDetail?: WordProgress;
  private studyEnrichmentBeforeDetail?: WordEnrichment;
  private foldListener: () => void = (): void => {
    if (this.appForeground && this.ready && this.snapshot.settings.onboarded && this.pathStack.size() === 0) { this.openActivity('Desk'); }
  };
  private visibilityListener: (visible: boolean) => void = (visible: boolean): void => {
    this.appForeground = visible;
    if (!visible) { this.stopQuickTimer(); this.pronunciation.cancel(); }
    else {
      this.nightAvailable = new Date().getHours() >= 21;
      if (this.ready) { this.refresh().catch(() => {}); }
      if (this.session.mode === 'quick' && this.pathStack.getAllPathName().slice(-1)[0] === 'Learn') { this.startQuickTimer(); }
    }
  };
  private routeListener: (route: string, wordId: number) => void = (route: string, wordId: number): void => {
    this.handleRoute(route, wordId);
  };

  aboutToAppear(): void {
    this.active = true;
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
      this.pathStack.disableAnimation(this.reduceMotion);
      accessibility.onAnimationReduceStateChange(this.animationReduceListener);
      this.animationReduceListening = true;
    } catch { this.reduceMotion = true; this.pathStack.disableAnimation(true); }
    this.context().eventHub.on('openRoute', this.routeListener);
    this.context().eventHub.on('halfFolded', this.foldListener);
    this.context().eventHub.on('appVisibility', this.visibilityListener);
    this.homeTimer = setInterval(() => {
      this.nightAvailable = new Date().getHours() >= 21;
      const day = dateKey();
      if (day !== this.currentDay && this.ready) {
        this.currentDay = day;
        this.refresh().catch(() => {});
      }
    }, 60000);
    this.initialize();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.refreshVersion++;
    if (this.animationReduceListening) {
      try { accessibility.offAnimationReduceStateChange(this.animationReduceListener); } catch {}
      this.animationReduceListening = false;
    }
    this.pronunciation.cancel();
    this.wordLoadVersion++;
    this.studyNavigationVersion++;
    this.context().eventHub.off('openRoute', this.routeListener);
    this.context().eventHub.off('halfFolded', this.foldListener);
    this.context().eventHub.off('appVisibility', this.visibilityListener);
    this.stopQuickTimer();
    if (this.homeTimer >= 0) { clearInterval(this.homeTimer); }
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    if (!AudioFlowService.getInstance().isActive()) { AudioService.getInstance().release(); }
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
      this.applyTheme();
      ReminderService.cleanupLegacyTests(this.context()).catch(() => {});
      this.ready = true;
      this.nightAvailable = new Date().getHours() >= 21;
      this.dispatchInitialRoute();
      if (AppStorage.get<boolean>('lexiglowHalfFolded') && this.pathStack.size() === 0) { this.foldListener(); }
    } catch (err) {
      this.error = '本地词库暂时没能打开，请重试。你的学习记录会保留。';
    }
  }

  private todayNewCount(snapshot: AppSnapshot = this.snapshot): number {
    return snapshot.stats.days.find((day: DaySummary) => day.date === dateKey())?.newCount || 0;
  }

  async refresh(): Promise<void> {
    if (this.restoring) { return; }
    const version = ++this.refreshVersion;
    const snapshot = await this.service.getSnapshot();
    if (version !== this.refreshVersion || this.reminderMutation) { return; }
    this.snapshot = snapshot;
    if (this.pathStack.getAllPathName().slice(-1)[0] !== 'Learn') { this.refreshExperience(); }
    FormService.update(snapshot, this.context()).catch(() => {});
    try {
      await ReminderService.syncDailyProgress(this.context(), snapshot.settings, this.todayNewCount(snapshot));
    } catch (error) {
      if (this.active && version === this.refreshVersion) {
        this.reminderFeedback = '学习记录已保存，提醒状态暂未同步。' + (error as Error).message;
      }
    }
  }

  private async refreshExperience(): Promise<void> {
    const version = ++this.experienceVersion;
    try {
      const attempts = await ExperienceService.getInstance().attempts();
      const session = this.service.getSession();
      const records: ReviewRecord[] = [];
      // At most one day's bounded session, never scan the whole review history on the UI thread.
      for (const item of session.items.slice(0, session.index)) {
        const history = await this.service.getHistory(item.word.id);
        records.push(...history);
      }
      const recommendation = recommendPractice(attempts, session, records);
      const readings = await ArticleService.getInstance().recommendations();
      if (version !== this.experienceVersion) { return; }
      this.recommendation = recommendation; this.readingPick = readings[0] || new ReadingRecommendation(); this.experienceError = '';
    } catch { if (version === this.experienceVersion) { this.experienceError = '学习建议暂未载入，点此重试'; } }
  }

  private openReading(id: number, key: string = ''): void {
    this.articleId = id; this.articleSourceKey = key;
    this.pathStack.pushPathByName('Article', id);
  }

  private async openRecommendedPractice(): Promise<void> {
    const mode = this.recommendation.mode;
    if (!mode) { this.pathStack.pushPathByName('Articles', ''); return; }
    this.preferredIds = this.recommendation.wordIds.slice();
    try {
      await AudioFlowService.getInstance().stop();
      this.pathStack.pushPathByName(mode === 'meaning' ? 'MeaningChallenge' : mode === 'dictation' ? 'Dictation' :
        mode === 'cloze' ? 'Cloze' : 'Spelling', 'recommended');
    } catch { this.toast('练习暂时无法打开，请重试。'); }
  }

  private openPracticeLibrary(): void {
    this.preferredIds = []; this.pathStack.pushPathByName('PracticeLibrary', '');
  }

  private startToday(): void {
    if (this.todayComplete()) { this.pathStack.pushPathByName('Articles', ''); return; }
    const session = this.service.getSession();
    this.beginStudy(session.index < session.items.length ? session.mode : 'today');
  }

  applyTheme(): void {
    const mode = this.snapshot.settings.themeMode;
    this.context().getApplicationContext().setColorMode(mode === 'dark' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK : mode === 'light' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  handleRoute(route: string, wordId: number): void {
    if (!this.ready || !this.snapshot.settings.onboarded || this.restoring) { return; }
    AppStorage.setOrCreate('launchRoute', '');
    this.wordLoadVersion++;
    this.studyNavigationVersion++;
    this.studyWordBeforeDetail = undefined;
    this.studyProgressBeforeDetail = undefined;
    this.studyEnrichmentBeforeDetail = undefined;
    this.stopQuickTimer();
    LiveStudyService.getInstance().stop();
    this.pathStack.clear();
    if (route === 'todayPlan') {
      this.tab = 0;
      this.pathStack.pushPathByName('TodayPlan', '');
    }
    else if (route === 'word') { this.openWord(wordId || this.snapshot.dailyWord.id); }
    else if (route === 'shared') {
      this.sharedText = AppStorage.get<string>('lexiglowSharedText') || '';
      if (this.sharedText) { this.pathStack.pushPathByName('SharedWords', ''); }
    }
    else if (route === 'audioFlow') { this.openActivity('AudioFlow'); }
    else if (route === 'night' || route === 'desk') { this.openActivity(route === 'night' ? 'Night' : 'Desk'); }
    else if (route === 'spelling' || route === 'constellation') {
      this.pathStack.pushPathByName(route === 'spelling' ? 'Spelling' : 'Constellation', '');
    }
    else if (route === 'review' || route === 'quick' || route === 'today') { this.beginStudy(route); }
  }

  private welcomeTransition(): TransitionEffect {
    if (this.reduceMotion) { return TransitionEffect.IDENTITY; }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 220, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) }),
      TransitionEffect.IDENTITY
    );
  }

  private setWelcomeStep(step: number): void {
    if (this.busy || step < 0 || step > 3 || step === this.welcomeStep) { return; }
    this.welcomeScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.welcomeStep = step;
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
      if (AppStorage.get<string>('launchRoute')) { this.dispatchInitialRoute(); }
      else { await this.beginStudy('onboarding'); }
    } catch (err) { this.toast('设置没有保存成功，请再试一次。'); }
    this.busy = false;
  }

  async beginStudy(mode: string): Promise<void> {
    if (!this.ready || this.openingStudy) { return; }
    this.openingStudy = true;
    const navigationVersion = ++this.studyNavigationVersion;
    try {
      await AudioFlowService.getInstance().stop();
      if (navigationVersion !== this.studyNavigationVersion) { this.openingStudy = false; return; }
      const session = await this.service.startSession(mode);
      if (navigationVersion !== this.studyNavigationVersion) { this.openingStudy = false; return; }
      this.session = session;
      this.answerVisible = false;
      if (this.session.items.length === 0) {
        this.toast(mode === 'review' ? '今天暂时没有到期词，可以学几个新词。' : '这本词书已经学完，可以换一本或稍后复习。');
        this.openingStudy = false;
        return;
      }
      await this.loadStudyWord();
      if (navigationVersion !== this.studyNavigationVersion) { this.openingStudy = false; return; }
      this.pathStack.pushPathByName('Learn', mode);
      if (mode === 'quick') { this.startQuickTimer(); this.updateLiveStudy(true); }
    } catch (err) { this.toast('学习队列没能载入，请重试。'); }
    this.openingStudy = false;
  }

  async loadStudyWord(): Promise<void> {
    if (this.session.index < this.session.items.length) {
      const version = ++this.wordLoadVersion;
      const word = this.session.items[this.session.index].word;
      const progress = await this.service.getProgress(word.id);
      const enrichment = await this.service.getWordEnrichment(word.id);
      if (version !== this.wordLoadVersion) { return; }
      this.currentWord = word;
      this.currentProgress = progress;
      this.enrichment = enrichment;
      this.spellingAnswer = '';
      this.spellingFeedback = '';
      this.pronunciationMessage = '';
      this.pronunciation.cancel();
      this.answerVisible = false;
      this.answerOpacity = 0;
      this.startedAt = Date.now();
      this.recalledMs = 0;
      if (this.snapshot.settings.autoPronounce) {
        this.autoPronounceWord(word, version);
      }
    }
  }

  showAnswer(): void {
    if (this.answerVisible || this.busy) { return; }
    this.answerVisible = true;
    this.recalledMs = Math.max(0, Date.now() - this.startedAt);
    HapticService.pulse(this.snapshot.settings.hapticsEnabled);
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.answerOpacity = 1; });
  }

  async judge(result: ReviewResult): Promise<void> {
    if (this.busy || !this.answerVisible || this.currentWord.id !== this.session.items[this.session.index]?.word.id) { return; }
    this.busy = true;
    const navigationVersion = this.studyNavigationVersion;
    try {
      const judgedWord = this.currentWord.word;
      const session = await this.service.record(result, this.recalledMs);
      this.undoAvailable = this.service.canUndo(); this.lastJudgedWord = judgedWord;
      await this.refresh().catch(() => {});
      if (navigationVersion !== this.studyNavigationVersion) { this.busy = false; return; }
      this.session = session;
    } catch (err) {
      if (navigationVersion !== this.studyNavigationVersion) { this.busy = false; return; }
      this.toast('这一词还没有保存，请再点一次。'); this.busy = false; return;
    }
    this.answerVisible = false;
    HapticService.pulse(this.snapshot.settings.hapticsEnabled, result === ReviewResult.KNOW ? 20 : 12);
    this.updateLiveStudy(false);
    if (navigationVersion !== this.studyNavigationVersion) { this.busy = false; return; }
    if (this.session.index >= this.session.items.length) {
      this.stopQuickTimer();
      LiveStudyService.getInstance().stop();
      HapticService.complete(this.snapshot.settings.hapticsEnabled);
      AudioService.getInstance().stop();
      this.pathStack.replacePathByName('Summary', this.session.mode);
    } else {
      await this.loadStudyWord().catch(() => { this.toast('下一词暂时没能载入，可以返回后继续。'); });
    }
    this.busy = false;
  }

  async undoJudgment(): Promise<void> {
    if (this.busy || !this.undoAvailable) { return; }
    this.busy = true;
    const version = this.studyNavigationVersion;
    try {
      const session = await this.service.undoLast();
      if (version !== this.studyNavigationVersion) { return; }
      this.session = session; this.undoAvailable = false;
      if (this.pathStack.getAllPathName().slice(-1)[0] === 'Summary') {
        this.pathStack.replacePathByName('Learn', session.mode);
      }
      await this.loadStudyWord(); await this.refresh();
      if (session.mode === 'quick') { this.startQuickTimer(); }
      this.updateLiveStudy(false);
      this.toast('已撤销，按真实回忆重新判断。');
    } catch (error) { this.toast((error as Error).message || '撤销暂未完成，请重试'); }
    finally { this.busy = false; }
  }

  private invalidateUndo(): void {
    this.undoAvailable = false;
    this.service.invalidateUndo().catch(() => {});
  }

  async leaveStudy(): Promise<void> {
    this.invalidateUndo();
    this.wordLoadVersion++;
    this.studyNavigationVersion++;
    this.stopQuickTimer();
    LiveStudyService.getInstance().stop();
    AudioService.getInstance().stop();
    this.pathStack.pop();
    await this.refresh().catch(() => {});
  }

  private async openPractice(name: string): Promise<void> {
    try {
      await AudioFlowService.getInstance().stop();
      AudioService.getInstance().stop(); this.pathStack.pushPathByName(name, '');
    } catch (_) { this.toast('请稍后再打开练习。'); }
  }

  private async openActivity(name: string): Promise<void> {
    if (this.activityOpening || !this.ready) { return; }
    this.activityOpening = true;
    try {
      if (name === 'AudioFlow') {
        this.activityWords = AudioFlowService.getInstance().isActive() ? [] : await this.service.getAudioWords(30);
      } else {
        await AudioFlowService.getInstance().stop();
        AudioService.getInstance().stop();
        this.activityWords = name === 'Night' ? await this.service.getNightWords(5) : await this.service.getDeskWords(30);
      }
      this.pathStack.pushPathByName(name, '');
    } catch { this.toast('单词暂时没能载入，请重试。'); }
    finally { this.activityOpening = false; }
  }

  private async openRelatedWord(id: number): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    if (this.pathStack.getAllPathName().indexOf('Learn') >= 0 && !this.studyWordBeforeDetail) {
      this.studyWordBeforeDetail = this.currentWord;
      this.studyProgressBeforeDetail = this.currentProgress;
      this.studyEnrichmentBeforeDetail = this.enrichment;
    }
    if (this.pathStack.getAllPathName().slice(-1)[0] === 'WordDetail') { this.pathStack.pop(); }
    await this.openWord(id);
    this.busy = false;
  }

  private microSpellingActive(): boolean {
    return this.snapshot.settings.spellingRecall && this.currentProgress.strength >= 75 &&
      this.session.items[this.session.index]?.type === 'review' && /^[a-z]{3,30}$/i.test(this.currentWord.word);
  }

  private checkMicroSpelling(): void {
    this.spellingFeedback = spellingMatches(this.currentWord.word, this.spellingAnswer) ? '拼对了。' : '再看一眼拼写，按真实回忆选择。';
    this.getUIContext().getFocusController().clearFocus();
    this.spellingEditing = false;
    this.showAnswer();
  }

  private liveState(): StudyLiveState {
    const state = new StudyLiveState();
    state.startedAt = this.session.startedAt;
    state.completed = this.session.index;
    state.total = this.session.items.length;
    return state;
  }

  private updateLiveStudy(start: boolean): void {
    if (this.session.mode !== 'quick') { return; }
    if (start) { LiveStudyService.getInstance().start(this.liveState()); }
    else { LiveStudyService.getInstance().update(this.liveState()); }
  }

  private stopQuickTimer(): void {
    if (this.quickTimer >= 0) { clearInterval(this.quickTimer); this.quickTimer = -1; }
  }

  private startQuickTimer(): void {
    this.stopQuickTimer();
    // A resumed quick session receives its remaining time; saved judgments remain durable.
    const update = (): void => {
      this.quickRemaining = Math.max(0, 180 - Math.floor((Date.now() - this.session.startedAt) / 1000));
      if (this.quickRemaining === 0 && !this.busy) {
        this.stopQuickTimer();
        LiveStudyService.getInstance().stop();
        AudioService.getInstance().stop();
        if (this.pathStack.getAllPathName().slice(-1)[0] === 'Learn') {
          this.pathStack.replacePathByName('Summary', 'quick');
        }
      }
    };
    update();
    if (this.quickRemaining > 0) { this.quickTimer = setInterval(update, 1000); }
  }

  async leaveSummary(): Promise<void> {
    this.invalidateUndo();
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
    const wordId = this.currentWord.id;
    const version = this.wordLoadVersion;
    const route = this.pathStack.getAllPathName().slice(-1)[0] || '';
    await this.pronunciation.play(text, this.getUIContext(),
      (): boolean => this.active && this.appForeground && version === this.wordLoadVersion &&
        wordId === this.currentWord.id && text === this.currentWord.word &&
        route === (this.pathStack.getAllPathName().slice(-1)[0] || ''),
      (_state: string, message: string): void => { this.pronunciationMessage = message; });
  }

  private async autoPronounceWord(word: Word, version: number): Promise<void> {
    try { await AudioService.getInstance().speak(word.word); }
    catch (error) {
      if (!this.active || !this.appForeground || version !== this.wordLoadVersion || word.id !== this.currentWord.id) { return; }
      const message = `${(error as Error).message || '自动朗读失败。'} 可使用单词旁的发音按钮重试。`;
      this.pronunciationMessage = message;
      if (this.autoPronunciationNotice !== message) { this.autoPronunciationNotice = message; this.toast(message); }
    }
  }

  async copyWord(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.currentWord.word));
      this.toast('单词已复制');
    } catch (err) { this.toast('暂时无法复制'); }
  }

  async openWord(id: number, bookId: string = ''): Promise<void> {
    const version = ++this.wordLoadVersion;
    try {
      const word = bookId ? await this.service.getBookWord(bookId, id) : await this.service.getWord(id);
      const progress = await this.service.getProgress(id);
      const history = await this.service.getHistory(id);
      const enrichment = await this.service.getWordEnrichment(id);
      if (version !== this.wordLoadVersion) { return; }
      this.detailBookId = bookId;
      this.currentWord = word;
      this.currentProgress = progress;
      this.history = history;
      this.enrichment = enrichment;
      this.pathStack.pushPathByName('WordDetail', id);
    } catch (err) {
      if (version !== this.wordLoadVersion) { return; }
      if (this.studyWordBeforeDetail && this.studyProgressBeforeDetail && this.studyEnrichmentBeforeDetail) {
        this.currentWord = this.studyWordBeforeDetail; this.currentProgress = this.studyProgressBeforeDetail;
        this.enrichment = this.studyEnrichmentBeforeDetail;
        this.studyWordBeforeDetail = undefined; this.studyProgressBeforeDetail = undefined; this.studyEnrichmentBeforeDetail = undefined;
      }
      this.toast('这个单词暂时无法打开。');
    }
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
    this.searchVersion++;
    this.loadingWords = true;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => { this.search(); }, 180);
  }

  async search(): Promise<void> {
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
    const version = ++this.searchVersion;
    this.loadingWords = true;
    try {
      const result = await this.service.getWords(this.listBookId, this.listFilter, this.searchText);
      if (version === this.searchVersion) { this.words = result; }
    } catch (err) {
      if (version === this.searchVersion) {
        this.words = [];
        this.toast('搜索暂时不可用，请重试。');
      }
    }
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
    this.refreshVersion++;
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
    const settings = this.copySettings();
    settings.autoPronounce = enabled;
    settings.autoPronounceConfigured = true;
    await this.saveSettings(settings);
  }

  async saveReminder(enabled: boolean): Promise<void> {
    if (this.busy) { return; }
    const hour = Number(this.reminderHour); const minute = Number(this.reminderMinute);
    if (enabled && (!/^\d{1,2}$/.test(this.reminderHour) || !/^\d{1,2}$/.test(this.reminderMinute) ||
      !Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59)) {
      this.toast('请填写有效的时间：小时 0–23，分钟 0–59。'); return;
    }
    this.busy = true;
    this.reminderMutation = true;
    this.refreshVersion++;
    const previousSettings = this.copySettings();
    try {
      await ReminderService.configure(this.context(), enabled, hour, minute,
        this.todayNewCount(), this.snapshot.settings.dailyNewTarget);
      const settings = this.copySettings();
      settings.reminderEnabled = enabled; settings.reminderHour = hour; settings.reminderMinute = minute;
      const saved = await this.saveSettings(settings);
      if (!saved) {
        await ReminderService.configure(this.context(), previousSettings.reminderEnabled,
          previousSettings.reminderHour, previousSettings.reminderMinute,
          this.todayNewCount(), previousSettings.dailyNewTarget);
        throw new Error('提醒偏好未保存，已恢复原提醒设置。');
      }
      this.reminderMutation = false;
      await this.refresh().catch(() => {});
      this.reminderFeedback = enabled ? (this.todayNewCount() >= this.snapshot.settings.dailyNewTarget ?
        '今天的目标已完成，今天不再提醒；明天继续按设定时间判断。' : '每日提醒已开启，未完成当天目标时才会提醒。') : '每日学习提醒已关闭。';
      this.toast(enabled ? '学习提醒已开启' : '学习提醒已关闭');
      await this.refreshReminderStatus();
    } catch (err) {
      this.reminderFeedback = (err as Error).message || '提醒未能设置，请检查通知权限和设备支持。';
      this.toast(this.reminderFeedback);
    }
    this.reminderMutation = false;
    this.busy = false;
  }

  async refreshReminderStatus(): Promise<void> {
    try {
      const status = await ReminderService.status(this.context());
      if (!this.active) { return; }
      this.reminderStatusText = status.notificationEnabled ?
        `系统通知已允许 · ${status.dailyReminderId >= 0 ? (status.dailySkippedToday ? '今天不再提醒，明天继续' : '每日提醒已登记') : '每日提醒未登记'}` :
        '系统通知未允许，请在系统设置中开启词萤通知。';
    } catch (err) {
      if (this.active) { this.reminderStatusText = (err as Error).message || '暂时无法读取提醒状态。'; }
    }
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

  async selectBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const backup = await TransferService.importBackup(this.context());
      this.pendingBackup = backup;
      this.backupDate = new Date(backup.exportedAt).toLocaleString();
      this.backupLearned = backup.progress.filter((item: WordProgress) => item.reviewCount > 0).length;
      this.backupBooks = backup.books.filter((book: DictionaryBook) => book.category === 'custom').length;
      this.backupRecords = backup.records.length;
      this.restoreFeedback = '';
      this.pathStack.pushPathByName('RestoreBackup', '');
    } catch (error) {
      const message = (error as Error).message || '备份读取失败，请重新选择。';
      if (!message.startsWith('已取消')) { this.toast(message); }
    } finally { this.busy = false; }
  }

  async confirmRestore(): Promise<void> {
    if (this.busy || !this.pendingBackup) { return; }
    this.busy = true;
    this.restoring = true;
    this.refreshVersion++;
    this.restoreFeedback = '正在恢复，请稍候…';
    this.pronunciation.cancel();
    this.stopQuickTimer();
    try {
      this.restoreSkipped = await this.service.restoreData(this.pendingBackup);
    } catch (error) {
      this.restoreFeedback = '恢复未完成，本机原有数据已保留。' + (error as Error).message;
      this.restoring = false;
      this.busy = false;
      return;
    }
    // Persistence has committed. A subsequent UI or reminder refresh cannot undo that success.
    this.pendingBackup = undefined;
    this.session = this.service.getSession();
    this.words = []; this.history = []; this.summaryWords = [];
    this.studyWordBeforeDetail = undefined; this.studyProgressBeforeDetail = undefined;
    this.studyEnrichmentBeforeDetail = undefined;
    this.wordLoadVersion++; this.studyNavigationVersion++;
    this.pathStack.clear(); this.tab = 3;
    this.restoring = false;
    try {
      await this.refresh();
      this.applyTheme();
      this.toast(this.restoreSkipped > 0 ? `学习进度已恢复，${this.restoreSkipped} 个词头未匹配，已跳过。` : '学习进度已恢复');
    } catch (_) { this.toast('学习进度已恢复，请重新打开页面查看。'); }
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
    if (this.todayComplete()) { return '今日计划完成，读一小篇  →'; }
    const session = this.service.getSession();
    return session.index < session.items.length ? '继续上次的学习  →' : '开始今天的学习  →';
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

  mainContentWidth(index: number = 0): number {
    const paneWidth = this.mainPaneWidth();
    return Math.max(0, Math.min(primaryPageMaxWidth(index), paneWidth) - this.mainPagePadding() * 2);
  }

  useDashboardColumns(): boolean { return dashboardUsesColumns(this.mainContentWidth(2)); }

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

  handleStudyKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (this.busy) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.leaveStudy(); return true; }
    if (this.spellingEditing) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_P || event.keyCode === KeyCode.KEYCODE_R) { this.pronounce(this.currentWord.word); return true; }
    if (event.keyCode === KeyCode.KEYCODE_S) { this.toggleFavorite(); return true; }
    if (event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_ENTER) {
      if (!this.answerVisible && this.session.index < this.session.items.length) { this.showAnswer(); return true; }
      return false;
    }
    if (!this.answerVisible) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_1 || event.keyCode === KeyCode.KEYCODE_J) { this.judge(ReviewResult.FORGET); return true; }
    if (event.keyCode === KeyCode.KEYCODE_2 || event.keyCode === KeyCode.KEYCODE_K) { this.judge(ReviewResult.FUZZY); return true; }
    if (event.keyCode === KeyCode.KEYCODE_3 || event.keyCode === KeyCode.KEYCODE_L) { this.judge(ReviewResult.KNOW); return true; }
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
    Scroll(this.welcomeScroller) {
    Row() {
      Column({ space: 24 }) {
        Row() {
          Text('LexiGlow').fontSize(13).letterSpacing(3).fontColor($r('app.color.text_secondary'))
          Blank()
          Text(`${this.welcomeStep + 1} / 4`).fontSize(13).fontColor($r('app.color.text_secondary'))
        }.width('100%')
        ForEach([this.welcomeStep], (step: number) => {
          Column({ space: 24 }) {
            this.WelcomeStep(step)
          }.width('100%').transition(this.welcomeTransition())
        }, (step: number) => `${step}`)
        if (this.welcomeStep > 0) {
          Button('上一步').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
            .onClick(() => { this.setWelcomeStep(this.welcomeStep - 1); })
        }
      }.padding(26).width('100%').constraintSize({ maxWidth: 620 })
    }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  @Builder
  WelcomeStep(step: number) {
    if (step === 0) {
      Column({ space: 24 }) {
        Image($r('app.media.ciying_icon')).width(112).height(112).borderRadius(30)
        Text('词萤').fontSize(42).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text('让单词一点一点亮起来').fontSize(21).fontColor($r('app.color.text_primary'))
        Text('每天一点光，慢慢记住更多词。\n从 3 个词开始，也是一份进步。')
          .fontSize(16).fontColor($r('app.color.text_secondary')).lineHeight(29).textAlign(TextAlign.Center)
      }.width('100%').padding({ top: 50, bottom: 48 })
      this.Action({ label: '开始点亮第一个词  →', action: () => { this.setWelcomeStep(1); }, primary: true })
      Text('无需注册 · 学习记录保存在本机').fontSize(13).fontColor($r('app.color.text_secondary'))
    } else if (step === 1) {
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
      this.Action({ label: '继续', action: () => { this.setWelcomeStep(2); }, primary: true })
    } else if (step === 2) {
      this.PageHeading({ title: '从你现在的节奏开始', subtitle: '选择起点，会为你推荐下一步的每日目标。' })
      this.FoundationOption('beginner', '刚开始', '先熟悉核心词，每次只学一点。')
      this.FoundationOption('regular', '有一点基础', '新词和复习，保持一个舒服的比例。')
      this.FoundationOption('sprint', '正在冲刺', '优先稳住到期词，再认识新词。')
      this.Action({ label: '继续', action: () => { this.setWelcomeStep(3); }, primary: true })
    } else {
      this.PageHeading({ title: '每天留一点时间给自己', subtitle: '先定一个小目标，之后可在“我的”中调整。' })
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
  }

  @Builder
  FoundationOption(value: string, title: string, subtitle: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 9 }) {
        Text(title).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(subtitle).fontSize(14).fontColor(this.foundation === value ? $r('app.color.glow_secondary') : $r('app.color.text_secondary')).lineHeight(23)
      }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }.width('100%').borderRadius(22).backgroundColor(this.foundation === value ?
      $r('app.color.glow') : $r('app.color.surface')).onClick(() => {
        if (this.foundation !== value) {
          this.foundation = value;
          this.selectedTarget = value === 'beginner' ? 10 : value === 'sprint' ? 30 : 20;
        }
      })
  }

  @Builder
  HomeDueCard() {
    if (this.snapshot.dueCount > 0) {
      Row({ space: 15 }) {
        Column({ space: 6 }) {
          Text('该和老朋友见面了').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.snapshot.plan.backlogCount > 100 ?
            `${this.snapshot.dueCount} 个到期词 · 今天先复习 ${Math.max(0, this.snapshot.plan.reviewTarget - this.snapshot.plan.reviewDone)} 个` :
            `${this.snapshot.dueCount} 个到期词 · 分几次完成也可以`).fontSize(13).fontColor($r('app.color.text_secondary'))
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
      this.Action({ label: this.todayActionLabel(), action: () => { this.startToday(); }, primary: true })
    }.padding(this.compactMainPage() ? 20 : 24).width('100%').backgroundColor($r('app.color.glow')).borderRadius(28)
  }

  @Builder
  TodayPlanPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 22 }) {
            this.PageHeading({ title: '今天，按自己的节奏来。', subtitle: `${dateKey()} · 查看今天的新词与复习目标` })
            this.HomePlanCard()
          }.padding(24).width('100%').constraintSize({ maxWidth: 680 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56)
        .contentEndOffset(bottomContentOffset(this.getUIContext()))
        .align(this.isMedium() ? Alignment.Top : Alignment.Center).scrollBar(BarState.Off)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
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
  HomeConstellationCard() {
    ConstellationHomeCard({ learnedCount: this.snapshot.stats.totalLearned,
      onOpen: () => { this.pathStack.pushPathByName('Constellation', ''); } })
  }

  @Builder
  HomeSceneCard() {
    Column({ space: 12 }) {
      Text('换一种方式记住它').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      this.Action({ label: '听词磨耳朵  ·  闭眼回忆', action: () => { this.openActivity('AudioFlow'); }, primary: false })
      this.Action({ label: '错题本 · 集中巩固', action: () => { this.pathStack.pushPathByName('Mistakes', ''); }, primary: false })
      this.Action({ label: '语境填空 · 在句子里用词', action: () => { this.openPractice('Cloze'); }, primary: false })
      this.Action({ label: '听音写词 · 5 词 90 秒', action: () => { this.openPractice('Dictation'); }, primary: false })
      this.Action({ label: '拼写速记  ·  5 词 90 秒', action: () => {
        AudioFlowService.getInstance().stop().then(() => { this.pathStack.pushPathByName('Spelling', ''); })
          .catch(() => { this.toast('听词暂未停止，请稍后再打开拼写速记。'); });
      }, primary: false })
      this.Action({ label: '书桌伴读  ·  静音翻页时钟', action: () => { this.openActivity('Desk'); }, primary: false })
      if (this.nightAvailable) {
        this.Action({ label: '晚间 30 秒过电影', action: () => { this.openActivity('Night'); }, primary: false })
      }
    }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
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
  HomeNextStepCard() {
    Column({ space: 14 }) {
      Text(this.recommendation.mode ? '可选的一小步' : '按自己的节奏来').fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.recommendation.mode) {
        Text(this.recommendation.reason).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
        this.Action({ label: this.recommendation.title, action: () => { this.openRecommendedPractice(); }, primary: false })
      }
      this.Action({ label: '专项练习 · 自己选一种方式', action: () => { this.openPracticeLibrary(); }, primary: false })
      if (this.experienceError) { Button(this.experienceError).fontColor($r('app.color.text_secondary')).onClick(() => { this.refreshExperience(); }) }
    }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  HomeReadingCard() {
    Column({ space: 12 }) {
      Text('今日读得懂').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text(this.readingPick.article.title || '把学过的词，放回生活里').fontSize(21).lineHeight(30)
        .fontColor($r('app.color.text_primary')).width('100%')
      Text(this.readingPick.article.id !== 0 ? `有 ${this.readingPick.learnedCount} 个词形已经学过 · 约 2 分钟` : '离线短文 · 点词收藏原句 · 读后回忆')
        .fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
      this.Action({ label: this.readingPick.paragraphIndex > 0 && !this.readingPick.completed ? '接着上次读 →' : '读一小篇 →',
        action: () => { if (this.readingPick.article.id !== 0) { this.openReading(this.readingPick.article.id); }
          else { this.pathStack.pushPathByName('Articles', ''); } }, primary: false })
    }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  PracticeLibraryPage() {
    Scroll() {
      Column({ space: 18 }) {
        Text('换一种方式，再记牢一些。').fontSize(25).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('独立练习不会增加今日背词任务。按自己的需要选择，也可以随时结束。').fontSize(14).lineHeight(24)
          .fontColor($r('app.color.text_secondary'))
        this.HomeChallengeCard()
        this.HomeSceneCard()
      }.padding({ top: 76, bottom: 40, left: 24, right: 24 }).width('100%').constraintSize({ maxWidth: 800 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
  }

  @Builder
  Home() {
    Column({ space: this.compactMainPage() ? 14 : 18 }) {
      this.PageHeading({ id: 'tab-heading-0', title: '今天，也只学一点点。', subtitle: this.snapshot.stats.streak > 0 ?
        `连续学习 ${this.snapshot.stats.streak} 天 · 每一次回忆都在积累` : '欢迎回来。今天从几个词开始就好。' })
      if (this.useHomeColumns()) {
        Row({ space: 24 }) {
          Column({ space: 18 }) {
            this.HomePlanCard()
            this.HomeOverviewCard()
            this.HomeConstellationCard()
          }.layoutWeight(1.15).alignItems(HorizontalAlign.Start)
          Column({ space: 18 }) {
            this.HomeQuickCards()
            this.HomeNextStepCard()
            this.HomeReadingCard()
            Text(`本周真正掌握 +${this.snapshot.stats.weekMastered} 词`).fontSize(13).fontColor($r('app.color.success'))
              .width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        this.HomePlanCard()
        this.HomeQuickCards()
        this.HomeNextStepCard()
        this.HomeConstellationCard()
        this.HomeReadingCard()
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
      this.Action({ label: '今日读得懂 · 精选短文与我的文章', action: () => { this.pathStack.pushPathByName('Articles', ''); }, primary: false })
      this.Action({ label: '我的原句 · 留下遇见单词的时刻', action: () => { this.pathStack.pushPathByName('Sentences', ''); }, primary: false })
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
      .width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
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
    }.padding(24).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
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
      .width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
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
              .backgroundColor(day.newCount > 0 || day.reviewCount > 0 ? $r('app.color.success') :
                day.glowing ? $r('app.color.glow') : $r('app.color.soft_surface')).borderRadius(8)
              .accessibilityText(`${day.date} 新词 ${day.newCount} 个，复习 ${day.reviewCount} 次${day.glowing ? '，已补光' : day.totalCount === 0 ? '，等待重新点亮' : ''}`)
          }
        }, (day: DaySummary) => JSON.stringify(day))
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').columnsGap(6).rowsGap(6).height(164)
      Text('暗下的光，等待重新点亮。补光日以淡金色显示。').fontSize(12).lineHeight(22).fontColor($r('app.color.text_secondary'))
    }.alignItems(HorizontalAlign.Start).padding(24)
      .width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  private todaySummary(): DaySummary {
    const key = dateKey(Date.now());
    return this.snapshot.stats.days.find((day: DaySummary) => day.date === key) || new DaySummary();
  }

  @Builder
  StatisticsPage() {
    Column({ space: 20 }) {
      this.PageHeading({ id: 'tab-heading-2', title: '记住的，正在变多。', subtitle: '每一次认真回忆，都算数。' })
      this.Action({ label: `错题本 · ${this.snapshot.mistakeCount}  →`, action: () => { this.pathStack.pushPathByName('Mistakes', ''); }, primary: false })
      Row({ space: 16 }) {
        this.SmallStat({ value: `${this.snapshot.stats.totalLearned}`, label: '已学习', highlighted: true })
        this.SmallStat({ value: `${this.snapshot.stats.mastered}`, label: '已掌握', highlighted: true })
        this.SmallStat({ value: `${this.snapshot.stats.streak}`, label: '连续学习天', highlighted: true })
      }.width('100%').padding(24).backgroundColor($r('app.color.glow')).borderRadius(24)
      if (this.useDashboardColumns()) {
        Row({ space: 20 }) {
          Column({ space: 20 }) {
            this.StatTodayCard()
            this.StatCalendarCard()
          }.layoutWeight(1)
          Column({ space: 20 }) {
            this.StatStrengthCard()
            this.StatWeekCard()
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 20 }) {
          this.StatTodayCard()
          this.StatStrengthCard()
          this.StatWeekCard()
          this.StatCalendarCard()
        }.width('100%')
      }
      DailyStudyCard({ date: dateKey(Date.now()), newCount: this.todaySummary().newCount, reviewCount: this.todaySummary().reviewCount,
        minutes: Math.round(this.todaySummary().durationMs / 60000) })
      if (this.snapshot.stats.glowDays.length > 0) {
        Text('用今天的光，温暖了昨天遗漏的记忆。').fontSize(14).fontColor($r('app.color.success')).width('100%')
      }
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
      Text('每日计划按此目标安排新词，复习单独计算。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(22).alignItems(HorizontalAlign.Start)
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
      PronunciationSettings()
      Divider().color($r('app.color.divider'))
      Row() {
        Text('熟词复习先试拼写').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.snapshot.settings.spellingRecall })
          .selectedColor($r('app.color.success')).onChange((value: boolean) => {
            const settings = this.copySettings(); settings.spellingRecall = value; this.saveSettings(settings);
          })
      }.width('100%')
      Row() {
        Text('轻触反馈').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.snapshot.settings.hapticsEnabled })
          .selectedColor($r('app.color.success')).onChange((value: boolean) => {
            const settings = this.copySettings(); settings.hapticsEnabled = value; this.saveSettings(settings);
          })
      }.width('100%')
    }.width('100%').padding(22).alignItems(HorizontalAlign.Start)
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
    }.width('100%').padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  ProfileActions() {
    Column({ space: 12 }) {
      this.Action({ label: '学习提醒  ·  ' + (this.snapshot.settings.reminderEnabled ? '已开启' : '未开启'), action: () => { this.pathStack.pushPathByName('Reminders', ''); }, primary: false })
      this.Action({ label: '导出学习数据', action: () => { this.exportData(); }, primary: false })
      this.Action({ label: '从备份恢复进度', action: () => { this.selectBackup(); }, primary: false })
      this.Action({ label: '数据与隐私', action: () => { this.pathStack.pushPathByName('Privacy', ''); }, primary: false })
    }.width('100%')
  }

  @Builder
  ProfileDataCard() {
    Column({ space: 16 }) {
      Text('数据与提醒').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      this.ProfileActions()
    }.width('100%').padding(22).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  Profile() {
    Column({ space: 20 }) {
      this.PageHeading({ id: 'tab-heading-3', title: '按自己的节奏来。', subtitle: '这里的设置，都是为了学得更舒服。' })
      if (this.useDashboardColumns()) {
        Row({ space: 20 }) {
          Column({ space: 20 }) {
            this.ProfileTargetCard()
            this.ProfilePreferenceCard()
          }.layoutWeight(1)
          Column({ space: 20 }) {
            this.ProfileAppearanceCard()
            this.ProfileDataCard()
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 20 }) {
          this.ProfileTargetCard()
          this.ProfilePreferenceCard()
          this.ProfileAppearanceCard()
          this.ProfileActions()
        }.width('100%')
      }
      Text('词萤 LexiGlow  1.2.1\n让单词一点一点亮起来').fontSize(12).lineHeight(21)
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
      if (this.session.mode === 'quick') {
        Text(`3 分钟速学 · 还有 ${Math.floor(this.quickRemaining / 60)}:${(this.quickRemaining % 60).toString().padStart(2, '0')}`)
          .fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 10 })
      }
      Scroll() {
        Row() {
          Column({ space: 24 }) {
            Text(this.session.items[this.session.index]?.type === 'review' ? '再次见面' : '认识一个新词')
              .fontSize(13).letterSpacing(2).fontColor($r('app.color.text_secondary'))
            Text(this.microSpellingActive() && !this.answerVisible ? spellingHint(this.currentWord.word) : this.currentWord.word)
              .fontSize(this.isWide() ? 52 : 40).fontWeight(FontWeight.Medium).fontFamily('serif')
              .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center).maxLines(2)
              .gesture(LongPressGesture().onAction(() => { this.copyWord(); }))
            Row({ space: 12 }) {
              Text(this.currentWord.phonetic).fontSize(16).fontColor($r('app.color.text_secondary'))
              Button('♪').width(48).height(48).fontSize(24).backgroundColor($r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).accessibilityText('播放英文发音').onClick(() => { this.pronounce(this.currentWord.word); })
            }
            if (this.pronunciationMessage) {
              Text(this.pronunciationMessage).fontSize(13).lineHeight(22)
                .fontColor($r('app.color.text_secondary')).width('100%')
            }
            if (this.answerVisible) {
              Column({ space: 20 }) {
                if (this.spellingFeedback) { Text(this.spellingFeedback).fontSize(15).fontColor($r('app.color.success')) }
                Text(this.currentWord.meaning).fontSize(22).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary')).lineHeight(32).width('100%')
                WordKnowledgeCard({ enrichment: this.enrichment, autoExpand: this.currentProgress.consecutiveFailures >= 2,
                  onOpenWord: (id: number) => { this.openRelatedWord(id); } })
                if (this.currentWord.example) {
                Divider().color($r('app.color.divider'))
                Text(this.currentWord.example).fontSize(18).fontColor($r('app.color.text_primary')).lineHeight(29).width('100%')
                Text(this.currentWord.translation).fontSize(15).fontColor($r('app.color.text_secondary')).lineHeight(25).width('100%')
                }
              }.padding(26).width('100%').backgroundColor($r('app.color.surface')).borderRadius(26)
                .opacity(this.answerOpacity).translate({ y: (1 - this.answerOpacity) * 8 })
            } else {
              if (this.microSpellingActive()) {
                Text(this.currentWord.meaning).fontSize(20).lineHeight(31).fontColor($r('app.color.text_primary'))
                TextInput({ text: this.spellingAnswer, placeholder: '中间字母，或完整单词' }).height(56).maxLength(30)
                  .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface'))
                  .onChange((value: string) => { this.spellingAnswer = value; })
                  .onFocus(() => { this.spellingEditing = true; }).onBlur(() => { this.spellingEditing = false; })
                  .onSubmit(() => { this.checkMicroSpelling(); })
                Button('检查拼写').height(48).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                  .onClick(() => { this.checkMicroSpelling(); })
              } else {
                Text('先想一想，它的意思是什么？').fontSize(16).fontColor($r('app.color.text_secondary')).margin({ top: 36 })
                WordExperiencePanel({ wordId: this.currentWord.id, compact: true })
              }
            }
            if (this.currentProgress.lastResponseMs > 3500 || this.currentProgress.consecutiveFailures >= 2) {
              Text('这个词值得慢慢巩固，可以借助搭配和辨析。').fontSize(12).lineHeight(22).fontColor($r('app.color.text_secondary'))
            }
          }.width('100%').padding({ left: 26, right: 26, top: this.viewportHeight < 480 ? 12 : 46, bottom: 24 })
            .constraintSize({ maxWidth: 640 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Column({ space: 14 }) {
        if (this.undoAvailable) {
          Button(`已判断 ${this.lastJudgedWord} · 撤销`).height(40).width('100%')
            .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
            .enabled(!this.busy).onClick(() => { this.undoJudgment(); })
        }
        if (this.answerVisible) {
          Row({ space: 9 }) {
            this.Judgment('不认识', '早点再见一次', ReviewResult.FORGET)
            this.Judgment('模糊', '再巩固一下', ReviewResult.FUZZY)
            this.Judgment('认识', '能回忆核心意思', ReviewResult.KNOW)
          }.width('100%')
        } else { this.Action({ label: '显示释义', action: () => { this.showAnswer(); }, primary: true }); }
        if (this.viewportHeight >= 480) {
          Text(this.isWide() ? '空格/Enter 释义 · 1/J 不认识 · 2/K 模糊 · 3/L 认识 · P/R 发音 · S 收藏 · Esc 返回' :
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
          if (this.undoAvailable) { this.Action({ label: `刚才的 ${this.lastJudgedWord} 点错了？撤销`, action: () => { this.undoJudgment(); }, primary: false }) }
          Text('✦').fontSize(60).fontColor($r('app.color.success')).margin({ top: 40 })
          Text('这一轮完成了，可以安心收起手机。').fontSize(27).fontWeight(FontWeight.Bold)
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
          if (this.recommendation.mode) {
            Text(this.recommendation.reason).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary'))
            this.Action({ label: `可选 · ${this.recommendation.title}`, action: () => { this.openRecommendedPractice(); }, primary: false })
          } else {
            this.Action({ label: '可选 · 读一篇短文', action: () => { this.pathStack.pushPathByName('Articles', ''); }, primary: false })
          }
        }.padding(26).width('100%').constraintSize({ maxWidth: 620 })
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor($r('app.color.background'))
  }

  @Builder
  WordListHeader() {
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
          if (!this.loadingWords) {
            Text(`${this.words.length} 个结果 · 右侧字母可快速跳转`).fontSize(13)
              .fontColor($r('app.color.text_secondary')).padding({ bottom: 12 }).width('100%')
          }
        }.width('100%')
  }

  @Builder
  WordListPage() {
    Row() {
      AlphabetWordList({ words: this.words, columns: this.wordListColumns(), loading: this.loadingWords,
        contentStartOffset: 66, contentEndOffset: bottomContentOffset(this.getUIContext()),
        header: () => { this.WordListHeader(); },
        onOpenWord: (id: number) => { this.openWord(id, this.listBookId); } })
        .constraintSize({ maxWidth: this.usesLargeWordList() ? PAGE_MAX_WIDTH : 1040 })
        .onAreaChange((_old: Area, area: Area) => { this.wordListWidth = Number(area.width); })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 16 }).backgroundColor($r('app.color.background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  WordMeaningCard() {
    Column({ space: 18 }) {
      Text(this.currentWord.meaning).fontSize(22).fontColor($r('app.color.text_primary')).lineHeight(32).width('100%')
      WordKnowledgeCard({ enrichment: this.enrichment, autoExpand: this.currentProgress.consecutiveFailures >= 2,
        onOpenWord: (id: number) => { this.openRelatedWord(id); } })
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
          Text(`${(record.responseMs / 1000).toFixed(1)} 秒`).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
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
          if (this.pronunciationMessage) {
            Text(this.pronunciationMessage).fontSize(13).lineHeight(22)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }
          WordExperiencePanel({ wordId: this.currentWord.id, onSource: (id: number, key: string) => { this.openReading(id, key); } })
          ReadAlongPanel({ word: this.currentWord.word, visible: this.detailVisible })
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
            this.PageHeading({ title: '在你喜欢的时间，轻轻提醒。', subtitle: `当天新学单词不足 ${this.snapshot.settings.dailyNewTarget} 个时，在你指定的时间提醒。提醒默认关闭。` })
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
          if (this.reminderStatusText) {
            Text(this.reminderStatusText).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
          }
          if (this.reminderFeedback) {
            Text(this.reminderFeedback).fontSize(14).lineHeight(24).fontColor($r('app.color.text_primary')).width('100%')
          }
          Text(`今天已新学 ${this.todayNewCount()} / ${this.snapshot.settings.dailyNewTarget} 个单词。\n达到目标后，今天不再提醒；明天继续。`)
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
  RestoreBackupPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 22 }) {
            this.PageHeading({ title: '在这台设备，接着学。', subtitle: '确认以下备份后，将替换本机的学习数据。' })
            Column({ space: 12 }) {
              Text('备份时间：' + this.backupDate).fontSize(15).fontColor($r('app.color.text_secondary'))
              Text(`${this.backupLearned} 个已学单词 · ${this.backupBooks} 本自定义词书`).fontSize(21)
                .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(`${this.backupRecords} 条回忆记录`).fontSize(15).fontColor($r('app.color.text_secondary'))
            }.width('100%').alignItems(HorizontalAlign.Start).padding(22)
              .backgroundColor($r('app.color.surface')).borderRadius(24)
            Text(`本机当前已学 ${this.snapshot.stats.totalLearned} 个单词。恢复会覆盖本机自定义词书、学习进度、收藏、生词本、统计和学习设置，不会合并。恢复前会自动保留本机安全副本；失败将还原。`)
              .fontSize(16).lineHeight(28).fontColor($r('app.color.text_primary')).width('100%')
            Text(this.pendingBackup && this.pendingBackup.version >= 4 ? '本备份还会替换文章、原句、阅读位置和逐词练习记录。' : '旧版备份保留本机文章、原句和阅读位置；逐词练习将清空。').fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary'))
            Text('提醒开关、提醒时间和通知授权保留本机设置，不从备份迁移。语音包需在这台设备上单独准备。')
              .fontSize(14).lineHeight(25).fontColor($r('app.color.text_secondary')).width('100%')
            if (this.restoreFeedback) {
              Text(this.restoreFeedback).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
            }
            this.Action({ label: '先导出本机备份', action: () => { this.exportData(); }, primary: false })
            this.Action({ label: '确认覆盖并恢复', action: () => { this.confirmRestore(); }, primary: true })
            this.Action({ label: '取消', action: () => { this.leaveRoute('RestoreBackup'); }, primary: false })
          }.padding(26).width('100%').constraintSize({ maxWidth: 680 })
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).width('100%').contentStartOffset(56).contentEndOffset(24)
        .align(this.isMedium() ? Alignment.Top : Alignment.Center)
    }.height('100%').width('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  PrivacyPage() {
    Column() {
      Scroll() {
        Row() {
          Column({ space: 24 }) {
          this.PageHeading({ title: '你的记忆，留在你的设备。', subtitle: '本版本无需账号，学习和英语朗读均可离线使用。' })
          Text('单词、学习进度和回忆记录保存在应用本机数据库；目标、外观等偏好保存在本机数据库。应用不包含广告、行为追踪或云端 AI 请求。')
            .fontSize(16).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
          Text('文件选择仅在你主动导入或导出时打开。提醒权限仅在主动开启提醒时申请。朗读通过华为 Core Speech Kit 使用设备上的离线音色；未安装时，由你主动下载语音包，下载需要联网。语音包准备完成后，英语单词和中文释义在本机离线合成。')
            .fontSize(16).lineHeight(29).fontColor($r('app.color.text_primary')).width('100%')
          Text('应用不会自动下载语音包，也不将学习内容上传到云端合成。语音资源由华为系统语音服务管理。')
            .fontSize(14).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
          Text('卸载应用可能删除本机记录。更换设备前，在「我的」导出学习数据，将 JSON 文件传到另一台设备，再选择「从备份恢复进度」。恢复前会展示备份信息，确认后覆盖该设备的学习数据；无需账号或云端同步。')
            .fontSize(14).lineHeight(26).fontColor($r('app.color.text_secondary')).width('100%')
          this.Action({ label: '导出我的学习数据', action: () => { this.exportData(); }, primary: false })
          this.Action({ label: '从备份恢复进度', action: () => { this.selectBackup(); }, primary: false })
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
      else if (name === 'PracticeLibrary') { this.PracticeLibraryPage(); }
      else if (name === 'Sentences') { SentenceCollectionPage({ onWord: (id: number) => { this.openWord(id); }, onSource: (id: number, key: string) => { this.openReading(id, key); } }) }
      else if (name === 'TodayPlan') { this.TodayPlanPage(); }
      else if (name === 'Summary') { this.SummaryPage(); }
      else if (name === 'WordList') { this.WordListPage(); }
      else if (name === 'WordDetail') { this.WordDetailPage(); }
      else if (name === 'Reminders') { this.RemindersPage(); }
      else if (name === 'Import') { this.ImportPage(); }
      else if (name === 'ImportPreview') { this.ImportPreviewPage(); }
      else if (name === 'RestoreBackup') { this.RestoreBackupPage(); }
      else if (name === 'EditWord') { this.EditWordPage(); }
      else if (name === 'Spelling' || name === 'Dictation') { SpellingChallengePage({ preferredIds: this.preferredIds, initialMode: name === 'Dictation' ? 'dictation' : 'spelling' }) }
      else if (name === 'Cloze') { ClozeChallengePage({ preferredIds: this.preferredIds, onLearn: () => { this.pathStack.pop(); this.beginStudy('today'); }, onLearnedWords: () => { this.returnToLearnedWords(); } }) }
      else if (name === 'Mistakes') { MistakeBookPage({ visible: this.mistakesVisible, onOpenWord: (id: number) => { this.openWord(id); }, onPractice: () => { this.beginStudy('mistake'); } }) }
      else if (name === 'Articles') { ArticleLibraryPage({ onOpenArticle: (id: number) => { this.openReading(id); } }) }
      else if (name === 'Article') { ArticlePage({ articleId: this.articleId, sourceKey: this.articleSourceKey }) }
      else if (name === 'AudioFlow') { AudioFlowPage({ words: this.activityWords, onBack: () => { this.pathStack.pop(); } }) }
      else if (name === 'Night' || name === 'Desk') {
        QuietReviewPage({ words: this.activityWords, mode: name === 'Night' ? 'night' : 'desk',
          onBack: () => { this.pathStack.pop(); } })
      }
      else if (name === 'Constellation') { ConstellationPage({ onOpenWord: (id: number) => { this.openWord(id); } }) }
      else if (name === 'SharedWords') {
        SharedWordsPage({ text: this.sharedText, onDone: () => { this.pathStack.pop(); this.refresh(); },
          onImport: (text: string) => { this.importText = text; this.importName = '分享收词'; this.pathStack.pushPathByName('Import', ''); } })
      }
      else if (name === 'MeaningChallenge') {
        MeaningChallengePage({ preferredIds: this.preferredIds,
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
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .onShown(() => {
        if (name === 'Summary' || name === 'PracticeLibrary') { this.refreshExperience(); }
        if (name === 'WordDetail') { this.detailVisible = true; }
        if (name === 'Mistakes') { this.mistakesVisible = true; }
        if (name === 'Reminders') { this.refreshReminderStatus(); }
        if (name === 'TodayPlan') { this.refresh().catch(() => {}); }
      })
      .onHidden(() => {
        if (['MeaningChallenge', 'Spelling', 'Dictation', 'Cloze', 'Article'].indexOf(name) >= 0) { this.refreshExperience(); }
        if (name === 'WordDetail') { this.detailVisible = false; }
        if (name === 'Mistakes') { this.mistakesVisible = false; }
        if (name === 'Learn' && this.pathStack.getAllPathName().slice(-1)[0] !== 'Summary') { this.invalidateUndo(); }
        if (name === 'Learn' || name === 'WordDetail') { this.pronunciation.cancel(); }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onBackPressed(() => {
        if (this.restoring) { return true; }
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
    if (name === 'TodayPlan') { return '今日学习计划'; }
    if (name === 'WordList') { return this.listTitle; }
    if (name === 'WordDetail') { return '单词详情'; }
    if (name === 'Reminders') { return '学习提醒'; }
    if (name === 'Import') { return '导入自定义词书'; }
    if (name === 'ImportPreview') { return '确认导入内容'; }
    if (name === 'RestoreBackup') { return '恢复学习进度'; }
    if (name === 'EditWord') { return this.editIndex >= 0 ? '补充 / 修改导入单词' : '编辑自定义词条'; }
    if (name === 'MeaningChallenge') { return '中文释义挑战'; }
    if (name === 'LearnedWords') { return '已学单词'; }
    if (name === 'Spelling') { return '拼写速记'; }
    if (name === 'Dictation') { return '听音写词'; }
    if (name === 'Cloze') { return '语境填空'; }
    if (name === 'Mistakes') { return '错题本'; }
    if (name === 'PracticeLibrary') { return '专项练习'; }
    if (name === 'Sentences') { return '我的原句'; }
    if (name === 'Articles') { return '阅读'; }
    if (name === 'Article') { return '阅读文章'; }
    if (name === 'AudioFlow') { return '听词磨耳朵'; }
    if (name === 'Night') { return '晚间复盘'; }
    if (name === 'Desk') { return '书桌伴读'; }
    if (name === 'Constellation') { return '词汇星图'; }
    if (name === 'SharedWords') { return '收词预览'; }
    return '数据与隐私';
  }

  @Builder
  RouteTitleBar(name: string) {
    this.BackHeader({ title: this.routeTitle(name), action: () => { this.leaveRoute(name); } })
  }

  private leaveRoute(name: string): void {
    if (this.restoring) { return; }
    if (name === 'RestoreBackup') { this.pendingBackup = undefined; }
    this.pathStack.pop();
    if (name === 'WordDetail') {
      if (this.studyWordBeforeDetail && this.studyProgressBeforeDetail && this.studyEnrichmentBeforeDetail) {
        this.currentWord = this.studyWordBeforeDetail;
        this.currentProgress = this.studyProgressBeforeDetail;
        this.enrichment = this.studyEnrichmentBeforeDetail;
        this.studyWordBeforeDetail = undefined;
        this.studyProgressBeforeDetail = undefined;
        this.studyEnrichmentBeforeDetail = undefined;
        const id = this.currentWord.id;
        this.service.getProgress(id).then((progress: WordProgress) => {
          if (this.currentWord.id === id) { this.currentProgress = progress; }
        }).catch(() => {});
        if (this.session.mode === 'quick') { this.startQuickTimer(); }
      } else { this.search(); }
    }
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
        .constraintSize({ maxWidth: primaryPageMaxWidth(index) })
    }.width('100%').height('100%').contentStartOffset(56)
      .contentEndOffset(bottomContentOffset(this.getUIContext()))
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
    }.width('100%').height('100%').background($r('app.color.background'))
      .onAreaChange((_old: Area, area: Area) => {
        this.viewportWidth = Number(area.width);
        this.viewportHeight = Number(area.height);
      })
  }
}
