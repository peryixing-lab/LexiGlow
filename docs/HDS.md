# LexiGlow 原生沉浸光感

本方案依据用户指定的华为[沉浸光感示例](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sample)，使用标准 ArkUI `Tabs`、`Navigation`、`NavDestination` 和 `@kit.ArkUI` 的 `uiMaterial`。当前工程运行依赖 HarmonyOS API 26；接口核对本机 DevEco Studio API 26 Release（`26.0.0.105`）的 `tabs.d.ts`、`navigation.d.ts`、`nav_destination.d.ts`、`common.d.ts` 和 `@ohos.arkui.uiMaterial.d.ts`。

## 系统材质与能力

`module.json5` 的模块根级元数据启用系统材质：

```json
{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }
```

这项配置让系统支持的原生组件按启用状态使用材质。悬浮底栏显式设置 `new uiMaterial.ImmersiveMaterial({})`，沿用 SDK 默认选项；圆角、边界、阴影和材质效果由原生组件管理，没有额外绘制的胶囊外壳。

组件出现时调用一次 `uiMaterial.isImmersiveMaterialSupported()`。支持时为浮栏传入 `ImmersiveMaterial`；不支持或探测失败时传入 `undefined`，保留标准 `Tabs` 的原生浮栏。`uiMaterial.getGlobalMaterialLevel()` 可查询设备定义的算力等级，应用不能修改该等级，也没有 `materialLevel` 设置。支持材质的设备仍由系统按高、中、低算力映射滤镜、背景、边框和阴影，不在应用中维护多套强度实现。

## 标准 Tabs 悬浮底栏

`ImmersiveDock.ets` 作为完整页面承载四个 `TabContent`，使用 `TabsController` 和标准 `BottomTabBarStyle`。`selectedIndex`、`onSelect` 与四个 `@BuilderParam` 保持接入契约；SVG 图标和选中/未选中文字颜色引用应用主题资源。

核心配置：

```ts
Tabs({ barPosition: BarPosition.End, index: this.boundedIndex(), controller: this.controller }) {
  // 首页、词库、统计、我的四个 TabContent
}
.barHeight(56)
.barMode(BarMode.Fixed)
.barOverlap(true)
.scrollable(false)
.barFloatingStyle({
  barBottomMargin: 8,
  systemMaterial: this.immersiveSupported ? this.nativeMaterial : undefined,
  maskColor: Color.Transparent,
  maskHeight: 0
})
```

浮栏高 56 vp，底部间距 8 vp。透明色与零高度关闭浮栏下方的渐变颜色遮罩，不关闭栏本体材质。`scrollable(false)` 禁止横向手势切换页签，避免正文滚动和学习交互产生冲突；点击四个原生页签仍正常切换。

SDK 参数为 `TabsOptions` 的 `barPosition/index/controller`，以及 `TabsAttribute.barFloatingStyle(style: Optional<FloatingTabBarStyle>)`。`FloatingTabBarStyle.systemMaterial` 类型是 `uiMaterial.ImmersiveMaterial`，`maskColor` 和 `maskHeight` 是同一配置对象的直接字段。

## 底部绘制与顶部沉浸

已在模拟器实际解决滚动正文在 Dock 上方被硬截断的问题，最终结构与官方《如何设置 Tabs 沉浸式》方案三一致，兼顾浮栏锚定与顶部沉浸：

