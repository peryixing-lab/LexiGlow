# 词萤小艺 Agent 配置与后续接入

## 当前平台配置

2026-10-09 已在小艺开放平台创建并配置单 Agent，ID 为 `agent45dc43c526b04198880cef3bcfa55457`，模型为 `DeepSeek-V3.2`。2026-10-14 平台仍显示「上架审核不通过」，本次修改未重新提交审核。

一句话描述保留为「我是词萤 LexiGlow，你的学习小帮手。」。2026-10-14 开场语改为「你好，我是词萤学习助手。我可以分享单词记忆技巧、讲解常用词，并带你学习每日一词。你也可以直接发来想学的单词。」。

- 当前定位为对话中的词汇学习助手，提供单词记忆技巧、常用词解析和每日一词练习，不提供学习备份统计或词书文件转换。
- 三条开场引导为「单词记忆小技巧」「常用单词 get 解析」「每日一词学习」，点击后直接回答，不要求上传文件或先填写水平调查。
- AgentCard 已同步为上述三项教学能力。文件上传已关闭，输入类型为字符串；照片与拍摄也保持关闭。
- 未接入外部插件、工作流或应用数据接口，不直接读取、上传或修改本机学习记录；“每日一词”由用户主动发起，不承诺自动推送。
- 2026-10-14 按用户“先连接 1.1.1”的要求，在平台关联已发布的词萤手机应用：包名 `com.lovexjy.lexiglow`，appId `6917618353575572135`。保存并刷新后显示关联应用 `1/20`。关联项按应用身份配置，不绑定具体版本；它不为市场版补充 DeepLink，也不代表 App 内已集成 AgentKit 或已接通学习数据。

本轮在平台分别点击三个新引导完成调试：记忆技巧返回 `focus` 的主动造句示范与一分钟练习；常用词解析返回 `get` 的词义、三组搭配和易混用法；每日一词返回 `check` 的音标、词义、生活例句和填空练习。三次均直接生成学习内容，没有索要备份或文件。此结果证明所测对话流程可用，不代表已穷尽模型事实质量或完成小艺到 App 的设备验证。

此前“导出整本学习备份并上传/改后缀”的流程受平台字符、文件格式和解析限制，无法稳定体验，已从引导、角色与能力介绍中移除。用户询问相关功能时，仅说明当前智能体的能力范围并引导至 App 内功能，不再要求导出、改后缀或粘贴整本词书。

## 今日学习计划快捷指令

App 新增 `lexiglow://study/plan`，对应独立的「今日学习计划」页面。页面复用首页的真实计划卡片，展示新词与复习目标、完成情况及开始学习按钮；打开链接不自动创建学习会话。

[module.json5](../entry/src/main/module.json5) 为已有的 `EntryAbility` 注册 `entity.system.browsable`、`ohos.want.action.viewData` 与精确的 `lexiglow` / `study` / `plan` 匹配。[LaunchRouteUtils.ets](../entry/src/main/ets/utils/LaunchRouteUtils.ets) 只接受这一外部 URI，未知 URI 不使用参数路由作为回退；无 URI 的旧桌面卡片、提醒及分享路由保留。[EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets) 在冷启动保存待处理路由，在热启动发送已有的 `openRoute` 事件。[Index.ets](../entry/src/main/ets/pages/Index.ets) 在初始化或新手设置完成后消费路由，并在显示计划时刷新本机数据。

小艺开放平台配置：

2026-10-13 已在 Chrome 保存为静态快捷指令，平台显示「今日学习计划 · 跳转型」，快捷指令数量为 `1/30`。2026-10-14 按用户明确的版本计划，将最低 App 版本修正为 1.2.0 对应版本码；未重新提交上架。

| 字段 | 值 |
| --- | --- |
| 快捷指令文案 | 今日学习计划 |
| 位置 / 类型 | 底部 / 跳转型 |
| 跳转方式 | DEEP LINK |
| 应用名称 | 词萤 |
| 应用包名 | com.lovexjy.lexiglow |
| DeepLink | lexiglow://study/plan |
| app 最小版本号 | 200612082 |
| Action 名称 | ohos.want.action.viewData |

最低版本按 `versionCode` 整数填写，当前工程为 `versionName: 1.2.0` / `versionCode: 200612082`。用户确认市场版为 1.1.1，并明确跳转作为 1.2.0 特性；此前门槛 200612081 错误地把市场版列为可体验版本，已修正。修改门槛不会给 1.1.1 安装包增加入口，也不能代替新包发布或设备验证。必须先发布支持链接的 1.2.0 App，再重新提交 Agent 审核。

