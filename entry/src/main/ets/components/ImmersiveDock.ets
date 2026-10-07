import { accessibility } from '@kit.AccessibilityKit';
import { curves, uiMaterial } from '@kit.ArkUI';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';

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
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  private readonly nativeMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({});
  private readonly tabSpring: curves.ICurve = curves.springMotion(0.30, 0.82);
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
    return this.availableWidth >= 840;
  }

  private boundedIndex(): number {
    return Math.max(0, Math.min(3, Math.floor(this.selectedIndex)));
  }

  private tabStyle(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(icon, label)
      .layoutMode(this.useSidebar() ? LayoutMode.HORIZONTAL : LayoutMode.VERTICAL)
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

  build() {
    Stack() {
      Tabs({ barPosition: this.useSidebar() ? BarPosition.Start : BarPosition.End, index: this.boundedIndex() }) {
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
      .width('100%').height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], this.windowState.keepSystemTop ?
        [LayoutSafeAreaEdge.BOTTOM] : [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .expandSafeArea([SafeAreaType.SYSTEM])
      .padding({ top: this.windowState.keepSystemTop ? 0 : this.windowState.topInset, bottom: this.windowState.bottomInset })
      .barHeight(this.useSidebar() ? '100%' : 56).barWidth(this.useSidebar() ? 168 : '100%')
      .barOverlap(!this.useSidebar()).vertical(this.useSidebar())
      .barMode(this.useSidebar() ? BarMode.Scrollable : BarMode.Fixed).scrollable(false)
      .barBackgroundColor(this.useSidebar() ? $r('app.color.surface') : Color.Transparent)
      .animationMode(this.reduceMotion ? AnimationMode.NO_ANIMATION : AnimationMode.CONTENT_FIRST_WITH_JUMP)
      .animationDuration(this.reduceMotion ? 0 : 260)
      .animationCurve(this.reduceMotion ? Curve.Linear : this.tabSpring)
      .barFloatingStyle(this.useSidebar() ? undefined : {
        barBottomMargin: 8,
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