1. `ImmersiveDock` 采用两层结构。外层 `Stack` 只负责绘制延伸（`.expandSafeArea([SafeAreaType.SYSTEM])`）；内层 `Tabs` 使用 `.height(LayoutPolicy.matchParent)` + `.ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])` + `.expandSafeArea([SafeAreaType.SYSTEM])`，让 `Tabs` 布局盒覆盖整个窗口，顶部沉浸光感标题栏的模糊可以一直绘制到状态栏区域；再用 `.padding({ top: 状态栏高度, bottom: 导航条高度 })`（运行时从 `window.getWindowAvoidArea` 读取并 `px2vp` 换算）把页签内容放回安全区内，标题文字与正文位置不变。
2. 悬浮浮栏锚定 `Tabs` 内容盒底边，`barBottomMargin: 8` 生效为「屏幕底部 − 手势避让区 − 8 vp」（1320×2848 设备实测浮栏 y=2727，手势区高 94 px）。注意：单独给 `Tabs` 加 `expandSafeArea(TOP)` 而不加 `ignoreLayoutSafeArea` 时，浮栏锚点会额外上移一个状态栏高度（实测多减 131 px / 38.8 vp），底栏明显偏高，必须避免这种组合。
3. 四个 `TabContent` 使用 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`。
4. 首页、词库、统计、我的四页 `Navigation` 与 `Scroll` 同样扩展系统顶部与底部绘制区；标题栏 builder 根节点继续扩展，负责状态栏沉浸与渐进模糊。
5. 各页滚动正文预留浮栏高度、间距和阅读余量，最后一个操作不会被浮栏盖住；安全区绘制延伸与可点击内容留白分别处理。

顶部按官方"沉浸光感典型场景"接入状态栏沉浸：`TabContent` 位于 `Tabs` 内部的 `Swiper` 中，扩展链覆盖 `ImmersiveDock` 外层 `Stack` → `Tabs` → `TabContent` → 内容根 `Navigation` 全部节点，缺任一层时顶部扩展失效，状态栏只剩外层纯色背景。标题栏模糊要覆盖状态栏，还需为标题栏 builder 根节点（`PrimaryTitleBar`、`BackHeader` 的根 `Row`）设置 `.expandSafeArea([SafeAreaType.SYSTEM])`；`expandSafeArea` 只扩展绘制区域，标题文字与按钮仍布局在安全区内，位置不变。`updateTitleCollapse` 依赖的 `tab-title-*` 矩形下边缘不受向上扩展影响。

## 原生标题栏方案

按照同一官方教程，标题栏由 `Navigation` / `NavDestination` 提供，采用 `BarStyle.STACK` 让原生栏叠放在滚动内容上。标题选项的 `scrollEffectOptions` 设置 `scrollEffectType: ScrollEffectType.GRADUAL_BLUR`，由原生滚动关联驱动标题栏渐进模糊。

滚动正文使用 `contentStartOffset` 为标题栏预留起始位置，数值与对应栏高和既有安全区布局一致。起始偏移用于内容排布，不能替代状态栏或挖孔避让；顶部沉浸只扩展绘制区域到状态栏下方，标题文字、正文首行仍布局在安全区内，不与挖孔重叠。

四个主页面各自使用原生 `Navigation` 标题栏。正文大标题滚出顶部后，栏内 `LexiGlow` 收束为当前页面名称；标题栏保持 56 vp，右侧 40 vp 圆形操作按钮使用 `ULTRA_THIN` 系统材质、交互变形和主题光效。导入、词条详情、编辑等子页面使用 `NavDestination` 标题栏；学习和结算继续采用原有操作栏。返回标题限制为一行，长词书名称自动省略。

深色主题采用中性炭黑背景、`#FFD45C` 主金黄色与 `#665000` 暖黄色卡片。黄色区域的辅助字使用专用 `#D0CBC1`，与卡片对比约 4.79:1；主文字对比约 6.86:1。普通卡片继续使用独立灰色辅助字。

## 验证边界

标准 `Tabs`、系统材质与新标题栏已通过 API 26 Release 构建，并安装到 HarmonyOS 7 / API 26 模拟器。词库滚动时可观察到标题区域原生渐进模糊与紧凑标题；浮栏下方正文继续延伸到系统手势区，消除旧版纯色硬截断。导入按钮可进入子页面，原生材质返回按钮与正文起始偏移正常。截图保存在 `docs/screenshots/`，以本次标准 `uiMaterial` 实现更新后的图片为准。

大字体、横竖屏、分屏/折叠、系统光感偏好、低算力/热降级和复杂背景下的帧率仍需目标真机验证。测试不能从 API 参数存在推断设备实际提供相同的材质效果。

官方参考：[沉浸光感示例](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sample)、[Navigation](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navigation)、[NavDestination](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navdestination)、[Tabs](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-tabs)。精确 API 26 参数以项目当前安装的官方 SDK 类型声明为准。