随后用户要求先连接 1.1.1。已完成手机应用关联，但旧版没有当前链接的 URI skill，不能直接把最低版本降到 1.1.1 并宣称快捷跳转可用。当前平台静态跳转的 DeepLink 为必填；下拉中的“界面”选择的是智能体用户界面资源，并非 App 的首页。官方[关联应用](https://developer.huawei.com/consumer/cn/doc/service/related-applications-0000002437785706)介绍的是已集成 AgentKit 的应用呼出 Agent，未提供通用的旧版 App 启动链接。快捷指令替代行为仍待用户选择，不能把关联配置描述为已修复“暂无可用打开方式”。

2026-10-14 只读核对：源码与最新未签名 debug HAP 均含相同的 URI skill，版本为 1.2.0 / 200612082，本地打包没有遗漏声明。当前未连接设备，尚未验证系统匹配和小艺调用；不得将本地声明核对或单元测试描述为真机跳转成功。本次未因旧市场包的失败盲目更改 URI/action 或其它 App 源码。

官方参考：[基础能力配置](https://developer.huawei.com/consumer/cn/doc/service/base-ability-0000002675010323#section11335141012574)、[DeepLink 参数定义](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/multi-jump-0000002485633457)。

2026-10-13 构建与签名成功；`tools/test-launch-routes.cjs` 9 项、`tools/test-ui-lifecycle.cjs` 15 项、`tools/test-layout.cjs` 8 项全部通过。路由测试执行真实 Ability 生命周期和页面处理方法，覆盖冷热启动、新手设置后的路由消费、未知 URI 不覆盖待处理路由，以及原卡片/分享接收流程。当前未连接测试设备，系统 URI 匹配、实际页面布局和小艺快捷指令到 App 的完整流程尚未做设备验证；上线前需分别验证 App 未运行与已运行时的跳转，以及计划中的开始学习按钮。

## 历史备份型试验（当前智能体不启用）

以下保留 2026-10-09 的报告统计、词书整理与后续接口设计记录，不能作为当前能力介绍或现版本的导出/上传操作指引。

### 报告统计口径

| 指标 | 软件口径 |
| --- | --- |
| 累计已学 | 按 `wordId` 去重，`progress.reviewCount > 0` |
| 当前掌握 | 已学且 `strength >= 75`；不能等同于本周新掌握 |
| 强度分布 | 0–24 陌生、25–49 模糊、50–74 熟悉、75–100 掌握 |
| 周期新词／复习 | 分别汇总 `days.newCount`／`days.reviewCount` |
| 学习任务次数 | `days.totalCount = newCount + reviewCount`，不是去重词数 |
| 复习成功率 | `sum(knownCount) / sum(reviewCount)`；`knownCount` 仅计复习时判断「认识」，无复习时显示暂无数据 |
| 连续学习 | 从今日有活动时的今日、否则昨日起，向前连续 `totalCount > 0` 的本地日期 |
| 到期词数 | 已学且 `nextReviewAt <= asOf` |
| 记录的答题时长 | `sum(days.durationMs)`，每次判断最多记录 5 分钟；不是应用使用总时长 |
| 计划完成率 | `(newDone + reviewDone) / (newTarget + reviewTarget)`；完成判断要求两类目标分别达到 |

`result` 为 0 不认识、1 模糊、2 认识；`progress.reviewCount` 包括初学，不能直接作纯复习次数。跨词书同一单词共享进度，不重复相加。中文释义挑战不写学习进度或每日统计。日期是设备本地 `YYYY-MM-DD`，时间戳单位为毫秒，本周从本地周一零点开始。备份没有时区、逐条 `item_type` 和独立首次掌握表；优先采用每日汇总，缺失字段明确标注，不能猜测首次掌握日期。

依据：[LearningRepository.ets](../entry/src/main/ets/repository/LearningRepository.ets) 第 545–546、677–696、725–764 行；[DailyPlanUtils.ets](../entry/src/main/ets/utils/DailyPlanUtils.ets) 第 4–10 行；[TimeUtils.ets](../entry/src/main/ets/utils/TimeUtils.ets) 第 1–26 行；[IMPLEMENTATION.md](IMPLEMENTATION.md) 中「中文释义挑战」说明。

### 历史词书转换边界

优先输出完整 UTF-8 JSON：`{"name":"词书名","words":[{"word":"apple","phonetic":"","meaning":"n. 苹果","example":"","translation":""}]}`。也可输出带 `word,phonetic,meaning,example,translation` 表头的 CSV 或五列制表符 TXT。文字回复需由用户保存成对应文件，再在词萤中导入并确认预览。

最终文件须不超过 5 MB，每份 1–5000 词；词头转小写、去重，保留原有释义和例句。`word` 仅接受英语字母、空格、直单引号和连字符，最长 80 字符；`meaning` 非空且最长 600 字符，`phonetic` 最长 200，`example/translation` 各最长 2000。可选字段缺失用空字符串。源内容缺少释义时不得无提示地编造；需单列待补项，或解释 TXT/DOCX 可由应用本地词典匹配、未匹配项仍须用户补全。超限、歧义、重复冲突需报告，不能静默截断。

格式与限制依据：[TransferService.ets](../entry/src/main/ets/service/TransferService.ets) 第 23–29、85–107、139–210 行。应用现有导入器支持 JSON/CSV/TXT/DOCX；Agent 接受的 PDF、表格等须转换后再导入。

### 后续只读应用数据契约（尚未实现）

拟新增端侧插件 `get_learning_report_data`，由应用在用户授权后读取本机数据并返回最小报告数据。平台角色规则不能替代接口。当前 [module.json5](../entry/src/main/module.json5) 未声明该意图或插件，[LearningService.ets](../entry/src/main/ets/service/LearningService.ets) 的 `getSnapshot()` 仅是应用内部服务。

请求建议包含 `startDate/endDate`（本地日期，包含两端）、`timezone`（IANA 时区）、`asOf`（毫秒时点，省略则由应用生成），可选 `bookId` 和明确的统计范围。应用需验证范围，并在返回中回显实际时区、日期和数据时点；不能重建历史进度时，应拒绝过去的 asOf，不能将当前快照描述为过去状态；历史每日汇总按当时设备本地日期保存，不能擅自重分桶。未实现历史状态重建时，应拒绝过去的 `asOf`，不能以当前进度冒充过去状态。

返回建议为版本化结构：

- `schema/version/generatedAt/asOf/timezone/range/scope` 与缺失、截断等 `warnings`。
- `summary`：周期新词、复习、任务、认识判断数、复习成功率、答题时长、活跃天数；累计已学、当前掌握、连续天数、到期数量及强度分布。
- `days`：范围内按日汇总的 `date/newCount/reviewCount/knownCount/totalCount/durationMs`，补齐无活动日期。
- `plan`：今日目标和完成量；最小化 `currentBook` 信息与用户学习目标。
- 若报告需要具体薄弱词，另行明确请求并限制条数，仅返回必要词头、释义、强度和错误数量；默认不传全部词书、逐次记录、未完成会话或提醒偏好。

端侧读操作不修改计划、进度、收藏或词书；用户拒绝、取消或数据不可用时返回明确状态，不以演示数据补位。应明确展示读取范围、用途及需要传给云端的字段，经用户同意后再传输；授权不可从一次普通聊天永久推定。凭据放在平台配置或应用安全存储中，不硬编码到工程或提示词。

华为官方要求应用先支持鸿蒙意图框架调用及数据输出，端调用插件注册并加白名单后才能生效；应用按调用指令的输出参数回传数据。详见[响应 data 数据结构定义](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/response-data-0000002505931382)。

### 后续本地校验与文件输出（尚未实现）

词书校验和保存应作为独立能力实现：将 Agent 转换结果交给本地 `TransferService.parse` 验证，返回具体行号、字段和冲突信息；验证通过后再由系统保存选择器输出文件。写入路径由用户选择，实际导入继续使用应用预览与确认流程。没有写入工具时，Agent 只返回完整文本，不能声称文件已经生成或导入成功。

### 历史测试

2026-10-09 使用虚构数据在平台调试：

- 词书去重：3 条源数据、1 条重复、2 条输出；表头不计数。初测说明曾把表头计入条数，补充计数规则后用另一组词头重测正确。
- 含逗号、中英文引号的 JSON 输出通过实际 `TransferService.parse`，解析出 2 条，五个字段完整保留。
- 混合缺释义初测曾丢失已有释义，已加入明确的保留样例。新会话使用 orange（空释义）与 give up（放弃）重测，返回带表头的 TAB 文本，保留 2 条及原释义。实际 `TransferService.parse` 验证通过，空行/表头不计数；缺释义仍留待预览补齐。此验证未覆盖本地词典匹配和数据库写入。
- 报告核心数字核对：2 个新词、0 次复习、2 个活跃日、90 秒记录时长、2 个已学词、1 个掌握词、1 个备份时点到期词；无复习时显示“暂无复习记录”，未学收藏词不计入已学。
- 报告初测的建议曾混淆学习活动与计划完成、已经到期与未来新增到期；补充规则后重测正确判断今日计划未完成，并建议先处理备份时点已到期的 shine。模型也曾将毫秒时间戳换算为错误时刻，已限制无日期执行工具时沿用用户提供的时刻，未能校验时不展示推算时刻。最终五句报告样例正确沿用用户声明的 12:00，统计数字一致，计划未完成，建议先处理已到期的 shine。

当前验证仅覆盖短文本与示例数据，未验证大文件、真实上传解析、自动应用数据读取、文件附件生成或发布审核。需要严格保证统计和词条数量时，应由未来端插件/本地解析器计算与校验，再交给模型组织语言。
