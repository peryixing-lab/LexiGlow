#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成《词萤（LexiGlow）软件功能丰富与体验升级完整方案》Word 文档 (.docx)
采用纯 Python 标准库 (zipfile, xml.etree.ElementTree) 生成符合 OpenXML 规范的 .docx
"""

import os
import zipfile
import xml.etree.ElementTree as ET

def build_docx(output_path):
    # 1. [Content_Types].xml
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

    # 2. _rels/.rels
    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

    # 3. word/_rels/document.xml.rels
    doc_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

    # 4. word/styles.xml
    styles_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei" w:cs="Calibri"/>
        <w:sz w:val="21"/>
        <w:szCs w:val="21"/>
        <w:lang w:val="en-US" w:eastAsia="zh-CN"/>
        <w:color w:val="262D2A"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:line="280" w:lineRule="auto" w:after="120"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>

  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr>
      <w:spacing w:line="280" w:lineRule="auto" w:after="120"/>
    </w:pPr>
    <w:rPr>
      <w:sz w:val="21"/>
      <w:color w:val="262D2A"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:spacing w:before="360" w:after="200" w:line="360" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>
      <w:b/>
      <w:sz w:val="48"/>
      <w:color w:val="1F2421"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:spacing w:before="100" w:after="360" w:line="300" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>
      <w:sz w:val="26"/>
      <w:color w:val="665000"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="320" w:after="140" w:line="320" w:lineRule="auto"/>
      <w:outlineLvl w:val="0"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>
      <w:b/>
      <w:sz w:val="32"/>
      <w:color w:val="1F2421"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="240" w:after="100" w:line="300" w:lineRule="auto"/>
      <w:outlineLvl w:val="1"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>
      <w:b/>
      <w:sz w:val="26"/>
      <w:color w:val="262D2A"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="180" w:after="80" w:line="280" w:lineRule="auto"/>
      <w:outlineLvl w:val="2"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>
      <w:b/>
      <w:sz w:val="22"/>
      <w:color w:val="454844"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Callout">
    <w:name w:val="Callout"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:pBdr>
        <w:left w:val="single" w:sz="24" w:space="12" w:color="D4A017"/>
      </w:pBdr>
      <w:shd w:val="clear" w:color="auto" w:fill="FAF7EC"/>
      <w:ind w:left="240" w:right="240"/>
      <w:spacing w:before="140" w:after="140" w:line="280" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:sz w:val="20"/>
      <w:color w:val="4A473D"/>
    </w:rPr>
  </w:style>
</w:styles>"""

    # 构建 document.xml 内容助手
    doc_body = []

    def p(text, style="Normal", bold=False, color=None, space_before=None, space_after=None, jc=None):
        p_pr = []
        if style != "Normal":
            p_pr.append(f'<w:pStyle w:val="{style}"/>')
        if jc:
            p_pr.append(f'<w:jc w:val="{jc}"/>')
        sp = []
        if space_before is not None:
            sp.append(f'w:before="{space_before}"')
        if space_after is not None:
            sp.append(f'w:after="{space_after}"')
        if sp:
            p_pr.append(f'<w:spacing {" ".join(sp)}/>')

        p_pr_xml = f"<w:pPr>{''.join(p_pr)}</w:pPr>" if p_pr else ""

        # rPr
        r_pr = []
        if bold:
            r_pr.append("<w:b/>")
        if color:
            r_pr.append(f'<w:color w:val="{color}"/>')
        r_pr_xml = f"<w:rPr>{''.join(r_pr)}</w:rPr>" if r_pr else ""

        # 过滤 xml 特殊字符
        clean_text = (text.replace("&", "&amp;")
                          .replace("<", "&lt;")
                          .replace(">", "&gt;"))

        xml = f'<w:p>{p_pr_xml}<w:r>{r_pr_xml}<w:t xml:space="preserve">{clean_text}</w:t></w:r></w:p>'
        doc_body.append(xml)

    def p_runs(runs, style="Normal", space_before=None, space_after=None, jc=None):
        p_pr = []
        if style != "Normal":
            p_pr.append(f'<w:pStyle w:val="{style}"/>')
        if jc:
            p_pr.append(f'<w:jc w:val="{jc}"/>')
        sp = []
        if space_before is not None:
            sp.append(f'w:before="{space_before}"')
        if space_after is not None:
            sp.append(f'w:after="{space_after}"')
        if sp:
            p_pr.append(f'<w:spacing {" ".join(sp)}/>')
        p_pr_xml = f"<w:pPr>{''.join(p_pr)}</w:pPr>" if p_pr else ""

        runs_xml = []
        for item in runs:
            bold = False
            color = None
            if isinstance(item, tuple):
                text = item[0]
                if len(item) > 1:
                    bold = item[1]
                if len(item) > 2:
                    color = item[2]
            else:
                text = str(item)

            r_pr = []
            if bold:
                r_pr.append("<w:b/>")
            if color:
                r_pr.append(f'<w:color w:val="{color}"/>')
            r_pr_str = f"<w:rPr>{''.join(r_pr)}</w:rPr>" if r_pr else ""
            clean_text = (text.replace("&", "&amp;")
                              .replace("<", "&lt;")
                              .replace(">", "&gt;"))
            runs_xml.append(f'<w:r>{r_pr_str}<w:t xml:space="preserve">{clean_text}</w:t></w:r>')

        doc_body.append(f'<w:p>{p_pr_xml}{"".join(runs_xml)}</w:p>')

    def callout(text):
        p(text, style="Callout")

    def table(headers, rows, col_widths=None):
        # 表格生成
        tbl = ['<w:tbl>',
               '<w:tblPr>',
               '  <w:tblStyle w:val="TableGrid"/>',
               '  <w:tblW w:w="0" w:type="auto"/>',
               '  <w:tblBorders>',
               '    <w:top w:val="single" w:sz="6" w:space="0" w:color="D9D5C7"/>',
               '    <w:left w:val="none"/>',
               '    <w:bottom w:val="single" w:sz="8" w:space="0" w:color="B5B09E"/>',
               '    <w:right w:val="none"/>',
               '    <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E8E5D8"/>',
               '    <w:insideV w:val="none"/>',
               '  </w:tblBorders>',
               '  <w:tblCellMar>',
               '    <w:top w:w="120" w:type="dxa"/>',
               '    <w:left w:w="160" w:type="dxa"/>',
               '    <w:bottom w:w="120" w:type="dxa"/>',
               '    <w:right w:w="160" w:type="dxa"/>',
               '  </w:tblCellMar>',
               '</w:tblPr>']

        # Header Row
        tbl.append('<w:tr>')
        tbl.append('<w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>')
        for idx, h in enumerate(headers):
            w_xml = f'<w:tcW w:w="{col_widths[idx]}" w:type="dxa"/>' if col_widths else '<w:tcW w:w="0" w:type="auto"/>'
            clean_h = h.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            tc = (f'<w:tc><w:tcPr>{w_xml}<w:shd w:val="clear" w:color="auto" w:fill="F4EFCF"/>'
                  f'<w:vAlign w:val="center"/></w:tcPr>'
                  f'<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
                  f'<w:r><w:rPr><w:b/><w:sz w:val="20"/><w:color w:val="262D2A"/></w:rPr>'
                  f'<w:t>{clean_h}</w:t></w:r></w:p></w:tc>')
            tbl.append(tc)
        tbl.append('</w:tr>')

        # Data Rows
        for r_idx, row in enumerate(rows):
            tbl.append('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
            bg = "FAF8EF" if r_idx % 2 == 1 else "FFFFFF"
            for c_idx, cell in enumerate(row):
                w_xml = f'<w:tcW w:w="{col_widths[c_idx]}" w:type="dxa"/>' if col_widths else '<w:tcW w:w="0" w:type="auto"/>'
                clean_c = cell.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                tc = (f'<w:tc><w:tcPr>{w_xml}<w:shd w:val="clear" w:color="auto" w:fill="{bg}"/>'
                      f'<w:vAlign w:val="center"/></w:tcPr>'
                      f'<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
                      f'<w:r><w:rPr><w:sz w:val="19"/><w:color w:val="333333"/></w:rPr>'
                      f'<w:t>{clean_c}</w:t></w:r></w:p></w:tc>')
                tbl.append(tc)
            tbl.append('</w:tr>')

        tbl.append('</w:tbl>')
        doc_body.append("".join(tbl))
        # 加一个空行缓冲
        p("", space_before=60, space_after=60)

    # ========================== 开始组织方案内容 ==========================

    # 文档大标题
    p("词萤 · LexiGlow", style="Title")
    p("背单词软件功能丰富与体验升级完整技术方案 (V1.5 ~ V2.0)", style="Subtitle")

    p_runs([
        ("文档版本：", True, "665000"), ("V1.5 (2026年10月)    ", False, "333333"),
        ("适用平台：", True, "665000"), ("HarmonyOS API 26 / Stage 模型    ", False, "333333"),
        ("核心愿景：", True, "665000"), ("让单词一点一点亮起来", False, "333333")
    ], jc="center", space_after=240)

    callout("【方案定位】本方案基于当前词萤已完成的稳健基石（本地 RDB 事务、纯函数间隔重复算法、五大离线词书、DOCX/CSV导入、API 26 沉浸光感与多端适配），全面贯彻“低压力、强复习、碎片化”的核心哲学。不搞过度游戏化噱头，专注解决学生在“记不住、易混淆、没时间、懒得打开”上的核心痛点，提供立即可落地的丰富演进路线。")

    # 一、项目现状与升级目标
    p("一、 项目现状评估与升级愿景", style="Heading1")

    p("1.1 当前工程已完成基石 (V1.0)", style="Heading2")
    p("在当前代码实现中，词萤已经具备了业界一流的原生离线品质：")
    headers_v1 = ["模块", "当前实现状态", "技术指标 / 核心特点"]
    rows_v1 = [
        ["数据持久化", "已完成", "ArkData RDB (SQLite)，支持单事务原子提交、崩溃完整回滚"],
        ["词库规模", "已完成", "ECDICT 离线五大词书（四级/六级/考研/雅思/托福），26,071 词条、10,689 独立词头"],
        ["复习算法", "已完成", "纯函数调度器，三档自评判断，基础间隔 10m~60d，记忆强度 0~100 分区"],
        ["多格式导入", "已完成", "JSON、CSV、TXT 及 DOCX (原生安全解压与解析)，零权限选择器"],
        ["视觉与交互", "已完成", "API 26 uiMaterial 沉浸光感底栏，大屏 (>=840vp) 顶部导航与自适应网格"],
        ["扩展能力", "已完成", "Core Speech Kit 离线英语 TTS，2x2 与 2x4 桌面卡片，系统代理提醒"]
    ]
    table(headers_v1, rows_v1, [1800, 1600, 5600])

    p("1.2 本次丰富方案的核心目标", style="Heading2")
    p("本次方案旨在将词萤从一个『好用的背词工具』升华为『具有极强黏性与记忆效果的学生学习伙伴』。重点围绕以下四个维度展开：")
    p_runs([("1. 记忆深度深化：", True, "1F2421"), ("解决单词『总记不住、易混淆、只会认不会拼』的问题；")], space_after=60)
    p_runs([("2. 学习场景延伸：", True, "1F2421"), ("覆盖『睡前 30 秒无痛复盘』与『通勤戴耳机磨耳朵』等碎片场景；")], space_after=60)
    p_runs([("3. 鸿蒙原生差异化：", True, "1F2421"), ("深度挖掘锁屏实况窗 (Live View)、自习室键盘全盲操与细腻触觉振动；")], space_after=60)
    p_runs([("4. 品牌情感与激励：", True, "1F2421"), ("将『萤火点亮』隐喻具象化为『词汇星图』，用温暖包容的补光机制代替焦虑断签。")], space_after=140)

    # 二、核心学习体验深化
    p("二、 核心背词体验深化（击穿记忆痛点）", style="Heading1")

    p("2.1 “我为什么总忘这个词？”—— 错词病历与易混辨析", style="Heading2")
    p("技术方案第 17.3 节提出了『总结难词』的设想。在 V1.5 中，将其具体落地为【错词归因诊断】与【易混词对撞卡】：")
    p_runs([("● 反应时长异动预警：", True, "262D2A"), ("利用现存数据表 review_record 中的 response_ms 字段。当单词连续 2 次被评为“模糊”，或反应时长超过 3500ms 时，系统自动标记为“犹豫词”并在卡片右上角显示微光警示；")])
    p_runs([("● 形近/易混词（Confusing Pairs）对比卡片：", True, "262D2A"), ("四六级和考研最令学生困扰的是形近词（如 adapt / adopt / adept、complement / compliment 等）。在词卡下方提供可折叠的【⚠️ 易混辨析】模块，一键并列对比两者发音、中文释义和典型短语；")])
    p_runs([("● 针对性纠错调度：", True, "262D2A"), ("在今日计划完成后，如果该词当天连续答错，次日优先将其排入复习队列首位。")])

    p("2.2 词根词缀与派生星图（Word Family）", style="Heading2")
    p("英语词汇中 70% 的高阶词汇源于常用词根词缀。单点记忆一个词往往孤立脆弱，成串记忆才能形成长期网络。")
    p_runs([("● 词根拆解展示：", True, "262D2A"), ("在单词卡反面增加【词根解析】折叠栏。例如 distract：dis- (分离) + tract (拉/引) -> 将注意力拉走 -> 分散注意力；")])
    p_runs([("● 派生词互联：", True, "262D2A"), ("展示同根词簇（attract, extract, contract, retract）。若派生词已存在于词库中，直接显示该词当前的记忆强度颜色点（红/橙/黄/绿），点击可直接无缝穿透查看。")])

    p("2.3 真题考点与高频搭配（Collocations）", style="Heading2")
    p("ECDICT 词典释义全面但偏书面化。为备考学生增加『真题核心考点』：")
    p_runs([("● 核心动宾搭配：", True, "262D2A"), ("如 abandon -> abandon the attempt (放弃尝试), abandon all hope (放弃一切希望)；")])
    p_runs([("● 考点义项高亮：", True, "262D2A"), ("多义词在考研/四六级中往往只考第 2 或第 3 义项（如 address 考“解决/演说”，novel 考“新颖的”）。系统将考试高频义项置顶加粗高亮展示。")])

    # 三、多元碎片化场景扩展
    p("三、 多元碎片化场景扩展（覆盖全天作息）", style="Heading1")

    p("3.1 晚间 30 秒睡前复盘（Night Flash）", style="Heading2")
    p("方案第 17.4 节提出的睡前复盘，是消除学生复习心理负担的绝佳功能：")
    callout("【设计原则】零操作、零判断、无考核压力。在晚上 21:00 之后，首页出现【晚间 30 秒过电影】入口。仅挑出当天被标记为“不认识”或“模糊”的 Top 3~5 个生词。")
    p_runs([("● 自动轮播：", True, "262D2A"), ("以每张卡片 4 秒的节奏轻柔淡入淡出：单词 -> 核心词性释义 -> 提示词。无需点击认识或不认识，用户只需像看流水一样看一眼；")])
    p_runs([("● 视觉氛围：", True, "262D2A"), ("采用深色暖调界面，避免强光刺激眼睛。结束时呈现一句轻柔问候：『今天的生词已温习完毕，晚安』。")])

    p("3.2 通勤与闭眼“听词磨耳朵”（Audio Flow）", style="Heading2")
    p("充分发挥已集成的 Core Speech Kit 离线英语语音能力，满足排队、挤地铁、晨间洗漱等无法看屏幕的场景：")
    headers_audio = ["时间轴", "播放内容", "设计目的"]
    rows_audio = [
        ["0.0s ~ 1.0s", "英文单词朗读 (1.0x 正常语速)", "听辨单词发音"],
        ["1.0s ~ 2.5s", "静音停顿 1.5 秒", "给大脑留出回忆中文释义的黄金窗口"],
        ["2.5s ~ 4.0s", "中文核心释义朗读", "揭晓答案，建立听觉映射"],
        ["4.0s ~ 6.5s", "英文典型例句朗读", "语境感知与强化"],
        ["6.5s ~ 7.5s", "转场微音效，自动切换下一词", "保持专注节奏，支持单曲循环/随机播放"]
    ]
    table(headers_audio, rows_audio, [1800, 3600, 3600])
    p("系统集成：接入 HarmonyOS 播控中心（MediaSession），在锁屏界面支持上一词、暂停、下一词及蓝牙耳机按键控制。")

    p("3.3 拼写速记挑战（Spell Rush）", style="Heading2")
    p("针对四六级翻译和考研写作『提笔忘字』的痛点：")
    p_runs([("● 题型机制：", True, "262D2A"), ("给出中文释义和首尾字母槽位（如：a _ _ _ _ _ _ e -> acknowledge），用户可从底部的乱序字母气泡中点选，或直接使用软/硬键盘键入；")])
    p_runs([("● 局制短小：", True, "262D2A"), ("每局 5 词，控制在 90 秒内完成。独立练习计分，不影响日常间隔调度算法。")])

    # 四、HarmonyOS 原生深度赋能
    p("四、 HarmonyOS 系统级原生体验深度赋能", style="Heading1")

    p("4.1 锁屏与桌面实况窗（Live View）打通", style="Heading2")
    p("背单词最大的敌人是“应用打开摩擦”。通过鸿蒙实况窗让学习触手可及：")
    p_runs([("● 锁屏胶囊态：", True, "262D2A"), ("在锁屏状态栏和 AOD 息屏常显上，展示当前待背单词与音标。点亮屏幕即可扫一眼；")])
    p_runs([("● 展开卡片交互：", True, "262D2A"), ("锁屏上轻触胶囊展开为轻量单词卡，点击【查看释义】即可翻转，无需解锁手机进入桌面，碎片时间利用率提高 300%。")])

    p("4.2 平板与 2in1 全键盘盲操支持（自习室生产力）", style="Heading2")
    p("项目已在 ResponsiveLayout 中完美支持了 840vp 宽屏和桌面窗口。考研自习室通常配合平板键盘或 2in1 电脑使用，全键盘快捷键能成倍提高吞吐率：")
    headers_kb = ["按键映射", "触发动作", "对应移动端操作"]
    rows_kb = [
        ["Space / Enter", "显示释义 / 翻转卡片", "点击【显示释义】按钮"],
        ["1  或  J", "标记【不认识】(Forget)", "点击底部【不认识】"],
        ["2  或  K", "标记【模糊】(Fuzzy)", "点击底部【模糊】"],
        ["3  或  L", "标记【认识】(Know)", "点击底部【认识】"],
        ["P  或  R", "重播单词发音 (Play Audio)", "点击发音喇叭图标"],
        ["S", "加入 / 取消生词本 (Star)", "点击右上角收藏星标"],
        ["Esc", "暂存进度并退出到首页", "点击左上角返回"]
    ]
    table(headers_kb, rows_kb, [2200, 3800, 3000])

    p("4.3 物理触觉引擎（Haptics Engine）", style="Heading2")
    p("调用 HarmonyOS 系统 Vibrator API，注入真实的物理回馈：")
    p_runs([("● 翻开释义：", True, "262D2A"), ("触发 15ms 微弱阻尼震动，模拟纸质单词卡翻面的细腻手感；")])
    p_runs([("● 标记认识：", True, "262D2A"), ("触发清脆短促的轻快点震，赋予明确的正面反馈；")])
    p_runs([("● 完成当日目标：", True, "262D2A"), ("触发两段式节奏轻震，配合萤光聚拢动效，形成强烈的仪式感。")])

    p("4.4 智慧识屏与全局生词收入插件", style="Heading2")
    p("在华为浏览器或阅读 PDF 时，长按选中生词，系统文本菜单中提供【词萤收词】快捷项。点击后后台无感调用 RDB 将其加入用户生词本，并匹配本地释义。")

    # 五、视觉情感与激励系统进阶
    p("五、 视觉情感化：“词萤”意象与激励进阶", style="Heading1")

    p("5.1 “萤火星图”（Vocabulary Constellation）可视化", style="Heading2")
    p("品牌 Slogan 是『让单词一点一点亮起来』。将掌握的单词抽象为可视化的星图：")
    p_runs([("● 动态星空画布：", True, "262D2A"), ("在统计页可切换【星图视图】。每一个背过的单词是一枚漂浮的微小光点；")])
    p_runs([("● 颜色与光度映射：", True, "262D2A"), ("陌生为微弱冷灰点、模糊为浅橙点、熟悉为淡黄点、掌握为璀璨的萤光金色点；")])
    p_runs([("● 语意连线：", True, "262D2A"), ("同词根或同主题的单词在达到【掌握】时，彼此之间浮现出细腻的淡金连线。用户能切身体会到『脑海中的知识网络正在逐步织密』。")])

    p("5.2 温暖无痛的“补光”机制（告别断签焦虑）", style="Heading2")
    callout("【反焦虑原则】学生极易因为考试、生病或活动断签一两天。强硬的“连续归零”或“收费补签”只会让学生彻底放弃打开应用。词萤采用包容温和的补光逻辑。")
    p_runs([("● 暗淡光点呈现：", True, "262D2A"), ("未学习的日期在日历上显示为“微暗的灰黄圈”，文案提示：『等待重新点亮』；")])
    p_runs([("● 次日超额自然补光：", True, "262D2A"), ("用户次日多学 5 个词或完成复习后，前一天暗掉的光点自动重新亮起。主界面提示：『用今天的光，温暖了昨天遗漏的记忆』，保护学生的坚持动力。")])

    # 六、技术演进与架构落地
    p("六、 技术演进与架构落地设计", style="Heading1")

    p("6.1 数据库架构增量升级方案 (SCHEMA_VERSION = 3)", style="Heading2")
    p("升级过程保持完全的向后兼容，不丢失既有学习进度：")
    headers_db = ["数据表变更", "类型", "字段与作用"]
    rows_db = [
        ["word_etymology (新增)", "新建表", "word_id (PK), root, prefix, suffix, analysis, family_words"],
        ["confusing_words (新增)", "新建表", "id (PK), word_id, paired_word_id, distinction_note"],
        ["word_progress (调整)", "增加字段", "hesitation_count (犹豫次数), last_response_ms (末次耗时)"],
        ["app_meta (配置更新)", "更新键值", "schema_version 更新为 3，记录词根及易混词库版本号"]
    ]
    table(headers_db, rows_db, [2600, 1800, 4600])

    p("6.2 算法演进：向自适应动态调度平滑升级", style="Heading2")
    p("保留 V1.0 纯函数调度的健壮性，同时引入自适应微调参数：")
    p_runs([("● 犹豫惩罚衰减：", True, "262D2A"), ("若 response_ms > 4000ms 且结果为 KNOW，则仅增加 8 点强度（原为 12 点），下次复习时间缩短 20%，防范盲目蒙对；")])
    p_runs([("● 长期稳定性加成：", True, "262D2A"), ("连续 3 次判定为 KNOW 且间隔超过 14 天的单词，步入稳定区，基础间隔倍率由 2.0x 提升至 2.4x。")])

    # 七、分阶段路线图与里程碑
    p("七、 分阶段迭代路线图与里程碑", style="Heading1")

    headers_phase = ["阶段", "周期", "核心交付功能", "用户与技术价值"]
    rows_phase = [
        ["Phase 1: 体验强化", "2 周", "1. 晚间 30 秒睡前复盘卡\n2. 易混词对比展开卡\n3. 2in1/平板全键盘快捷键\n4. 触觉振动引擎集成", "极低重构成本，成倍提升每日背词操作吞吐率与舒适感"],
        ["Phase 2: 场景延伸", "3 周", "1. 后台“磨耳朵”连播模式\n2. 拼写速记挑战 (Spell Rush)\n3. 词汇星图 (Canvas 掌握可视化)", "打破单一视觉背词场景，覆盖听力与拼写全维度"],
        ["Phase 3: 系统深度协同", "3~4 周", "1. HarmonyOS 锁屏与实况窗卡片\n2. 智慧识屏生词本一键收词\n3. 自适应犹豫度间隔算法优化", "打造具备鸿蒙顶级辨识度的旗舰级背单词应用"]
    ]
    table(headers_phase, rows_phase, [1800, 1200, 3200, 2800])

    p("八、 结语", style="Heading1")
    p("『词萤』不仅是一款背单词软件，更是一种安静、克制、温暖的学习陪伴。通过上述方案的层层充实，它在保持纯粹离线、极简轻量核心初衷的同时，能够完美覆盖现代学生从早晨通勤、自习室沉浸到睡前温习的全天候需求，成为鸿蒙生态中真正有口皆碑的标杆作品。")

    # 包装并写入 zip / docx
    full_doc_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    {''.join(doc_body)}
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>"""

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types)
        zf.writestr("_rels/.rels", root_rels)
        zf.writestr("word/_rels/document.xml.rels", doc_rels)
        zf.writestr("word/styles.xml", styles_xml)
        zf.writestr("word/document.xml", full_doc_xml)

    print(f"Successfully generated DOCX at: {output_path}")

if __name__ == "__main__":
    out = os.path.abspath("docs/词萤_LexiGlow_软件功能丰富与体验升级完整方案.docx")
    build_docx(out)
