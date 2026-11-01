# 词萤的 HarmonyOS 平台能力

本工程沿用现有 `26.0.0` SDK 配置，接口以本机 DevEco Studio 随附的 Huawei SDK 类型声明和华为官方文档核对。该 SDK 是项目当前的开发基线；正式发布还应在对应系统版本的真机验证。

## 桌面卡片

`EntryFormAbility` 提供 `2×2` 每日一词和 `2×4` 今日计划。卡片通过 `@LocalStorageProp` 接收数据；点击使用 `postCardAction` 的 `router` 事件，进入 `EntryAbility`。

传入 `Want.parameters` 的约定：

| route | 作用 | 附加参数 |
| --- | --- | --- |
| `word` | 每日单词详情 | `wordId: number` |
| `today` | 今日学习 | — |
| `review` | 到期复习 | — |
| `quick` | 3 分钟速学 | — |

`FormService.update(snapshot, context)` 在学习数据变化后更新已添加的卡片。Preferences 保存卡片 ID 和小型快照；系统查询补充遗漏的 ID。新增卡片先返回快照，再异步读取学习数据库；系统周期更新和 `00:05` 更新重新读取真实的当天计划。刷新调度受系统节能策略影响，应用内学习后的主动刷新不依赖精确的后台计时器。卡片进程使用与应用一致的本地数据，没有独立的模拟学习记录。

参考：[卡片生命周期管理](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/arkts-ui-widget-lifecycle-V5)、[FormExtensionContext](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-inner-application-formextensioncontext)、[官方卡片数据绑定示例](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/push-form-update)。本项目采用本地 `updateForm`，没有接入示例中的 Push Kit 网络推送。

## 英语发音

自动读出单词默认关闭，用户可在「我的 → 学习偏好」自行开启；单词旁的朗读按钮始终可用。旧版缺少显式选择标记的偏好首次升级为关闭并写回一次；用户主动更改开关后保存 `autoPronounceConfigured`，后续启动和修改其他偏好均保留选择。

英语和中文均通过华为 Core Speech Kit 系统引擎朗读。`listVoices({ online: 1 })` 查询离线音色，选择系统报告的 `person` 与 `style`；优先已安装的 `en-US` 英语音色，无可用英语音色时兼容系统 `zh-CN` 双语引擎。`online: 1` 在本机 SDK 中代表离线模式。

「我的 → 学习偏好 → 单词朗读」显示实际系统音色状态；仅缺少英语音色且系统报告可下载时，提供用户主动下载入口。`downloadVoice` 由华为系统服务管理下载与存储，应用不自动下载，不申请 `INTERNET` 权限，也没有第三方语音网络请求。保留删除检查音色和试听按钮的产品要求。

播放以 `onComplete.type === 1` 作为声音播报完成的依据；`type === 0` 仅表示合成完成，不推进听词队列。保留后台音频通道、`isBackStage`、取消旧请求与退出释放。日志不记录单词或释义内容。

应用包移除 MeloTTS 模型、ONNX Runtime、Flite 及其原生构建依赖；升级时按旧语音缓存目录名称清理模型、词典和音素缓存，不触碰学习数据库、备份或系统音色。系统音色是否可用与音质取决于设备语音服务，不能以模拟器或 Mock 测试代替真机听感验收。

