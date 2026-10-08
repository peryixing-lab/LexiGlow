# 词萤实现与验收说明

本应用按用户提供的产品方案实现本机优先的第一版，采用当前工程和已安装的 Huawei Release SDK。方案中的代码作为结构参考，实际签名通过官方文档和本机 SDK `.d.ts` 核对，并以 Hvigor 的资源检查及 ArkTS 编译结果验证。

## 方案对应

| 方案部分 | 实现 |
| --- | --- |
| 品牌与视觉 | 词萤名称、原创 SVG 卡片/萤光点图标、暖象牙白页面背景、萤光黄、资源化深浅色 |
| 首次使用 | 4 步引导，目标词书、基础、每日量、默认关闭提醒，首次 3 词体验 |
| 首页 | 今日完成量/预计时长、到期词优先入口、速学、每日词、忙碌预算、考试倒计时 |
| 学习和复习 | 揭晓答案前回忆、三档判断、统一进度、按时间调度、每词原子保存、重启续学 |
| 中文释义挑战 | 从已学词随机抽取最多 10 词，输入任意一个完整中文义项通过，答后揭晓、独立计分与再来一轮 |
| 已学单词 | 按首次学习日期倒序分组，近期日期切换、系统日期选择器、当天搜索与分页，缺失历史单列 |
| 词库 | 五类词书、本地搜索、跨书共享进度、收藏、生词本、DOCX/TXT/CSV/JSON 导入、预览、改名与词条编辑、单独导出 |
| 统计 | 真实数据库汇总、当前掌握数、首次掌握周增量、复习成功率、记忆强度、28 天日历 |
| 鸿蒙能力 | Stage UIAbility、Navigation/NavDestination/NavPathStack、RDB/Preferences、两种 FormExtensionAbility 卡片、标准 Tabs 与 API 26 沉浸光感 |
| 设置与数据 | 目标、预算、考试冲刺、日期、自动发音、主题、主动提醒、JSON 导出、隐私说明 |
| 后续版本 | FSRS、AI、账号与跨设备同步尚未实现；导出数据恢复尚未实现 |

页面通过 LearningService 访问学习数据，页面中没有 SQL。复习调度是可独立测试的纯函数。收藏与生词标志可以在尚未学习时保存，但只有 `review_count > 0` 才算已学或到期；因此收藏不会意外减少新词或制造复习任务。

自定义释义、音标和例句保存在词书成员的覆盖字段中；编辑同名词只改变该自定义词书的内容，内置词典和共享学习进度保持一致。词头变更关联到相应新词 ID，旧词学习记录保留；若同书已存在目标词头，事务拒绝修改，避免静默合并覆盖已有内容。导入只有词头的 DOCX/TXT 时先匹配本地词典，未匹配的词需在预览里补充释义。

每次判断把 progress、review_record、daily_plan、daily_summary 和 study_session 游标放在同一官方 Transaction 对象。批量词库导入的查询和写入也使用这个对象，避免旧 RdbStore 读连接看不到未提交词条 ID。发生写入失败时一起回滚，界面留在当前词以便重试。首次达到掌握强度写入独立记录，避免同一个词反复跌落/回升后虚增每周掌握数。学习进度按单词 ID 共享，词书只维护多对多成员关系。

复习判断严格采用产品方案第 13 节 V1 代码：基础间隔为 10 分钟、1/3/7/14/30/60 天。不认识将等级减一（最低 0）、强度减 20（最低 0），新等级 0 时下次 10 分钟，否则 12 小时；模糊保留等级、强度加 5（最高 100），当前基础间隔乘 0.6 后四舍五入；认识升一级、强度加 12（最高 100），采用新等级基础间隔。状态按第 8.2 节映射：0–24 陌生、25–49 模糊、50–74 熟悉、75–100 掌握，判断按钮“认识”与累计状态“熟悉”分开表达。到期任务按逾期优先排序；冲刺模式减少新词，并优先错误较多、强度低的到期词。日常目标和临时预算分离，跨本地日期重新生成计划；积压超过 60 时减少新词，达到 100 时暂停新词，复习队列最多 100，避免一次压入几百词。

首页主进度为（新词完成量 + 复习完成量）/（新词目标 + 复习目标），同时分列新词和复习，符合方案“今日计划”和“今日学习”的结构。两类目标分别完成后才进入“再学一点”，避免超额新词替代剩余复习。`daily_summary.total_count` 记录当日判断任务总量（`new_count + review_count`），已学词数独立按有学习记录的单词去重计算；复习日仍计入学习日历和连续学习。学习总结也分别显示新词数和复习次数。

