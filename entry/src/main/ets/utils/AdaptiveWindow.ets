import { deviceInfo } from '@kit.BasicServicesKit';
import { AppStorageV2, KeyboardAvoidMode, window } from '@kit.ArkUI';

/** Insets belong to the current ability window, never to the physical display. */
@ObservedV2
export class AdaptiveWindowState {
  @Trace topInset: number = 0;
  @Trace bottomInset: number = 0;
  @Trace keepSystemTop: boolean = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
  @Trace isFloating: boolean = false;
}

export function adaptiveWindowState(): AdaptiveWindowState {
  return AppStorageV2.connect(AdaptiveWindowState, () => new AdaptiveWindowState())!;
}

export class AdaptiveWindowController {
  private mainWindow: window.Window;
  private state: AdaptiveWindowState = adaptiveWindowState();
  private listening: boolean = false;
  private windowStatusListening: boolean = false;
  private readonly avoidListener: (options: window.AvoidAreaOptions) => void =
    (_options: window.AvoidAreaOptions): void => { this.refreshInsets(); };
  private readonly sizeListener: (size: window.Size) => void =
    (_size: window.Size): void => { this.refreshInsets(); };
  private readonly windowStatusListener: (status: window.WindowStatusType) => void =
    (status: window.WindowStatusType): void => {
      this.state.isFloating = status === window.WindowStatusType.FLOATING;
    };

  constructor(mainWindow: window.Window) {
    this.mainWindow = mainWindow;
  }

  start(): void {
    // Keep the native desktop title bar and its move/minimize/maximize/close controls.
    this.mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.refreshInsets();
    this.mainWindow.on('avoidAreaChange', this.avoidListener);
    this.mainWindow.on('windowSizeChange', this.sizeListener);
    this.listening = true;
    if (deviceInfo.deviceType === 'tablet') {
      try {
        this.windowStatusListener(this.mainWindow.getWindowStatus());
      } catch {}
      try {
        this.mainWindow.on('windowStatusDidChange', this.windowStatusListener);
        this.windowStatusListening = true;
      } catch {}
    }
  }

  private refreshInsets(): void {
    try {
      const uiContext = this.mainWindow.getUIContext();
      const system = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const navigation = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.state.topInset = uiContext.px2vp(Math.max(system.topRect.height, cutout.topRect.height));
      this.state.bottomInset = uiContext.px2vp(Math.max(system.bottomRect.height,
        cutout.bottomRect.height, navigation.bottomRect.height));
    } catch {}
  }

  stop(): void {
    if (!this.listening) { return; }
    this.mainWindow.off('avoidAreaChange', this.avoidListener);
    this.mainWindow.off('windowSizeChange', this.sizeListener);
    if (this.windowStatusListening) {
      try {
        this.mainWindow.off('windowStatusDidChange', this.windowStatusListener);
      } catch {}
      this.windowStatusListening = false;
    }
    this.listening = false;
  }
}
