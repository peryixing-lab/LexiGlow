import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AudioService } from '../service/AudioService';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureRoute(want, false);
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureRoute(want, true);
  }

  private captureRoute(want: Want, notify: boolean): void {
    const route = typeof want.parameters?.route === 'string' ? want.parameters.route as string : '';
    const wordId = Number(want.parameters?.wordId || 0);
    if (!route) { return; }
    AppStorage.setOrCreate('launchRoute', route);
    AppStorage.setOrCreate('launchWordId', wordId);
    if (notify) { this.context.eventHub.emit('openRoute', route, wordId); }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) { hilog.error(0x0000, 'Ciying', 'Page load failed, code %{public}d', err.code); }
    });
  }

  onBackground(): void { AudioService.getInstance().stop(); }
  onDestroy(): void { AudioService.getInstance().release(); }
}