参考：[Core Speech Kit](https://developer.huawei.com/consumer/cn/sdk/core-speech-kit/)、[文本转语音 API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hms-ai-texttospeech)、[文本转语音开发指南](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/texttospeech-guide)、[基础语音错误码](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/errorcode-corespeech)。接口签名与 `online`、音色状态、下载事件、完成回调语义以本机 API 26 Release `@hms.ai.textToSpeech.d.ts` 核对。

## 轻提醒

默认关闭。用户主动开启后，才请求通知授权并提交 `ReminderRequestCalendar`，每天在选择的本地时间轻提醒一次。Preferences 保存提醒 ID；修改时间时先登记并保存新实例，再显式取消仍然有效的旧实例。关闭只取消本应用的学习提醒，不影响其它应用的日程。

用户下载的 `agconnect-services.json` 原样放在 `entry/agconnect-services.json`，已核对包名为 `com.lovexjy.lexiglow`。本地配置加入 Git 忽略规则，不把密钥写入日志或复制到公开文档。当前 ArkTS 学习提醒使用系统 Background Tasks Kit，并不通过 AGC SDK 加载这份 JSON；能力权益由签名 Profile 和设备通知授权共同决定。当前用户重新生成的 Release Profile 已包含 `com.huawei.service.notification.agentreminder`。

提醒通过 `SERVICE_INFORMATION` 通道发送。每日提醒使用原生周期日历实例，内容与到时内容均为“今天的任务还没完成哦，赶紧来学习吧”。以本地当天 `daily_summary.new_count` 与用户设置 `dailyNewTarget` 比较；达到目标后通过 `addExcludeDate()` 只跳过当天，未来每天继续由系统调度。目标提高后，尚未到提醒时间则恢复当天提醒；已过时不补发。到点后的刷新保留已登记且未完成的当天提醒，避免与系统投递竞争；异步授权或排队跨午夜后，不把昨日完成量沿用到今天。学习记录保存、目标修改、启动和回到前台都会被动同步，通知未授权时不弹窗，提醒同步错误不影响学习记录保存。界面不再提供测试通知入口，升级时只清除历史测试提醒和测试通知，保留正常每日提醒。状态读取系统有效实例及当天排除日期。

**代理提醒是受管控的开放能力**。上架前需在华为开发者后台申请并开启代理提醒能力，再配置 `ohos.permission.PUBLISH_AGENT_REMINDER`。仅声明权限不能替代能力审批。能力不可用、授权拒绝或发布失败时，服务抛出明确错误，界面应保持提醒关闭。

参考：[华为代理提醒能力、权限与通知授权说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-background-tasks-11)、[API 26 Background Tasks Kit 变更](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/js-apidiff-backgroundtaskskit-hdc)。日期、循环和取消签名核对本机 `@ohos.reminderAgentManager.d.ts`。

最新依据：[华为代理提醒 ArkTS 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)、[通知通道 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-notificationmanager)、[签名 Profile 与开放能力](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing-auto)。API 20 起支持模拟器开发的说明可交叉核对 [OpenHarmony 官方代理提醒指南的模拟器支持情况](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/task-management/agent-powered-reminder.md#模拟器支持情况)。支持模拟器开发不代表每个模拟器安装环境都已获得当前应用的代理提醒使用权益。本项目保留用户已更新的手动签名配置。

2026-10-10：用户确认已自行解决原通知问题。后续工作保留 AGC、签名及权限配置，按新增需求接入目标完成判断。服务回归可以验证条件与错误处理，不能替代正式设备投递验收。

2026-10-11：用户已在真机确认“通知我已经测试没问题”，本轮学习提醒验收状态为通知正常。工作保留用户已经完成的 AGC、签名及权限配置。

历史 QA 限制：本轮临时 API 26 模拟器当时通知已允许、当前应用有效提醒为 0，但系统 `publishReminder()` 返回 `1700002`。该记录仅说明当时的临时模拟器环境拒绝登记，不作为当前真机通知故障的结论。已只读确认当前 Release Profile 的 `app-services-capabilities` 包含 `com.huawei.service.notification.agentreminder`；没有修改签名或系统提醒许可。该错误在系统中可来自应用代理提醒使用门禁或数量限制，不能仅按字面理解为本应用已创建过多提醒，也不能据此认定 Profile 缺失能力。依据：[官方代理提醒发布服务的能力与数量检查](https://github.com/openharmony/notification_distributed_notification_service/blob/master/services/reminder/src/reminder_agent_service.cpp)。

相同 `notificationId` 对应的通知展示可以覆盖，但 `publishReminder()` 创建独立日程实例，不能依赖它自动取消旧日程。替换时再次查询旧 ID 的身份，新登记或持久化失败时清理新实例并恢复原登记；旧实例取消失败时保留原日程及排除日期，允许重试。`tools/test-reminders.cjs` 按原生多实例语义运行，58 项提醒回归通过，覆盖未完成/完成、提高目标、到点竞争、跨日、并发、陈旧 ID、测试通知清理与故障回滚；平台服务检查通过。源码回归与真机验收分别记录，真机通知结果由用户在本轮确认正常。API 依据：[华为 ReminderAgentManager](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-reminderagentmanager)、[官方实例管理与通知展示源码](https://github.com/openharmony/notification_distributed_notification_service/blob/master/services/reminder/src/reminder_data_manager.cpp)。

## 导入和导出

`TransferService.importFile` / `exportFile` 从 UIAbilityContext 使用系统 `DocumentViewPicker`。只读取用户选择的文件、只写入用户选定的保存 URI，无需全盘存储权限，文件句柄在 `finally` 关闭。

导入支持 UTF-8 JSON（单词数组，或 `{ "name": "词书名", "words": [...] }`）、CSV、TXT 和 Word `.docx`。CSV 支持 BOM、CRLF、双引号内的逗号和换行、`""` 转义双引号。必需列是 `word,meaning`，可选列为 `phonetic,example,translation`。TXT 支持每行一个词、`word<TAB>meaning`、英文单词加空格中文释义、冒号分隔，以及五列 `word,phonetic,meaning,example,translation` 的制表符文本。中英文表头可声明列顺序；TXT/DOCX 只有英语单词时保留空释义，由本地词典补全，未匹配的项目由用户在导入预览中填写，不能直接存入可学习词书。

DOCX 仅抽取 `word/document.xml` 的正文和表格，保留同一段落多个文字 run，合并表格单元格段落，通过官方 `xml.XmlPullParser.parseXml` 读取 XML。整段叙述和标题不会当作单词导入。压缩目录和本地条目交叉校验路径、格式、大小，再使用官方 `zlib.Zip.inflateInit2(..., -15)` / `inflate` 在定长缓冲区中解压，校验 CRC32。源文件最多 5 MB，正文最多 4 MB，压缩目录最多 2000 项、声明总解压量最多 20 MB；拒绝加密、ZIP64、路径穿越、符号链接、DTD 和外部实体。只在内存中提取正文，不展开附件或写入压缩包里的路径，也没有残留临时目录。

输入限制为 5 MB、5000 个单词，逐字段验证并在单次导入内去重；数据仓库进一步按规范化单词跨词书去重并保留学习进度。粘贴导入复用同一 `parse` 验证流程。旧版二进制 `.doc` 文件需先在 Word 中另存为 `.docx`。

导出使用系统保存弹窗写入 JSON 学习备份；`exportBookFile(context, name, words, format)` 将指定词书导出为 JSON、CSV 或 TXT，三种格式可再次导入。CSV 保留引号、逗号和多行例句；TXT 用制表符保存五列，字段内换行变为空格。系统文件选择器返回空数组时按用户取消处理；缺少文件选择器能力的设备可以使用应用里的粘贴导入入口。

学习备份与词书导入分开处理。「我的 → 从备份恢复进度」只读取用户选中的 JSON（上限 50 MB），先校验格式版本、字段、数量和所有单词引用，再展示导出时间、词书与已学数量，明确确认覆盖。错误文件或取消选择不会写入数据库。普通词书入口明确拒绝学习备份，避免误导入成词书。

新导出版本为 3，包含完整单词表、每本词书的内容及顺序、学习进度、回忆记录类型、每日计划与统计、未完成会话、历史掌握时间、拼写成绩、补光记录和学习设置。单次 RDB 事务恢复这些表与 `app_meta.user_settings`，失败回滚；成功后刷新内存、页面和卡片。现有 Preferences 学习设置首次迁入 RDB，以便数据与设置同时提交。系统提醒 ID 保持原存储方式，备份不迁入来源设备的提醒开关、提醒时间或系统通知授权。

兼容 v1/v2 已有备份；旧格式没有的扩展字段采用兼容默认值。若旧备份中存在没有对应单词内容的孤立进度，不能凭编号猜测词义，恢复会要求在原设备更新后重新导出。

参考：[DocumentViewPicker 官方 API 与权限说明](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)、[华为 zlib ZIP / Raw Deflate / CRC32 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-zlib-V5)、[压缩解压缩模块说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/archive-overview)。文件读取、写入、关闭、UTF-8 编解码及 XML 解析签名核对本机 Core File Kit、Basic Services Kit 和 ArkTS SDK 类型声明；XML 官方网页本次检索超时，未以第三方实现替代运行时官方 API。

## 可重复验证

执行 `node tools/test-platform.cjs`，直接转译本工程 ArkTS 服务源码，用 Kit Mock 验证 JSON/CSV/TXT 输入、真实 DOCX ZIP 的压缩/未压缩正文、表格、多 run、实体解码、正文筛选与恶意文件拒绝、词书导出的格式往返、音频播放完成与资源释放、代理提醒的 ID 替换和通知拒绝路径，并使用已安装 Huawei SDK 的 JSON Schema 验证两种卡片配置。ZIP Mock 使用 Node 的 zlib，XML Mock 使用 Python 3 标准库 ElementTree 产生解析事件；它们不能验证设备上的原生 Kit。默认读取 macOS DevEco Studio 的官方 TypeScript；其他安装路径可设置 `DEVECO_STUDIO_HOME`、`LEXIGLOW_TYPESCRIPT` 或 `LEXIGLOW_PYTHON`。这些检查不能替代真机的原生英语合成输出、中文离线音色、签名权限和桌面卡片交互验收。

## 原生模拟器结果

HarmonyOS 7 / API 26 模拟器的 `PlatformNativeTest` 已通过 3 项：真实华为 zlib/XML 的 DOCX 正文与表格读取、TXT 解析、JSON/CSV/TXT 导出后重新解析，Failure / Error 均为 0。测试 fixture 在 `entry/src/ohosTest/resources/rawfile/platform_wordbook.docx`，测试不读取学习数据库。

在 DevEco Studio 运行 `PlatformNative.test.ets`，或构建 `entry@ohosTest` 后使用官方测试运行器：

```sh
hdc shell aa test -b com.lovexjy.lexiglow -m entry_test -s unittest OpenHarmonyTestRunner -s class PlatformNativeTest -w 20
```

应用界面已实际验证粘贴单词自动匹配释义、确认导入、改名、同词 ID 的释义/例句编辑、系统返回后的列表更新。JSON 经真实 DocumentViewPicker 保存到模拟器 Documents，回读文件确认名称和编辑内容正确。学习提交一次后队列推进至第 2 词，首页和统计更新；中途退出后结束应用进程并重启，首页仍为 1/20，继续学习从第 2 词恢复。HDS 四页切换及明暗模式验证见 [HDS.md](HDS.md)。

## 真机验收

1. 学习一个单词后返回桌面，两种卡片的进度与应用一致；卡片三个区域分别进入对应流程。
2. 终止应用进程后点击卡片，首次启动仍正确读取 route 和 wordId；应用已打开时通过 `onNewWant` 更新入口。
3. 先通过系统服务准备英语音色，再断网播放单词、自定义导入单词及英文例句；中文音色可用时完成后台听词，缺少音色时显示明确提示。
4. 通知授权拒绝时提醒保持关闭；获准的代理提醒在应用退出后按设定时间显示，关闭设置后不再出现。
5. 导入带中文释义、逗号、引号及多行例句的 CSV；导入已学单词不重置进度；取消文件选择不改变数据库。
6. 在手机导出 JSON，再在平板选择文件、核对摘要并确认恢复；确认进度、词书顺序、收藏、统计和未完成会话一致，目的设备提醒设置保留。
7. 已学单词和词汇星图滚动视口使用 `LayoutPolicy.matchParent` 与底部 `ignoreLayoutSafeArea`，末尾留白随窗口 bottomInset 更新；设备旋转与深浅色下检查导航指示条附近背景和最后一项可达性。

## 1.1.1 本轮验收（2026-10-13）

- Hvigor 编译及签名通过；签名 HAP 约 5.2 MB。包内容检查确认无内置语音模型、旧离线合成库与联网权限。
- 朗读回归 30 项、听词流程 12 项、领域/SQLite 47 项、设置 8 项通过；平台服务检查通过，提醒既有 58 项回归保持通过。
- 两个隔离 API 26 手机/平板模拟器已安装。已学页面与星图底部背景、手机星图末尾按钮、平板深色星图进行了截图检查。
- 模拟器已通过系统双语音色实际朗读，观察到 Core Speech Kit 播放开始和 type=1 完成事件；英语 Laura 的真机音质和首次系统下载仍需在具备该音色的真机确认。
- 测试手机通过真实文件保存弹窗导出约 9 MB 的应用备份，再经系统文件选择器打开、预览和确认恢复，返回后已学数量及收藏保留。跨设备数据一致性、不同词 ID 和词书顺序通过独立 SQLite 数据库往返验证；本轮未通过模拟器之间实际传文件完成端到端迁移。
- 用户已验证的真机通知与签名配置未改动。
