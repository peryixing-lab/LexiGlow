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

`AudioService` 使用 Core Speech Kit，创建 `language: 'en-US', person: 8, online: 1` 的离线引擎，先注册监听器再播报；播放结束、取消、错误均释放挂起状态，退出应用释放引擎。

Huawei SDK 标明英语 Laura 音色需要下载。**已安装英语语音包后发音离线可用**。应用本身不发起网络下载；模拟器缺少 TTS 能力或设备未安装对应模型时，返回可展示给用户的错误，同时保留文字学习功能。

参考：[官方语音引擎使用说明与示例](https://developer.huawei.com/consumer/cn/doc/doccenter-industry-solutions/backgroundtask-0000002757018167)、[基础语音常见问题](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-core-speech-kit)。参数签名核对本机 `@hms.ai.textToSpeech.d.ts`。

## 轻提醒

默认关闭。用户主动开启后，才请求通知授权并提交 `ReminderRequestCalendar`，每天在选择的本地时间轻提醒一次。Preferences 保存提醒 ID；修改时间替换原提醒，关闭只取消本应用保存的提醒，不影响其它应用的日程。

**代理提醒是受管控的开放能力**。上架前需在华为开发者后台申请并开启代理提醒能力，再配置 `ohos.permission.PUBLISH_AGENT_REMINDER`。仅声明权限不能替代能力审批。能力不可用、授权拒绝或发布失败时，服务抛出明确错误，界面应保持提醒关闭。

参考：[华为代理提醒能力、权限与通知授权说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-background-tasks-11)、[API 26 Background Tasks Kit 变更](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/js-apidiff-backgroundtaskskit-hdc)。日期、循环和取消签名核对本机 `@ohos.reminderAgentManager.d.ts`。

## 导入和导出

`TransferService.importFile` / `exportFile` 从 UIAbilityContext 使用系统 `DocumentViewPicker`。只读取用户选择的文件、只写入用户选定的保存 URI，无需全盘存储权限，文件句柄在 `finally` 关闭。

导入支持 UTF-8 JSON（单词数组，或 `{ "name": "词书名", "words": [...] }`）、CSV、TXT 和 Word `.docx`。CSV 支持 BOM、CRLF、双引号内的逗号和换行、`""` 转义双引号。必需列是 `word,meaning`，可选列为 `phonetic,example,translation`。TXT 支持每行一个词、`word<TAB>meaning`、英文单词加空格中文释义、冒号分隔，以及五列 `word,phonetic,meaning,example,translation` 的制表符文本。中英文表头可声明列顺序；TXT/DOCX 只有英语单词时保留空释义，由本地词典补全，未匹配的项目由用户在导入预览中填写，不能直接存入可学习词书。

DOCX 仅抽取 `word/document.xml` 的正文和表格，保留同一段落多个文字 run，合并表格单元格段落，通过官方 `xml.XmlPullParser.parseXml` 读取 XML。整段叙述和标题不会当作单词导入。压缩目录和本地条目交叉校验路径、格式、大小，再使用官方 `zlib.Zip.inflateInit2(..., -15)` / `inflate` 在定长缓冲区中解压，校验 CRC32。源文件最多 5 MB，正文最多 4 MB，压缩目录最多 2000 项、声明总解压量最多 20 MB；拒绝加密、ZIP64、路径穿越、符号链接、DTD 和外部实体。只在内存中提取正文，不展开附件或写入压缩包里的路径，也没有残留临时目录。

输入限制为 5 MB、5000 个单词，逐字段验证并在单次导入内去重；数据仓库进一步按规范化单词跨词书去重并保留学习进度。粘贴导入复用同一 `parse` 验证流程。旧版二进制 `.doc` 文件需先在 Word 中另存为 `.docx`。

导出使用系统保存弹窗写入 JSON 学习备份；`exportBookFile(context, name, words, format)` 将指定词书导出为 JSON、CSV 或 TXT，三种格式可再次导入。CSV 保留引号、逗号和多行例句；TXT 用制表符保存五列，字段内换行变为空格。系统文件选择器返回空数组时按用户取消处理；缺少文件选择器能力的设备可以使用应用里的粘贴导入入口。

参考：[DocumentViewPicker 官方 API 与权限说明](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)、[华为 zlib ZIP / Raw Deflate / CRC32 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-zlib-V5)、[压缩解压缩模块说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/archive-overview)。文件读取、写入、关闭、UTF-8 编解码及 XML 解析签名核对本机 Core File Kit、Basic Services Kit 和 ArkTS SDK 类型声明；XML 官方网页本次检索超时，未以第三方实现替代运行时官方 API。

## 可重复验证

执行 `node tools/test-platform.cjs`，直接转译本工程 ArkTS 服务源码，用 Kit Mock 验证 JSON/CSV/TXT 输入、真实 DOCX ZIP 的压缩/未压缩正文、表格、多 run、实体解码、正文筛选与恶意文件拒绝、词书导出的格式往返、TTS 播放完成与资源释放、代理提醒的 ID 替换和通知拒绝路径，并使用已安装 Huawei SDK 的 JSON Schema 验证两种卡片配置。ZIP Mock 使用 Node 的 zlib，XML Mock 使用 Python 3 标准库 ElementTree 产生解析事件；它们不能验证设备上的原生 Kit。默认读取 macOS DevEco Studio 的官方 TypeScript；其他安装路径可设置 `DEVECO_STUDIO_HOME`、`LEXIGLOW_TYPESCRIPT` 或 `LEXIGLOW_PYTHON`。这些检查不能替代真机的 Kit 可用性、语音包、签名权限和桌面卡片交互验收。

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
3. 安装英语语音包后断网播放单词；未安装时显示提示且可继续学习。
4. 通知授权拒绝时提醒保持关闭；获准的代理提醒在应用退出后按设定时间显示，关闭设置后不再出现。
5. 导入带中文释义、逗号、引号及多行例句的 CSV；导入已学单词不重置进度；取消文件选择不改变数据库。
6. 导出的 JSON 可被解析且包含实际学习进度；设备旋转、字体放大和桌面卡片长单词仍可阅读。
