import { common } from '@kit.AbilityKit';
import { uiMaterial, window } from '@kit.ArkUI';

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
  private readonly controller: TabsController = new TabsController();
  private readonly nativeMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({});

  aboutToAppear(): void {
    try {
      this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    } catch {
      this.immersiveSupported = false;
    }
  }

  /**
   * The Tabs ignores the layout safe area so the floating bar keeps its correct anchor and the
   * title bar blur can cover the status bar; the page content is kept inside the safe area by
   * padding with the measured avoid-area insets.
   */
  private topInsetVp(): number {
    return this.avoidInsetVp(window.AvoidAreaType.TYPE_SYSTEM, true);
  }

  private navInsetVp(): number {
    return this.avoidInsetVp(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR, false);
  }

  private avoidInsetVp(type: window.AvoidAreaType, top: boolean): number {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const area = context.windowStage.getMainWindowSync().getWindowAvoidArea(type);
      return this.getUIContext().px2vp(top ? area.topRect.height : area.bottomRect.height);
    } catch {
      return 0;
    }
  }

  @Monitor('selectedIndex')
  syncSelectedIndex(): void {
    this.controller.changeIndex(this.boundedIndex());
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

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: this.boundedIndex(), controller: this.controller }) {
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
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .expandSafeArea([SafeAreaType.SYSTEM])
      .padding({ top: this.topInsetVp(), bottom: this.navInsetVp() })
      .barHeight(56).barOverlap(true).vertical(false)
      .barMode(BarMode.Fixed).scrollable(false)
      .barFloatingStyle({
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
