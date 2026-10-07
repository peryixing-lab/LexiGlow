import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** Dedicated HAP: its page and data remain local to the smart watch. */
export default class WatchAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'LexiGlowWatch', 'Unable to load watch page: %{public}d', error.code);
      }
    });
  }
}
