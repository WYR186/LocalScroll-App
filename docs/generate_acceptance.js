const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
        AlignmentType, HeadingLevel, BorderStyle, WidthType, ShadingType,
        PageBreak, VerticalAlign } = require('docx');
const fs = require('fs');

// ─── Colour palette ───────────────────────────────────────────────────────────
const BLUE_HEADER   = "1F4E78";
const BLUE_MID      = "2E75B6";
const GREY_ROW      = "F2F2F2";
const GREEN_PASS    = "E2F0D9";
const ORANGE_WARN   = "FFF2CC";
const RED_FAIL      = "FCE4D6";

// ─── Border helpers ───────────────────────────────────────────────────────────
const thinBorder = { style: BorderStyle.SINGLE, size: 4, color: "CCCCCC" };
const allThin = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };
const boldBorder = { style: BorderStyle.SINGLE, size: 8, color: BLUE_MID };
const allBold = { top: boldBorder, bottom: boldBorder, left: boldBorder, right: boldBorder };

const CM = { top: 80, bottom: 80, left: 120, right: 120 };

// ─── Cell factories ───────────────────────────────────────────────────────────
function hcell(text, w) {
  return new TableCell({
    borders: allBold,
    shading: { fill: BLUE_HEADER, type: ShadingType.CLEAR },
    margins: CM,
    width: { size: w, type: WidthType.DXA },
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", font: "Arial", size: 22 })] })]
  });
}
function cell(text, w, fill, bold = false) {
  return new TableCell({
    borders: allThin,
    shading: { fill: fill || "FFFFFF", type: ShadingType.CLEAR },
    margins: CM,
    width: { size: w, type: WidthType.DXA },
    children: [new Paragraph({ children: [new TextRun({ text, bold, font: "Arial", size: 20 })] })]
  });
}
function statusCell(text, fill, w) {
  return new TableCell({
    borders: allThin,
    shading: { fill, type: ShadingType.CLEAR },
    margins: CM,
    width: { size: w, type: WidthType.DXA },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text, bold: true, font: "Arial", size: 20 })]
    })]
  });
}

// ─── Paragraph helpers ────────────────────────────────────────────────────────
const spacer = new Paragraph({ spacing: { before: 0, after: 200 }, children: [new TextRun("")] });

function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 300, after: 120 },
    children: [new TextRun({ text, bold: true, size: 32, color: BLUE_HEADER, font: "Arial" })]
  });
}
function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 240, after: 100 },
    children: [new TextRun({ text, bold: true, size: 26, color: BLUE_MID, font: "Arial" })]
  });
}
function h3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 180, after: 80 },
    children: [new TextRun({ text, bold: true, size: 24, color: "444444", font: "Arial" })]
  });
}
function body(text) {
  return new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text, font: "Arial", size: 22 })] });
}
function note(text) {
  return new Paragraph({ spacing: { after: 80 }, children: [new TextRun({ text, font: "Arial", size: 20, color: "555555", italics: true })] });
}

// ─── Feature table (F-xx, feature, test steps, pass criteria) ─────────────────
function featureTable(rows) {
  // columns: F-ID(800), Category(1600), Feature Description(3200), Test Steps(5400), Pass Criteria(2560)
  const colWidths = [700, 1600, 2400, 3000, 2460];  // sum = 10160 (content 9360 + some overflow will auto-fit)
  // Let's use 9360 total
  // 700+1500+2300+3100+1760 = 9360
  const cw = [700, 1500, 2300, 3100, 1760];
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: cw,
    rows: [
      new TableRow({ children: [
        hcell("ID", cw[0]),
        hcell("分类", cw[1]),
        hcell("功能说明", cw[2]),
        hcell("测试步骤", cw[3]),
        hcell("验收标准", cw[4])
      ]}),
      ...rows.map((r, i) => new TableRow({ children: [
        cell(r[0], cw[0], i%2 ? GREY_ROW : "FFFFFF", true),
        cell(r[1], cw[1], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[2], cw[2], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[3], cw[3], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[4], cw[4], i%2 ? GREY_ROW : "FFFFFF")
      ]}))
    ]
  });
}

function evidenceTable(rows) {
  const cw = [1800, 1900, 3300, 2360];
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: cw,
    rows: [
      new TableRow({ children: [
        hcell("范围", cw[0]),
        hcell("执行方式", cw[1]),
        hcell("最低证据", cw[2]),
        hcell("状态口径", cw[3])
      ]}),
      ...rows.map((r, i) => new TableRow({ children: [
        cell(r[0], cw[0], i%2 ? GREY_ROW : "FFFFFF", true),
        cell(r[1], cw[1], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[2], cw[2], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[3], cw[3], i%2 ? GREY_ROW : "FFFFFF")
      ]}))
    ]
  });
}