中文释义挑战通过独立 `ChallengeService` 管理题目与计分，不写每日计划、复习记录或记忆强度。`MeaningMatcher` 拆分词典义项并作完整匹配，兼容词性、编号、标点、括号说明和形容词末尾“的”的自然省略；仅输入义项片段或包含答案的无关长句不会通过。候选要求 `review_count > 0`，轮内不重复。

已学列表以第一次新词判断记录的本地日期分组，之后复习不会移动日期，跨词书共享词只出现一次。列表优先展示当前词书覆盖释义，每页 50 词，可用系统日期选择器跳转、近期日期快速切换及英文前缀/中文释义搜索；历史日期缺失时单列“日期未记录”，不会用最后复习时间代替。

初始化执行 `learning_semantics_version=2` 原子迁移，覆盖旧版保底算法已迁移的数据：按判断提交顺序回放完整且连续、从初始强度 0 开始的历史，修正当前强度与记录链，并重新确定首次达到 75 的掌握日期；未曾达到 75 的错误掌握记录移除。仅修改强度和统计口径，保留复习时间、等级、判断计数、收藏、生词标记和会话。无法从初始状态安全还原的历史原样保留。每日总数恢复为新词与复习之和，版本标记与所有修正一起提交；失败回滚，下次启动重试。

视觉实现采用用户最新指定的 API 26 官方教程：标准 Tabs 配合 BottomTabBarStyle 与 `barFloatingStyle`，通过 `@kit.ArkUI` 的 `new uiMaterial.ImmersiveMaterial({})` 配置原生悬浮栏材质。底栏 `barBottomMargin` 为 8vp，`maskColor` 为透明、`maskHeight` 为 0。Tabs 使用底部限定的 `ignoreLayoutSafeArea` 与 `LayoutPolicy.matchParent`，TabContent、各页 Navigation 和 Scroll 延伸底部安全区，使背景与滚动内容铺到手势区，同时保留顶部状态栏和挖孔避让。

窄窗口四个主页标题与子页标题分别由原生 Navigation/NavDestination 管理，采用 `BarStyle.STACK` 和 `ScrollEffectType.GRADUAL_BLUR`；滚动内容用 `contentStartOffset(56)` 避让初始标题，正文大标题滚出后显示紧凑标题。平板与 2in1 宽窗口将顶部一级导航放在 Tabs 外层共享的原生 Navigation 标题栏中，高度 56vp，保留相同的原生渐进模糊及安全区延伸。宽模式各 Tab 直接使用 Scroll，起始偏移仍为 56vp；正文滚动和切页时顶部栏保持原位。标题栏按钮使用同一套系统材质；`module.metadata` 配置 `ohos.arkui.UIMaterial.state: enable`。设备材质能力通过 `uiMaterial.isImmersiveMaterialSupported()` 检查，材质效果由系统根据设备能力呈现。

平板与 2in1 在窗口宽度达到 840vp 时，将 Logo、LexiGlow 与首页/词库/统计/我的放在同一顶部标题行；当前页使用无边框高亮，切换沿用标准 TabsController 的动画。窄窗口恢复现有悬浮底部 Dock。主页面使用整个窗口宽度计算卡片布局，不再预留侧栏，标题与正文共同居中；600vp 以上顶部对齐，正文上限为 1600vp。词库按最小 320vp 卡宽显示一至三列，统计与设置按最小 300vp 卡宽显示一至两列，列宽显式扣除固定间距，避免原来的 `49% + 16vp` 在小窗中意外换行。短窗口收紧标题、计划卡片和页边距。大屏首页增加现有学习累计概览及每日一词释义，手机保持原来的首页内容。已学列表支持一至三列；挑战页用同一 Flex 输入结构响应宽度变化。浅色背景统一恢复为 `#F6F2E4`，包含启动窗口与 2in1。

本次响应式调整通过 HAP/APP 构建与 `tools/test-layout.cjs` 的 7 组几何检查，覆盖侧栏断点、最小卡宽、固定间距、等比例缩窗和反复缩放。模拟器验证平板全屏首页、词库、统计、已学列表、挑战页，2in1 最大化与等比例缩小窗口，以及手机首页。截图见 [平板首页](screenshots/tablet-responsive-home.png)、[平板词库](screenshots/tablet-responsive-books.png)、[2in1 全屏](screenshots/desktop-responsive-full.png)、[2in1 小窗](screenshots/desktop-responsive-small.png)。

