import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { CommonModifier, curves, uiMaterial } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';
import { primaryNavigationRailWidth, usesTopNavigation } from '../utils/ResponsiveLayout';

/** Standard ArkUI floating tabs; the system maps the material to device capability. */
@ComponentV2
export struct ImmersiveDock {
  @Param selectedIndex: number = 0;
  @Event onSelect: (index: number) => void = () => {};
  @BuilderParam homeContent: () => void = this.emptyContent;
  @BuilderParam booksContent: () => void = this.emptyContent;
  @BuilderParam statisticsContent: () => void = this.emptyContent;
  @BuilderParam profileContent: () => void = this.emptyContent;
  @Local immersiveSupported: boolean = false;
  @Local reduceMotion: boolean = false;
  @Param availableWidth: number = 0;
  @Param tabsController: TabsController = new TabsController();
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  private readonly nativeMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    interactive: true,
    lightEffect: { color: $r('app.color.glow_deep') }
  });
  private readonly dockMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    interactive: true,
    lightEffect: { color: $r('app.color.glow_deep') }
  });
  private readonly tabSpring: curves.ICurve = curves.springMotion(0.30, 0.82);
  private readonly loweredPhoneBar: CommonModifier = new CommonModifier().offset({ y: 12 });
  private readonly loweredTabletBar: CommonModifier = new CommonModifier().offset({ y: 24 });
  private readonly defaultBar: CommonModifier = new CommonModifier().offset({ y: 0 });
  private animationReduceListening: boolean = false;
  private readonly animationReduceListener: (enabled: boolean) => void = (enabled: boolean): void => {
    this.reduceMotion = enabled;
  };

  aboutToAppear(): void {
    try {
      this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    } catch {
      this.immersiveSupported = false;
    }
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
    } catch {
      this.reduceMotion = false;
    }
    try {
      accessibility.onAnimationReduceStateChange(this.animationReduceListener);
      this.animationReduceListening = true;
    } catch {
      this.animationReduceListening = false;
    }
  }

  aboutToDisappear(): void {
    if (this.animationReduceListening) {
      try {
        accessibility.offAnimationReduceStateChange(this.animationReduceListener);
      } catch {}
      this.animationReduceListening = false;
    }
  }

  private useSidebar(): boolean {
    return primaryNavigationRailWidth(this.availableWidth, deviceInfo.deviceType) > 0;
  }

  private hideBottomDock(): boolean {
    return this.useSidebar() || usesTopNavigation(this.availableWidth, deviceInfo.deviceType);
  }

  private bottomDockMargin(): number {
    // Keep fullscreen tablets and 2in1 windows at their existing position.
    return deviceInfo.deviceType === 'phone' ||
      (deviceInfo.deviceType === 'tablet' && this.windowState.isFloating) ? 4 : 8;
  }

  private dockBarModifier(): CommonModifier {
    // Move only the bottom bar; leave page measurements and system insets intact.
    if (this.hideBottomDock()) { return this.defaultBar; }
    if (deviceInfo.deviceType === 'phone') { return this.loweredPhoneBar; }
    if (deviceInfo.deviceType === 'tablet' && this.windowState.isFloating) { return this.loweredTabletBar; }
    return this.defaultBar;
  }

  private boundedIndex(): number {
    return Math.max(0, Math.min(3, Math.floor(this.selectedIndex)));
  }

  private tabStyle(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(icon, label)
      .layoutMode(LayoutMode.VERTICAL)
      .iconStyle({
        selectedColor: $r('app.color.brand_ink'),
        unselectedColor: $r('app.color.text_secondary')
      })
      .labelStyle({
        selectedColor: $r('app.color.brand_ink'),
        unselectedColor: $r('app.color.text_secondary')
      });
  }

  @Builder
  private emptyContent() {
    Column().width('100%').height('100%')
  }

  @Builder
  private dockItem(icon: Resource, label: string, index: number) {
    Column({ space: 3 }) {
      Image(icon).width(22).height(22)
        .fillColor(index === this.boundedIndex() ? $r('app.color.brand_ink') : $r('app.color.text_secondary'))
      Text(label)
        .fontSize(10)
        .fontWeight(index === this.boundedIndex() ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.boundedIndex() ? $r('app.color.brand_ink') : $r('app.color.text_secondary'))
    }
    .width(60)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(18)
    .backgroundColor(index === this.boundedIndex() ? $r('app.color.soft_surface') : Color.Transparent)
    .focusable(true)
    .hoverEffect(HoverEffect.Highlight)
    .onKeyEvent((event: KeyEvent): boolean => {
      if (event.type === KeyType.Down && (event.keyCode === KeyCode.KEYCODE_ENTER ||
        event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
        this.tabsController.changeIndex(index);
        return true;
      }
      return false;
    })
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
  }

  @Builder
  private sideDock() {
    Column() {
      Column({ space: 6 }) {
        this.dockItem($r('app.media.dock_home'), '首页', 0)
        this.dockItem($r('app.media.dock_books'), '词库', 1)
        this.dockItem($r('app.media.dock_statistics'), '统计', 2)
        this.dockItem($r('app.media.dock_profile'), '我的', 3)
      }
      .width(76)
      .padding({ top: 10, bottom: 10 })
      .borderRadius(26)
      .systemMaterial(this.immersiveSupported ? this.dockMaterial : undefined)
      .backgroundColor(this.immersiveSupported ? Color.Transparent : $r('app.color.surface'))
      .border(this.immersiveSupported ? { width: 0 } : { width: 1, color: $r('app.color.divider') })
    }
    .width(104)
    .height('100%')
    .padding({
      left: 12,
      top: (this.windowState.keepSystemTop ? 0 : this.windowState.topInset) + 12,
      bottom: this.windowState.bottomInset + 12
    })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Row() {
      if (this.useSidebar()) {
        this.sideDock()
      }
      Tabs({ barPosition: BarPosition.End, index: this.boundedIndex(), controller: this.tabsController,
        barModifier: this.dockBarModifier() }) {
        TabContent() {
          this.homeContent()
        }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .tabBar(this.tabStyle($r('app.media.dock_home'), '首页'))
        TabContent() {
          this.booksContent()
        }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .tabBar(this.tabStyle($r('app.media.dock_books'), '词库'))
        TabContent() {
          this.statisticsContent()
        }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .tabBar(this.tabStyle($r('app.media.dock_statistics'), '统计'))
        TabContent() {
          this.profileContent()
        }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .tabBar(this.tabStyle($r('app.media.dock_profile'), '我的'))
      }
      // Phone immersion needs matchParent; keep the tablet and desktop cross-axis sizing.
      .height(this.windowState.keepSystemTop ? '100%' : LayoutPolicy.matchParent)
      .layoutWeight(1)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], this.windowState.keepSystemTop ?
        [LayoutSafeAreaEdge.BOTTOM] : [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .expandSafeArea([SafeAreaType.SYSTEM])
      .padding({ top: this.windowState.keepSystemTop ? 0 : this.windowState.topInset, bottom: this.windowState.bottomInset })
      // Leave floating width to the native capsule; 100% makes it touch both screen edges.
      .barHeight(this.hideBottomDock() ? 0 : 56)
      .barOverlap(!this.hideBottomDock()).vertical(false)
      .barMode(BarMode.Fixed).scrollable(false)
      .animationMode(this.reduceMotion ? AnimationMode.NO_ANIMATION : AnimationMode.CONTENT_FIRST_WITH_JUMP)
      .animationDuration(this.reduceMotion ? 0 : 260)
      .animationCurve(this.reduceMotion ? Curve.Linear : this.tabSpring)
      .barFloatingStyle(this.hideBottomDock() ? undefined : {
        barBottomMargin: this.bottomDockMargin(),
        systemMaterial: this.immersiveSupported ? this.nativeMaterial : undefined,
        maskColor: Color.Transparent,
        maskHeight: 0
      })
      .onChange((index: number) => {
        if (index !== this.boundedIndex()) {
          this.onSelect(index);
        }
      })
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM])
  }
}