function automationTable(rows) {
  const cw = [1500, 3500, 2200, 2160];
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: cw,
    rows: [
      new TableRow({ children: [
        hcell("阶段", cw[0]),
        hcell("命令 / 操作", cw[1]),
        hcell("归档文件", cw[2]),
        hcell("通过标准", cw[3])
      ]}),
      ...rows.map((r, i) => new TableRow({ children: [
        cell(r[0], cw[0], i%2 ? GREY_ROW : "FFFFFF", true),
        cell(r[1], cw[1], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[2], cw[2], i%2 ? GREY_ROW : "FFFFFF"),
        cell(r[3], cw[3], i%2 ? GREY_ROW : "FFFFFF")
      ]}))
    ]
  });
}

// ─── Bug tracking table ────────────────────────────────────────────────────────
function bugTrackingTable() {
  const cw = [700, 2000, 2400, 2000, 1260, 1000];
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: cw,
    rows: [
      new TableRow({ children: [
        hcell("Bug ID", cw[0]), hcell("功能区", cw[1]), hcell("问题描述", cw[2]),
        hcell("复现步骤", cw[3]), hcell("严重度", cw[4]), hcell("状态", cw[5])
      ]}),
      new TableRow({ children: [
        cell("BUG-001", cw[0], GREY_ROW, true),
        cell("（填写）", cw[1], GREY_ROW),
        cell("", cw[2], GREY_ROW),
        cell("", cw[3], GREY_ROW),
        cell("P1/P2/P3", cw[4], GREY_ROW),
        statusCell("OPEN", RED_FAIL, cw[5])
      ]})
    ]
  });
}

