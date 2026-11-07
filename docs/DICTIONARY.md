# 内置词书内容与来源

本地词书文件为 `entry/src/main/resources/rawfile/wordbooks/catalog.json`，当前内容版本为 `2`。五本词书完整保留所选 **ECDICT 固定快照中的对应标签词**，可离线学习；这些标签不能表述为现行官方考试大纲认证。

| 应用词书 ID | 展示名称 | 上游标签 | 实际词条数 |
| --- | --- | --- | ---: |
| cet4 | 四级 · ECDICT 词书 | cet4 | 3,849 |
| cet6 | 六级 · ECDICT 词书 | cet6 | 5,407 |
| graduate | 考研 · ECDICT 词书 | ky | 4,801 |
| ielts | 雅思 · ECDICT 词书 | ielts | 5,040 |
| toefl | 托福 · ECDICT 词书 | toefl | 6,974 |

合计 26,071 个词书条目、10,689 个不同词头。词书之间存在正常交集，同一个词头使用同一份内容及学习进度。文件为 3,157,625 字节，没有为凑数量拼造单词或复制例句填充。

## 上游数据与许可证

- 上游：[skywind3000/ECDICT — Free English to Chinese Dictionary Database](https://github.com/skywind3000/ECDICT)。
- 固定提交：[bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b](https://github.com/skywind3000/ECDICT/commit/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b)，提交日期为 2025-03-28。
- 实际输入：[该提交的 ecdict.csv](https://raw.githubusercontent.com/skywind3000/ECDICT/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b/ecdict.csv)，原文件 65,933,428 字节、770,611 条数据行。
- 仓库许可证：[该提交的 MIT LICENSE](https://github.com/skywind3000/ECDICT/blob/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b/LICENSE)，版权声明为 `Copyright (c) 2025 Linwei`。
- 完整 MIT 声明随应用保存在 `entry/src/main/resources/rawfile/licenses/ECDICT-MIT.txt`，保留许可要求的版权与授权原文。

此处按上游仓库发布的 MIT 许可使用其词典数据，没有引入音频、商业词典页面或付费例句。上游 README 说明数据库由历年资料、开源 cdict、语料库处理和网友贡献汇集而成；本项目记录的是上游仓库的许可与出处，不宣称对其每一个历史来源进行了独立权属认证。上游没有为这些考试标签注明具体大纲年份，因此不把仓库快照日期当作考试大纲年份。

机器可读的来源、计数、输入/输出 SHA-256 和处理方式记录在 `docs/DICTIONARY_SOURCE.json`。源 CSV 的 SHA-256 是：

```text
1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf
```

## 内容转换与例句

### 1.3 独立离线查询词典

`dictionary/lookup-v1.json` 是独立于五本学习词书的查询资源，来自同一固定 ECDICT 快照，共 **15,255 个词头、2,183,054 字节**。选择范围包括现有词书词头、BNC 或当代词频前 10,000、Oxford 标记、18 篇精选短文词形及已知原形。它保留 `translation` 的全部非空义项及 `exchange` 词形字段，不新增考试标签。

首次升级以事务及临时表批量导入：已有词条 ID 和学习记录保持；仅内置词书的基础释义升级为完整义项；自定义词书覆盖与仅由用户创建的基础词条保留。新查询词只追加到 `word`，不创建词书关系、进度或每日任务。用户主动加入生词本以后才进入原有学习安排。

阅读、全词典搜索和系统收词共用 `LearningService.lookupCandidates()`。`went`、`was` 等纯变形返回 `go`、`be` 的主词头；`found` 与 `saw` 同时保留独立义项和 `find`、`see` 的变形候选，由用户按原文选择。词形候选不代表自动语义消歧。人名也可能与常用词或缩写同形，正文中的人名身份由阅读界面按语境说明，不改写词典的一般释义。

备份仍按词头身份合并：只有被原句、收藏、进度或其他记录引用的查询新词才带入紧凑备份的完整兜底词条；未用过的查询资源无需重复备份。恢复到另一台设备时保留引用，不依赖源设备的数字 ID 一致。

复现：`python3 tools/build_lookup_dictionary.py /path/to/ecdict.csv`。脚本先核对固定 SHA-256，再生成查询资源和 `docs/LOOKUP_DICTIONARY_SOURCE.json`；不改变原五本词书。运行 `node tools/test-lookup-dictionary.cjs` 验证真实 ArkTS 词形索引、SQLite 导入、历史 ID、自定义释义与备份兜底规则。另由阅读内容检查覆盖 18 篇正文和重点词。

### 五本词书资源的转换

词头统一为小写，保留原始五类考试标签。每本书按上游当代词频排名、BNC 排名排序，方便从常用词开始学习；没有缺失或剔除本快照中的这五类标签词。

中文释义使用上游 `translation` 字段的首个非空释义行，避免把多个专业领域释义全部堆到学习卡上。音标来自上游 `phonetic` 字段，添加 `/.../` 显示边界，保留其既有记音方式；上游部分记录使用较旧的记音符号，374 个词头没有音标。应用发音服务读取英文词头，不依赖音标字符串。

本项目另行创作了 314 组中文核心释义、英文短例句及中文译文，源文件为 `tools/data/dictionary_overrides.json`；其中 298 个词头属于所选上游标签集合，作为跨书一致的内容覆盖。其他词不伪造例句，`example` 与 `translation` 同时留空，学习界面应在有例句时才显示这一块。

应用图标 `ciying_icon.svg` 为按照产品方案中「暖黄色背景 + 深灰折叠词卡 + 萤光点」绘制的原创矢量图形。

## 数据结构

```json
{
  "version": 2,
  "books": [
    {
      "id": "cet4",
      "name": "四级 · ECDICT 词书",
      "category": "考试词书",
      "description": "3849 个词 · ECDICT cet4 标签；非现行官方大纲认证。",
      "words": [
        {
          "word": "abandon",
          "phonetic": "/əˈbændən/",
          "meaning": "v. 放弃；抛弃",
          "example": "We abandoned the old plan.",
          "translation": "我们放弃了原来的计划。"
        }
      ]
    }
  ]
}
```

所有词条必须包含五个字段，`word` 与 `meaning` 必须有内容。音标可为空；例句与译文需要同时填写或同时留空。同词跨书的字段必须完全一致，以便共享复习记录。

## 复现与后续升级

1. 从上述固定 URL 下载 CSV 到临时目录，保留上游完整 MIT 声明。
2. 运行 `python3 tools/build_dictionary.py /private/tmp/lexiglow-ecdict.csv`。脚本先验证源文件 SHA-256，随后生成词库和来源清单；不会联网，也不修改任何用户学习记录。
3. 运行 `python3 tools/verify_dictionary.py`，检查结构、数量、空字段、规范词头、书内重复、跨书内容一致性和已有例句的完整性。该校验不替代人工语言校对。

以后接入更新词书时，记录新版本来源、数据许可、各字段和音频的授权范围，更新固定提交/哈希及 `version`。只有官方材料能够证明时才将内容描述为相应年份的完整大纲。词库更新应增加或更新书籍关系，保留已有学习进度及复习记录，不能通过删除用户数据库重新导入。

校验脚本也接受候选词库路径：`python3 tools/verify_dictionary.py /absolute/path/catalog.json`。
