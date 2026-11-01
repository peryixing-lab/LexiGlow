import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { AudioService } from '../service/AudioService';
import { AudioFlowService } from '../service/AudioFlowService';
import { SharedWordService } from '../service/SharedWordService';
import { LiveStudyService } from '../service/LiveStudyService';
import { AdaptiveWindowController } from '../utils/AdaptiveWindow';
import { resolveLaunchRoute } from '../utils/LaunchRouteUtils';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;
  private windowController: AdaptiveWindowController | undefined = undefined;
  private foldListening: boolean = false;
  private readonly foldListener = (status: display.FoldStatus): void => {
    const half = status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
      status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_HALF_FOLDED ||
      status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_EXPANDED;
    const previous = AppStorage.get<boolean>('lexiglowHalfFolded') || false;
    AppStorage.setOrCreate('lexiglowHalfFolded', half);
    if (half && !previous) { this.context.eventHub.emit('halfFolded'); }
  };
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AudioService.getInstance().initialize(this.context);
    this.captureRoute(want, false);
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureRoute(want, true);
  }

  private captureRoute(want: Want, notify: boolean): void {
    SharedWordService.captureWant(want).then((captured: boolean) => {
      if (!captured) { return; }
      AppStorage.setOrCreate('launchRoute', 'shared');
      this.context.eventHub.emit('openRoute', 'shared', 0);
    }).catch(() => {});
    const parameterRoute = typeof want.parameters?.route === 'string' ? want.parameters.route as string : '';
    const route = resolveLaunchRoute(typeof want.uri === 'string' ? want.uri : '', parameterRoute);
    const wordId = route === 'todayPlan' ? 0 : Number(want.parameters?.wordId || 0);
    if (!route || route === 'shared') { return; }
    AppStorage.setOrCreate('launchRoute', route);
    AppStorage.setOrCreate('launchWordId', wordId);
    if (notify) { this.context.eventHub.emit('openRoute', route, wordId); }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) { hilog.error(0x0000, 'Ciying', 'Page load failed, code %{public}d', err.code); }
      else {
        this.mainWindow = windowStage.getMainWindowSync();
        this.syncWindowBackground();
        this.windowController = new AdaptiveWindowController(this.mainWindow);
        this.windowController.start();
        try {
          if (display.isFoldable()) {
            display.on('foldStatusChange', this.foldListener);
            this.foldListening = true;
            this.foldListener(display.getFoldStatus());
          }
        } catch {}
      }
    });
  }

  onConfigurationUpdate(_configuration: Configuration): void {
    this.syncWindowBackground();
  }

  private syncWindowBackground(): void {
    if (!this.mainWindow) { return; }
    try {
      // System bars and exposed safe-area pixels use the same themed backing as the page.
      const color = this.context.resourceManager.getColorByNameSync('background');
      this.mainWindow.setWindowBackgroundColor(`#${(color >>> 0).toString(16).padStart(8, '0')}`);
    } catch {
      hilog.warn(0x0000, 'Ciying', 'Window background update failed');
    }
  }

  onWindowStageDestroy(): void {
    this.windowController?.stop();
    this.windowController = undefined;
    this.mainWindow = undefined;
    if (this.foldListening) { display.off('foldStatusChange', this.foldListener); this.foldListening = false; }
  }

  onForeground(): void { this.context.eventHub.emit('appVisibility', true); }
  onBackground(): void {
    this.context.eventHub.emit('appVisibility', false);
    AudioService.getInstance().stopForeground();
  }
  onDestroy(): void {
    this.windowController?.stop();
    this.mainWindow = undefined;
    if (this.foldListening) { display.off('foldStatusChange', this.foldListener); this.foldListening = false; }
    LiveStudyService.getInstance().stop();
    AudioFlowService.getInstance().release();
    AudioService.getInstance().destroy();
  }
}