// ─── Main document ────────────────────────────────────────────────────────────
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial", color: BLUE_HEADER },
        paragraph: { spacing: { before: 300, after: 120 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: "Arial", color: BLUE_MID },
        paragraph: { spacing: { before: 240, after: 100 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, font: "Arial", color: "444444" },
        paragraph: { spacing: { before: 180, after: 80 }, outlineLevel: 2 } }
    ]
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [{ level: 0, format: "bullet", text: "•",
          alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 600, hanging: 300 } } } }] }
    ]
  },
  sections: [{
    properties: {
      page: { size: { width: 15840, height: 12240 }, margin: { top: 1080, right: 1080, bottom: 1080, left: 1080 } }
    },
    children: [
      // ── 封面 ──────────────────────────────────────────────────────────────
      new Paragraph({
        alignment: AlignmentType.CENTER, spacing: { before: 600, after: 300 },
        children: [new TextRun({ text: "LocalScroll iOS", bold: true, size: 56, color: BLUE_HEADER })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER, spacing: { after: 200 },
        children: [new TextRun({ text: "功能全景清单 + 测试验收规程", size: 36, color: BLUE_MID })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER, spacing: { after: 800 },
        children: [new TextRun({ text: "版本：commit 6d58eab  |  日期：2026-06-05", size: 22, italics: true })]
      }),
      new Paragraph({ children: [new PageBreak()] }),

      // ── 说明 ──────────────────────────────────────────────────────────────
      h1("0. 阅读说明"),
      body("本文档列出 LocalScroll iOS 的全部功能，并为每项功能提供："),
      body("  • 具体测试步骤（可直接在手机上执行）"),
      body("  • 量化的验收标准（有则通过 / 无则不通过）"),
      body("  • 建议的测试素材"),
      body(""),
      body("测试顺序建议：先完成 §1（冒烟验证），通过后按 §2～§8 逐区深测，最后用 §9 做回归。"),
      body("验收优先级：P1 = 核心功能，P2 = 重要功能，P3 = 增强功能。"),
      note("测试设备：iPhone 15 Pro Max (iOS 26.5)，视频来自「相册」app。"),
      spacer,
      h2("0.1 执行口径与证据要求"),
      body("每轮验收必须区分三类结论：端到端 PASS、自动化/逻辑验证通过、以及真机待测。源码审查不能单独替代端到端 PASS；若系统 picker、Foundation Models、Live Activity、后台调度或资源压力无法在模拟器覆盖，应明确标记为 NEEDS DEVICE，并列出下一步真机步骤。"),
      evidenceTable([
        ["端到端路径", "手工真机或稳定 UI 自动化", "截图/录屏 + xcodebuild 或手工记录 + History/剪贴板证据", "只有按本文档步骤完整完成，才记为 PASS"],
        ["算法/管线", "XCTest + 真实或生成视频", "完整日志、行数、耗时、关键转写片段、测试名称", "可记为 PASS（自动化），但不能替代 UI 入口验收"],
        ["设置/历史/队列", "UI 测试优先；必要时补单元测试", "测试日志 + 截图附件；若仅源码审查需注明 Logic Verified", "未按用户步骤操作时不得写端到端 PASS"],
        ["真机能力", "iPhone 15/16/17 Pro · iOS 26", "真机录屏、系统设置截图、失败/超时日志", "模拟器只可标 PARTIAL 或 NEEDS DEVICE"]
      ]),
      spacer,
      h2("0.2 证据归档规范"),
      body("每次执行创建 docs/acceptance-artifacts/YYYY-MM-DD/，至少包含 build.log、unit.log、ui.log、e2e_fast.log、e2e_blank.log、screenshots/、xcresults/、manual-device-notes.md。报告中引用的所有文件必须位于该目录或可长期保留的位置，不引用 /tmp 作为最终证据。"),
      body("若某项失败或跳过，记录：设备型号、iOS 版本、素材文件名、执行命令、失败截图、失败原因、是否为产品缺陷或环境限制。"),
      spacer,

      // ── §1 冒烟 ─────────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("1. 冒烟测试（Smoke Test）——上手前必过"),
      body("以下 5 项是最基础的端到端路径。全部通过才继续后续深测。"),
      spacer,
      featureTable([
        ["S-01","启动","App 可以正常打开",
         "1. 按下 LocalScroll 图标\n2. 等待至多 3 秒",
         "• 出现 Extract / History / Settings 三 Tab\n• 无崩溃，无空白页"],
        ["S-02","选视频","从相册选一个视频",
         "1. 点「Photos」\n2. 从系统 picker 选一个 60 秒以内的录屏视频\n3. 点「Add」",
         "• 队列中出现该视频名\n• 状态为「clock」待处理"],
        ["S-03","Fast 提取","Fast preset 提取一段文字滚动视频",
         "1. 选 Fast preset\n2. 从 §S-02 继续\n3. 等待完成（进度条走满）",
         "• 状态变为绿色对勾\n• Extract Tab 底部显示 N lines（N > 0）\n• History 中出现该条记录"],
        ["S-04","历史详情","打开提取结果",
         "1. 切到 History Tab\n2. 点击 §S-03 的记录",
         "• 显示缩略图、时长、preset 标签\n• Raw 面板有文字\n• Copy 按钮可用"],
        ["S-05","复制文字","复制 Raw 文本",
         "1. 在历史详情点「Copy」\n2. 打开备忘录粘贴",
         "• 备忘录中出现完整的文字内容，不乱码"]
      ]),
      spacer,

      // ── §2 视频输入 ────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("2. 视频输入（F-INPUT）"),
      body("测试三条输入路径：相册 picker、Files app、缓存重处理。"),
      spacer,
      featureTable([
        ["F-01","输入 / 相册","多选视频同时加入队列",
         "1. 点「Photos」\n2. 长按多选 3 个视频\n3. 点「Add」",
         "• 队列中出现 3 条记录，顺序与选择顺序一致\n• 逐个串行处理，不并行"],
        ["F-02","输入 / Files","从 Files app 导入",
         "1. 点「Files」\n2. 选择一个 .mp4 或 .mov 文件\n3. 确认导入",
         "• 队列中出现该文件，displayName 显示原始文件名\n• 处理后 History 中 originalFileName 与文件名一致"],
        ["F-03","输入 / 文件错误","导入不支持的文件",
         "1. 点「Files」\n2. 选择一个非视频文件（如 .pdf）",
         "• 弹出「Could Not Import Video」alert\n• 队列不变"],
        ["F-04","输入 / 大文件","导入 4K 10 分钟以上视频",
         "1. 从相册选一个 4K 10+ 分钟录屏\n2. 选 Precise preset\n3. 等待完成",
         "• 不 OOM 崩溃\n• 进度条持续推进，不卡死\n• 最终有输出行数 > 0"],
        ["F-05","输入 / 重处理","从 History 再次处理同一视频",
         "1. Settings → 开启「Cache Original Videos」\n2. 处理一个视频\n3. History 详情 → 点「Re-process Video」",
         "• Extract Tab 自动弹回前台\n• 队列中出现同一视频，状态为 pending\n• 重新处理后 History 出现第二条记录"]
      ]),
      spacer,

      // ── §3 提取质量 ─────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("3. 提取质量（F-EXTRACT）"),
      body("核心算法验收。需准备 3 种测试素材："),
      body("  A. 「纯滚动」—— 微博/Twitter feed 慢速上滑录屏，约 30～60s"),
      body("  B. 「停顿+滚动」—— 滚动后停顿阅读再继续，测试 PAUSED 状态"),
      body("  C. 「Zoom/会议字幕」—— 视频会议实时字幕，适合 Caption 模式"),
      spacer,
      featureTable([
        ["F-06","提取 / Fast","Fast preset 基线质量",
         "1. 素材 A，Fast preset，Scroll 模式\n2. 提取完成后查看 Raw",
         "• 行数覆盖视频中≥80%的可见文字段落\n• 无明显大段重复（连续 3+ 行完全一样）"],
        ["F-07","提取 / Smart","Smart preset 智能采样",
         "1. 素材 B，Smart preset\n2. 查看进度文字中的 scroll state",
         "• 进度条出现「PAUSED」「FORWARD」状态切换\n• 停顿期间无多余重复行\n• 总行数 ≥ Fast 的 70%（不因过度跳帧而遗漏）"],
        ["F-08","提取 / Precise","Precise preset 高覆盖率",
         "1. 素材 A，Precise preset\n2. 对比 Fast 结果",
         "• 行数 ≥ Fast 结果的 110%（更密集采样）\n• 处理耗时可接受（不超过视频时长的 3x）"],
        ["F-09","提取 / Caption 模式","Caption 模式去除字幕闪动重复",
         "1. 素材 C，任意 preset，开启「Caption」toggle\n2. 查看 Raw",
         "• 同一句字幕只出现 1 次，不出现逐字显示的中间帧重复\n• 行数比 Scroll 模式明显少"],
        ["F-10","提取 / 中文","中文识别",
         "1. 一段微信/微博中文滚动录屏\n2. Settings OCR Language → Simplified Chinese\n3. 提取",
         "• 中文字符正确识别，不出现乱码\n• 行数覆盖率与英文素材同级别"],
        ["F-11","提取 / 双语","自动语言检测",
         "1. 一段中英混合录屏\n2. OCR Language → Automatic\n3. 提取",
         "• 中英文字符均正确识别，不出现乱码"],
        ["F-12","提取 / 反向滚动","向上滚动后再向下",
         "1. 先向下滚，再向上滚，再继续向下的录屏\n2. Smart preset",
         "• 向上滚动阶段不产生大量重复行\n• 向上部分的内容也完整出现在结果中"],
        ["F-13","提取 / 空结果","静止截图或无文字视频",
         "1. 导入一个 10 秒的无文字黑屏视频\n2. Fast preset",
         "• 处理完成不崩溃\n• 状态显示「0 lines」或「1 lines」\n• History 中出现记录"]
      ]),
      spacer,

      // ── §4 队列管理 ────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("4. 队列管理（F-QUEUE）"),
      spacer,
      featureTable([
        ["F-14","队列 / 暂停当前","暂停正在处理的视频",
         "1. 处理中，点进度条右侧橙色暂停按钮",
         "• 状态变 paused（橙色 pause 图标）\n• 进度值保留，不归零\n• 下一个 pending 视频自动开始"],
        ["F-15","队列 / 恢复","恢复暂停的视频",
         "1. 接上 F-14\n2. 点击绿色播放按钮",
         "• 状态变 processing，进度从上次继续（不从 0 开始）\n• 最终行数与未暂停处理结果相近"],
        ["F-16","队列 / 暂停 pending","提前暂停等待中的视频",
         "1. 队列中有 3 个 pending\n2. 点第 3 个的暂停按钮",
         "• 第 3 个变为 paused，不影响当前处理和第 2 个\n• 第 1/2 处理完后不自动开始第 3 个"],
        ["F-17","队列 / 删除 pending","删除等待中的视频",
         "1. 左划队列行 → Delete\n   或进入 Edit mode → 删除",
         "• 记录从队列移除\n• 不影响当前处理任务"],
        ["F-18","队列 / 删除 processing","删除正在处理的视频",
         "1. 左划正在处理的行 → Delete",
         "• 当前任务立即终止，无 crash\n• 下一个 pending 自动开始"],
        ["F-19","队列 / 排序","拖拽调整顺序",
         "1. 点 EditButton（左上）\n2. 拖拽改变队列顺序\n3. 点 Done",
         "• 顺序按拖拽后生效\n• 处理按新顺序进行"],
        ["F-20","队列 / Cancel All","取消所有任务",
         "1. 处理中，点右上「Cancel All」\n2. 观察队列状态",
         "• 所有 processing/pending 变为 failed(Canceled)\n• isRunning = false，不再自动开始"],
        ["F-21","队列 / Clear Finished","清除已完成项",
         "1. 有多个 done/failed 条目\n2. 点 header 的「Clear Finished」",
         "• done + failed 条目从队列移除\n• pending/processing/paused 保留不受影响"],
        ["F-22","队列 / 重启恢复","App 重启后未完成任务恢复",
         "1. 处理进行到一半，强制关闭 App（从 App Switcher 划掉）\n2. 重新打开",
         "• 队列中出现「Resume ready」状态的任务\n• 恢复处理后进度从断点继续，不从零开始"]
      ]),
      spacer,

      // ── §5 AI 功能 ────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("5. AI 功能（F-AI）—— Foundation Models, iOS 26 Required"),
      note("以下测试需要 iPhone 15 Pro Max iOS 26.5，且设备已下载 Foundation Models 模型（设置 → 通用 → Apple Intelligence）。"),
      spacer,
      featureTable([
        ["F-23","AI / Cleanup 可用性","Extract 页面 AI Cleanup toggle 可用",
         "1. 打开 App\n2. 观察 Extract 页控制栏",
         "• 「AI Cleanup」toggle 显示（iOS 26 才出现）\n• Foundation Models 已下载时 toggle 可点击"],
        ["F-24","AI / Cleanup 提取","提取时开启 AI Cleanup",
         "1. 开启「AI Cleanup」\n2. 处理素材 A（纯英文 60s）",
         "• 处理完成后 History 详情有「Cleaned」面板\n• Cleaned 文字比 Raw 更连贯，标点/大小写修正\n• didChange = true → 详情默认显示 Cleaned"],
        ["F-25","AI / Cleanup 离线","Airplane Mode 下 AI Cleanup",
         "1. 开启飞行模式\n2. 开启 AI Cleanup\n3. 处理视频",
         "• 处理正常完成（AI 用本地 Foundation Models）\n• Cleaned 结果可用，无网络错误"],
        ["F-26","AI / 摘要 - 自动生成","Settings 摘要模式 = After Cleanup",
         "1. Settings → Summary → After Cleanup\n2. 开启 AI Cleanup，处理视频",
         "• 处理完成后，进度条状态出现「Summarizing...」\n• History 详情 Summary 面板有摘要文字\n• summaryGeneratedAt 有日期"],
        ["F-27","AI / 摘要 - 手动生成","History 详情手动触发摘要",
         "1. Settings → Summary → Manual\n2. 处理一个有 Raw 文字的视频\n3. History 详情 → Summary 面板 → 点「Generate Summary」",
         "• 显示进度 spinner 和进度文字\n• 完成后显示摘要段落\n• 「Regenerate」按钮出现"],
        ["F-28","AI / 摘要 - 取消","中途取消摘要生成",
         "1. 点「Generate Summary」\n2. 在生成中途点「Cancel Summary」",
         "• spinner 消失，无 crash\n• 摘要面板回到「No Summary」状态\n• 历史记录不损坏"],
        ["F-29","AI / 摘要 - 重新生成","对同一条记录重新生成摘要",
         "1. 已有摘要的 History 记录 → 点「Regenerate」",
         "• 老摘要被新摘要替换\n• summaryGeneratedAt 更新为当前时间"]
      ]),
      spacer,

      // ── §6 历史记录 ─────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("6. 历史记录（F-HISTORY）"),
      spacer,
      featureTable([
        ["F-30","历史 / 列表","History Tab 显示所有记录",
         "1. 完成至少 3 次提取\n2. 切到 History Tab",
         "• 每条显示：缩略图、视频名、时长、行数\n• 按时间倒序排列"],
        ["F-31","历史 / 详情元数据","历史详情中的元数据准确",
         "1. 打开一条 History 记录",
         "• 显示：视频名、原始文件名、行数、时长（格式 m:ss）、preset 标签、时间戳\n• 数字与实际视频/结果一致"],
        ["F-32","历史 / Raw / Cleaned 切换","Raw/Cleaned 面板切换",
         "1. 使用 AI Cleanup 处理过的视频记录\n2. 点 Cleaned → 点 Raw → 切回",
         "• 文字内容随面板切换变化，不闪烁\n• 选中的文字不随切换丢失"],
        ["F-33","历史 / 重命名","重命名历史记录标题",
         "1. History 详情 → 点铅笔图标\n2. 修改名称 → 点「Save」",
         "• 标题更新，originalFileName 不变\n• 重启 App 后标题依然保持"],
        ["F-34","历史 / 重命名 - 空字符串","保存空名称",
         "1. 重命名 alert 中清空文字 → 点「Save」",
         "• 不保存（原标题不变）\n• 无 crash"],
        ["F-35","历史 / Copy","复制 Raw",
         "1. History 详情，Raw 面板 → 点 Copy",
         "• 剪贴板内容与 Raw 内容完全一致"],
        ["F-36","历史 / Share","分享",
         "1. History 详情 → 点 Share（方块箭头图标）\n2. 选择「备忘录」",
         "• 系统 Share Sheet 出现\n• 备忘录中内容与选中面板文字一致"],
        ["F-37","历史 / 持久化","重启后历史不丢失",
         "1. 完成 3 次提取\n2. 强制关闭并重启 App",
         "• History Tab 显示与之前相同的记录，缩略图/文字不丢失"],
        ["F-38","历史 / 缩略图","缩略图显示正常",
         "1. 浏览 History 列表",
         "• 每条记录有视频第一帧缩略图，不显示空占位符\n• 长按视频名不崩溃"]
      ]),
      spacer,

      // ── §7 设置 ────────────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("7. 设置（F-SETTINGS）"),
      spacer,
      featureTable([
        ["F-39","设置 / 外观 - 深色","深色模式",
         "1. Settings → Appearance → Dark",
         "• 整个 App 立即切换为深色\n• 重启 App 后保持深色模式"],
        ["F-40","设置 / 外观 - 跟随系统","System 模式",
         "1. Settings → Appearance → System\n2. 在系统 Settings 中切换深/浅色",
         "• App 外观随系统同步变化"],
        ["F-41","设置 / OCR 语言 - 简中","指定简体中文",
         "1. Settings → OCR Language → Simplified Chinese\n2. 处理中文录屏",
         "• 处理完成，中文识别正常\n• 处理速度比 Automatic 略快"],
        ["F-42","设置 / 缓存视频","开启/关闭视频缓存",
         "1. Settings → 开启「Cache Original Videos」\n2. 处理一个视频\n3. 查看 History 详情",
         "• 出现「Re-process Video」按钮\n3. 关闭缓存后再处理\n4. 新记录无「Re-process Video」"],
        ["F-43","设置 / 管理缓存","查看并删除缓存",
         "1. 有缓存视频时\n2. Settings → Manage Cached Videos\n3. 左划删除一条",
         "• 列表显示缓存视频名\n• 删除后对应 History 记录的「Re-process」按钮消失\n• 文件占用空间减少"],
        ["F-44","设置 / 摘要模式","三种摘要生成模式",
         "1. Always → 处理一个视频（不开 Cleanup）\n2. After Cleanup → 处理（不开 Cleanup）\n3. Manual",
         "• Always：自动用 Raw 生成摘要\n• After Cleanup（不开 Cleanup）：不自动生成\n• Manual：不自动生成，详情页可手动触发"]
      ]),
      spacer,

      // ── §8 后台与通知 ─────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("8. 后台处理 & Live Activity（F-BG）"),
      spacer,
      featureTable([
        ["F-45","后台 / 短暂后台","处理中切出 App（不超过 3 分钟）",
         "1. 处理进行中\n2. 按 Home 键或滑动进入后台\n3. 等 30 秒后回到 App",
         "• 处理继续或显示已完成\n• 无崩溃\n• 进度/状态与后台前一致"],
        ["F-46","后台 / 锁屏 Live Activity","锁屏进度条",
         "1. 处理进行中\n2. 按电源键锁屏",
         "• 锁屏出现 LocalScroll Live Activity 横条\n• 显示视频名 + 进度百分比"],
        ["F-47","后台 / Dynamic Island","Dynamic Island 进度",
         "1. 处理进行中\n2. 切到另一个 App",
         "• Dynamic Island 显示 LocalScroll 图标和进度\n• 点击 Dynamic Island 可跳回 App"],
        ["F-48","后台 / BGProcessingTask","后台长时处理恢复",
         "1. 处理一个超过 5 分钟的视频\n2. 切到后台\n3. 等待系统调度（连接充电器可触发）",
         "• 系统有机会后台继续处理\n• 回到前台时显示已完成或进度推进\n（注：受 iOS 调度策略影响，可接受「进度暂停」）"],
        ["F-49","后台 / 后台超时暂停","系统终止后台任务",
         "1. 处理长视频时切到后台 > 3 分钟\n2. 系统回收后台资源",
         "• 回到 App 时状态为 paused「Paused — progress saved」\n• 不显示 failed\n• 可手动 resume 继续"]
      ]),
      spacer,

      // ── §9 回归 / 边界 ────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("9. 回归 & 边界条件（F-EDGE）"),
      spacer,
      featureTable([
        ["F-50","边界 / 0 行输出","提取结果完全空",
         "1. 导入纯黑 10s 视频，Fast preset",
         "• 处理完成，状态为 done\n• 显示「0 lines」，不崩溃\n• History 出现记录（thumbnailData 不为空）"],
        ["F-51","边界 / 超长视频","4K 20 分钟以上视频",
         "1. 导入 4K 20 分钟录屏\n2. Precise preset",
         "• 处理不 OOM 崩溃\n• 进度条稳定推进\n• 断点续传可用（参见 F-22）"],
        ["F-52","边界 / 快速连续加入","1 秒内加入 10 个视频",
         "1. 快速多选 10 个视频并 Add",
         "• 队列正确显示 10 条\n• 顺序逐一处理，不并发\n• 无 race condition / 崩溃"],
        ["F-53","边界 / 内存压力","同时打开多个 App 制造内存压力",
         "1. 在 App Switcher 打开 5 个大型 App\n2. 切回 LocalScroll 处理视频",
         "• 处理不被系统直接 kill\n• 如被 kill，重启后 checkpoint 可恢复"],
        ["F-54","边界 / 磁盘空间不足","剩余空间 < 1GB",
         "1. 找一台存储接近满的设备\n2. 尝试处理视频",
         "• 报错清晰（不 crash，不静默失败）\n• 队列状态变为 failed 并有错误说明"],
        ["F-55","边界 / 重复 ID","同一视频处理两次",
         "1. 处理同一视频两次（不 Re-process）",
         "• History 出现 2 条独立记录\n• 两条互不干扰，可分别重命名/删除"],
        ["F-56","隐私 / 全离线","飞行模式全程使用",
         "1. 开启飞行模式\n2. 打开 App，选视频，完成提取，查看 History，分享",
         "• 全程无网络请求\n• 所有功能正常（除 AI 功能视 Foundation Models 而定）"]
      ]),
      spacer,

      // ── §10 性能基准 ──────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("10. 性能基准参考（非硬性验收）"),
      body("以下为 iPhone 15 Pro Max 上的预期参考值，仅供对比参考，不作为 pass/fail 标准。"),
      spacer,
      new Table({
        width: { size: 9360, type: WidthType.DXA },
        columnWidths: [3000, 2100, 2100, 2160],
        rows: [
          new TableRow({ children: [
            hcell("场景", 3000), hcell("Fast", 2100), hcell("Smart", 2100), hcell("Precise", 2160)
          ]}),
          new TableRow({ children: [
            cell("60s 1080p 滚动录屏，处理耗时", 3000, GREY_ROW),
            cell("< 20s", 2100, GREY_ROW), cell("< 35s", 2100, GREY_ROW), cell("< 60s", 2160, GREY_ROW)
          ]}),
          new TableRow({ children: [
            cell("4K 10min 视频，内存峰值", 3000),
            cell("< 400MB", 2100), cell("< 600MB", 2100), cell("< 800MB", 2160)
          ]}),
          new TableRow({ children: [
            cell("启动到 Extract Tab 可交互", 3000, GREY_ROW),
            cell("< 2s", 2100, GREY_ROW), cell("< 2s", 2100, GREY_ROW), cell("< 2s", 2160, GREY_ROW)
          ]})
        ]
      }),
      spacer,

      // ── §11 Bug 跟踪模板 ─────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("11. Bug 跟踪表"),
      body("发现问题时填写此表，提交到项目 GitHub Issues 或 Notion。"),
      spacer,
      new Table({
        width: { size: 9360, type: WidthType.DXA },
        columnWidths: [600, 1500, 1500, 1800, 900, 1200, 1060, 800],
        rows: [
          new TableRow({ children: [
            hcell("ID", 600), hcell("F-ID", 1500), hcell("功能区", 1500),
            hcell("问题描述", 1800), hcell("优先级", 900), hcell("复现步骤", 1200),
            hcell("发现版本", 1060), hcell("状态", 800)
          ]}),
          ...["BUG-001","BUG-002","BUG-003"].map((id, i) =>
            new TableRow({ children: [
              cell(id, 600, i%2?GREY_ROW:"FFFFFF", true),
              cell("", 1500, i%2?GREY_ROW:"FFFFFF"),
              cell("", 1500, i%2?GREY_ROW:"FFFFFF"),
              cell("", 1800, i%2?GREY_ROW:"FFFFFF"),
              cell("P1 / P2 / P3", 900, i%2?GREY_ROW:"FFFFFF"),
              cell("", 1200, i%2?GREY_ROW:"FFFFFF"),
              cell("6d58eab", 1060, i%2?GREY_ROW:"FFFFFF"),
              statusCell("OPEN", RED_FAIL, 800)
            ]})
          )
        ]
      }),
      spacer,

      // ── §12 测试素材建议 ─────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("12. 测试素材准备建议"),
      h2("必备素材（最低 5 条）"),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun({ text: "短英文滚动（30-60s，Twitter/Reddit feed）— 用于 F-06/07/08/09/23-29", font: "Arial", size: 22 })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun({ text: "中文滚动（30-60s，微博/微信朋友圈）— 用于 F-10/11/41", font: "Arial", size: 22 })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun({ text: "停顿+滚动（慢速滚动，中途停下来阅读）— 用于 F-07/12", font: "Arial", size: 22 })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun({ text: "会议字幕（Zoom/Teams 实时字幕）— 用于 F-09 Caption 模式", font: "Arial", size: 22 })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun({ text: "4K 长视频（10 分钟以上录屏）— 用于 F-04/51/53", font: "Arial", size: 22 })]
      }),
      spacer,
      h2("录屏方法（iPhone 15 Pro Max）"),
      body("1. 控制中心 → 屏幕录制（按钮长按可开启麦克风）"),
      body("2. 录制目标 App 的内容滚动操作"),
      body("3. 录制完成后视频自动保存到「相册 → 最近项目」"),
      body("4. 直接在 LocalScroll 中选择即可，无需导出"),
      spacer,

      // ── §13 自动化补测 ───────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      h1("13. 自动化补测与重测流程"),
      body("以下流程用于每次修复后快速补强测试。若其中任一阶段失败，先停止并修复该阶段；不要在基础套件未全绿时发布最终验收结论。"),
      automationTable([
        ["构建", "xcodebuild build-for-testing -project LocalScroll.xcodeproj -scheme LocalScroll -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' CODE_SIGNING_ALLOWED=NO", "build.log", "App / Widget / Tests 全部 TEST BUILD SUCCEEDED"],
        ["单元套件", "xcodebuild test -project LocalScroll.xcodeproj -scheme LocalScroll -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' -only-testing:LocalScrollTests", "unit.log + xcresult", "所有 LocalScrollTests 通过；0 failed / 0 unexpected skip"],
        ["Fast E2E", "LOCALSCROLL_E2E_VIDEO=/path/IMG_0249.MOV xcodebuild test ... -only-testing:LocalScrollTests/EndToEndComparisonTests", "e2e_fast.log", "行数 > 0；中英无乱码；记录耗时与行数"],
        ["空结果 E2E", "LOCALSCROLL_E2E_VIDEO=/path/blank_10s.mp4 LOCALSCROLL_E2E_EXPECT_EMPTY=1 xcodebuild test ... -only-testing:LocalScrollTests/EndToEndComparisonTests", "e2e_blank.log", "行数 = 0；无崩溃；测试明确断言空结果"],
        ["UI 冒烟", "xcodebuild test ... -only-testing:LocalScrollUITests", "ui.log + screenshots/ + xcresult", "S-01、History/Settings、F-39 通过；PHPicker 跳过须转真机补测"],
        ["真机补测", "按 §5 的真机清单执行 AI、Live Activity、后台、资源压力、Photos picker 提交", "manual-device-notes.md + 录屏", "每项有 PASS/FAIL/PARTIAL 与证据链接"]
      ]),
      spacer,
      h2("13.1 本轮重点回归项"),
      body("每次补测至少覆盖：S-02→S-05 真实相册端到端、F-02/F-03 Files 导入错误路径、F-07 Smart PAUSED/FORWARD 状态、F-08 Precise 与 Fast 行数对比、F-09 Caption 专项素材、F-12 反向滚动、F-13/F-50 纯黑空结果、F-39 深色持久化、F-55 重复处理同一视频。"),
      body("若没有对应素材，必须在报告中写明素材缺口；不能把 mock 单测写成真实素材通过。"),
      spacer,

      // ── 页脚 ───────────────────────────────────────────────────────────
      new Paragraph({
        alignment: AlignmentType.CENTER, spacing: { before: 400 },
        border: { top: { style: BorderStyle.SINGLE, size: 4, color: "CCCCCC" } },
        children: [new TextRun({ text: "LocalScroll iOS  •  测试验收文档  •  2026-06-05", font: "Arial", size: 18, color: "888888" })]
      })
    ]
  }]
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = "/Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode/docs/LocalScroll_iOS_Acceptance_Test.docx";
  fs.writeFileSync(outPath, buffer);
  console.log("✓ Acceptance test doc written:", outPath);
}).catch(err => {
  console.error("Error:", err.message);
  process.exit(1);
});
