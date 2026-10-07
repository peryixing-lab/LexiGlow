import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';

/** Keep the final item reachable while letting the scroll viewport draw into the gesture area. */
export function bottomContentOffset(uiContext: UIContext): number {
  try {
    const context = uiContext.getHostContext() as common.UIAbilityContext;
    const area = context.windowStage.getMainWindowSync()
      .getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    return 24 + uiContext.px2vp(area.bottomRect.height);
  } catch {
    return 24;
  }
}