## 华为官方依据

- [组件导航与 Navigation](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-navigation-introduction)
- [Navigation / NavPathStack API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-navigation)
- [ArkData relationalStore API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-relationalstore)
- [Preferences API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-preferences)
- [创建 ArkTS 卡片](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-creation)
- [Hvigor 命令行构建](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app)
- [沉浸光感典型场景](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sample)：标准 Tabs 悬浮栏，以及内容区标题切换至 Navigation/NavDestination 标题栏的原生渐进模糊效果。
- [开启沉浸光感](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense-enable)、[组件适配沉浸光感](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense-component-adaptation)：module 开关、系统材质接口与生效区域。
- [Tabs 沉浸式布局](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1584)：背景、布局和滚动内容的安全区延伸。
- [组件位置设置](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-location)：Scroll 默认居中，`align(Alignment.Top)` 改为顶部对齐。
- [多设备窗口模式](https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-window-mode)：根据实际窗口、容器尺寸响应全屏与自由窗口。
- 发音、文件选择、提醒的官方依据及设备条件见 [PLATFORM.md](PLATFORM.md)。

本机 SDK 元数据：`/Applications/DevEco-Studio.app/Contents/sdk/default/sdk-pkg.json`，`platformVersion:26.0.0`、`releaseType:Release`、`version:26.0.0.105`。工程没有降级到旧 SDK 或为了绕过编译禁用 ArkTS 检查。

## 已完成的验证

API 26 Release HAP 构建通过。25 组服务/SQLite 行为检查和 13 组释义匹配及挑战状态检查通过，平台解析和状态机检查、10,689 词头资源校验及沉浸视效静态审计通过。释义检查覆盖内置词库全部 26,071 条释义。原生模拟器通过 3 项真实 zlib/XML 和格式往返测试，并实际走通导入、改名、词条编辑、文件保存、单词判断、学习计数刷新、中文释义挑战、已学日期查询与四页 Dock 深浅色切换。新标准 Tabs 已实测背景和滚动内容延伸至底部手势区，8vp 悬浮栏保留安全距离；首页、词库滚动标题的原生渐进模糊及导入页原生标题栏也已验证。具体设备条件和验证记录见 [PLATFORM.md](PLATFORM.md) 与 [HDS.md](HDS.md)。

## 设备验收清单

1. 第一次启动不用登录，在一分钟内完成首批 3 词，首页显示真实新词记录。
2. 同一个词分别作不认识、模糊、认识判断，详情显示不同下次复习时间；不能在答案未显示时判断。
3. 学到一半退出或结束应用进程，重开同一学习模式后续上当前位置，已提交词不重复计数。
4. 收藏一个未学词：收藏数增加，已学数与到期数不变；加入生词本后后续新词队列可学习该词。
5. 选用另一本包含相同词的自定义词书：相同词的 strength、nextReviewAt 和历史不重置。
6. 飞行模式下完成学习、复习、搜索、统计；英语语音包已安装时可播放发音，缺包时不阻断学习。
7. 导入 UTF-8 JSON/TXT、含中文表格/单词行的 DOCX 和含引号、逗号、多行例句的 CSV。改名与修改自定义释义后关闭重开仍保留，内置同名词不变。JSON/CSV/TXT 导出可重新导入，取消选择器不改数据。
8. 临时选择很忙/正常/有空，只改变当天预算。跨本地午夜、手动改变系统日期后首页刷新生成相应日期计划，不清空长期进度。
9. 字体放大、浅色/深色、手机/宽窗口下阅读与操作可用。页面以 Scroll/List 与最大内容宽度适配；没有硬编码全屏像素尺寸。背景与滚动内容延伸底部手势区，底栏与关键操作保持安全距离，顶部状态栏和挖孔仍自动避让。
10. 两种卡片添加/刷新、冷热启动跳转、通知授权拒绝/允许、代理提醒定时触发，依照 PLATFORM.md 在真实设备核查。

## 发布仍需完成

开发者签名、华为代理提醒能力审批、设备验收、应用市场品牌/内容审核，以及应用市场隐私政策链接。源码中没有凭证；本地未签名 HAP 的构建成功不等同于已经签名、安装、验收或上架。
