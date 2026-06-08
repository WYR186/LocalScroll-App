# LocalScroll iOS — 验收测试执行报告

**执行日期：** 2026-06-08
**被测版本：** branch `claude`，HEAD `a8c80ec`（本次会话新增 6 个提交，见 §6）
**依据文档：** `docs/LocalScroll_iOS_Acceptance_Test.docx`（S-01..S-05 冒烟 + F-01..F-56 功能，共 61 项）
**上一份报告：** `docs/LocalScroll_iOS_Acceptance_Results_2026-06-05.md`（commit `6d58eab`）

---

## 0. 测试环境

| 项 | 实际使用 | 说明 |
|----|----------|------|
| 工具链 | Xcode 26.5 (Build 17F42) · iOS 26.5 SDK | |
| 模拟器 | **iPhone 17 Pro (iOS 26.5)** | 本机 iOS 26.5 runtime 下只有 iPhone 17 系列 / iPhone Air；iPhone 16 Pro 仅有 iOS 18.3.1。17 Pro 是最接近的等价机型（Pro + 灵动岛 + iOS 26.5），并能同时编译 Foundation Models（iOS 26）相关代码路径。 |
| Deploy target | iOS 18.2 | |

### 采用的测试手段
1. **Core 纯算法包**（`project/localScroll_iOS`）—— `swift run CoreTests` 可执行断言套件。
2. **Xcode 全套测试**（`xcodebuild test`，App + Widget 编译 + 单元/适配器/E2E/UITest）—— 真实跑在 iOS 26.5 模拟器。
3. **真实视频端到端提取**（`EndToEndComparisonTests`）—— 跑完整 Fast 管线（AVAsset + Vision OCR + Stitcher），与 Python 基线对齐。
4. **XCUITest 验收 UI 测试** —— 真实驱动 App UI。
5. **xcresult 失败快照分析** —— 取失败时刻无障碍快照 + 截图定位根因。
6. **源码审查** —— Live Activity / 队列 / 设置 / 历史。

### 状态图例
- ✅ **PASS** —— 模拟器/真实视频直接验证。
- 🟢 **PASS（逻辑）** —— 生产代码已实现并由单元测试和/或源码审查证实。
- 🟡 **PARTIAL** —— 部分验证；剩余需真机/交互。
- ⚪ **NEEDS DEVICE** —— 模拟器无法验证（Apple Intelligence / Live Activity 渲染 / 灵动岛 / 后台调度 / OOM / 磁盘 / 内存压力）。

---

## 1. 总体结论

| 维度 | 结果 |
|------|------|
| Core 纯算法套件 `swift run CoreTests` | ✅ **187 checks / 0 失败** |
| 编译（App + Widget + Tests，iOS 26.5 sim） | ✅ **BUILD / TEST SUCCEEDED** |
| Xcode 全套测试 | ✅ **50 个：49 通过 / 0 失败 / 1 跳过** —— `result: Passed` |
| 唯一跳过项 | `LocalScrollUITests.testAcceptanceS02toS05ProcessFromPhotos`（无头 PHPicker 无法稳定提交选择，**设计内 SKIP**） |
| 真实视频提取（Fast，E2E vs Python 基线） | ✅ `iosPipelineMatchesPythonFastBaselineOnRealVideo` 通过 |

**未发现任何产品级功能缺陷。** 上一份报告（06-05）唯一的红项是一个 UI 测试假阴性，本次已查实根因并修复（§3）；06-05 报告记录的 BUG-001（`TranscriptSummaryTests` 断言写法）也已解决——该套件现 9/9 全绿。

---

## 2. 测试结果明细

### 2.1 Core 纯算法包（`project/localScroll_iOS`）

```
LocalScrollCore — Phase iOS-1 parity suite
✓ Types  ✓ Fuzzy  ✓ Dedup  ✓ Stitcher  ✓ Scheduler  ✓ Incremental  ✓ Incremental-parity (vs Python)
checks: 187   failures: 0   ALL PASS ✅
```

### 2.2 Xcode 套件分套结果（iPhone 17 Pro · iOS 26.5）

| 套件 | 通过 | 失败 | 跳过 |
|------|:---:|:---:|:---:|
| AcceptanceLogicTests | 7 | 0 | 0 |
| AdapterPhaseTests | 5 | 0 | 0 |
| EndToEndComparisonTests | 2 | 0 | 0 |
| HistoryAndImportTests | 5 | 0 | 0 |
| PipelinePhaseTests | 10 | 0 | 0 |
| Phase7PolishTests | 1 | 0 | 0 |
| TranscriptCleanupTests | 3 | 0 | 0 |
| TranscriptSummaryTests | 9 | 0 | 0 |
| LocalScrollTests | 1 | 0 | 0 |
| LocalScrollUITests | 5 | 0 | **1** |
| LocalScrollUITestsLaunchTests | 1 | 0 | 0 |
| **合计** | **49** | **0** | **1** |

> `AcceptanceLogicTests` 本次 +3：`historySearchMatchesEditableTitleAndOriginalNameCaseInsensitively`、`historyBlankQueryReturnsEverythingAndTrimsWhitespace`、`historyPresetFilterExcludesOtherPresets`（覆盖本次新增的 History 搜索/筛选逻辑）。

---

## 3. 上一轮红项的定性与修复（UI 测试假阴性）

- **失败用例（06-05 起）：** `LocalScrollUITests.testAcceptanceHistoryAndSettingsTabs()` → `XCTAssertTrue failed - Cache toggle missing`（断言 Settings 的 `Cache Original Videos` 开关）。
- **根因（已查实）：** 从 xcresult 取出失败时刻快照，窗口尺寸为 **874 × 402（横屏）**，截图亦为侧向渲染。Settings 是 `Form`，该开关在第 4 个分区，在仅 402pt 高的横屏里位于屏幕外；**SwiftUI 不会把屏幕外的 Form cell 放进无障碍树**，故裸 `.exists` 查不到。其上方三行（Appearance / OCR Language / Generate Summary）均通过。
- **结论：产品代码无问题**（`SettingsView.swift` 中开关确实存在）；属测试侧脆弱性。
- **修复（仅测试代码）：** 加 `scrollToElement` 上滑兜底，断言前把目标行带进无障碍树；并在 `setUp` 中 `XCUIDevice.shared.orientation = .portrait` 锁竖屏从根上避免横屏假阴性。复跑该用例 **PASS**。

---

## 4. 本次会话的功能改动（均已编译 + 测试 + 提交）

### 4.1 Live Activity（灵动岛 / 锁屏）重设计 — F-46/F-47 相关
- **动机：** 真机反馈灵动岛/通知中心像调试 HUD（直接显示 `Frame 476 of 476 - 38 OCR lines - 15 skipped`）。
- **改动：** `ProcessingActivityAttributes.ContentState` 从自由字符串 `status` 改为**语义化模型** `{ progress, phase: ProcessingPhase, lineCount, detail }`。Widget 自行组织文案：状态动词（`Extracting text` / `Cleaning up` / `Summarizing` / `Done` …）+ `N lines` 副标题；每阶段独立 SF Symbol + 配色；完成/失败/暂停时百分比换成对应图标，灵动岛 keyline 随阶段染色。锁屏改用系统默认材质（自适应深浅色）。
- **范围隔离：** App 内 Extract 队列行的逐帧详细文字（`progressText`）**保持不变**。
- **同步约束：** `ProcessingPhase` + `ContentState` 在 App 与 Widget 两个 target **各一份，必须字节级一致**（跨进程序列化状态），两处已加注释。
- **Summarizing 阶段：** AI 摘要生成期间现会推送 `.summarizing`（由 `willGenerateSummary(for:)` 统一判断，仅当模式开启且 Foundation Model 可用时显示）。

### 4.2 History 搜索 + 画质预设筛选 — F-30 相关（PROGRESS.md 低优项）
- `.searchable` 按可编辑标题或原始文件名匹配（不区分大小写）；下拉菜单按 Fast/Smart/Precise 过滤。
- 区分「搜索无结果」与「预设过滤为空」两种空态；滑动删除走过滤后列表索引。
- 匹配逻辑抽为纯函数 `HistoryFilter.apply(to:query:preset:)`，加 3 个 Swift Testing 单测。

### 4.3 Live Activity Xcode 预览
- 因模拟器不渲染 Live Activity，新增 `#Preview`（锁屏 + 灵动岛 展开/紧凑/极简 × extracting/summarizing/done/paused/failed），可在 Xcode 画布直接核对设计，无需真机。

---

## 5. 模拟器无法覆盖、必须真机补测的项（与 06-05 一致，未闭环）

1. **AI 全家桶（F-23~F-29）** —— 需已下载 Apple Intelligence / Foundation Models 模型；逻辑层（清洗/摘要分块/模式/应用）已 mock 单测覆盖。
2. **Live Activity / 灵动岛视觉（F-46, F-47）** —— 模拟器不渲染；本次重设计代码两端编译通过，**视觉最终验收待真机**（可先看 §4.3 Xcode 预览定稿）。
3. **后台调度 / 后台超时（F-45, F-48, F-49 触发）** —— iOS 调度仅真机。
4. **资源极限（F-04, F-51, F-53, F-54）** —— 4K 长视频 OOM、内存压力、磁盘不足。
5. **整条系统相册「选择并提交」UI（S-02 提交、F-01/F-52 多选）** —— 无头 XCUITest 无法稳定驱动 PHPicker；提取本身由 `EndToEndComparisonTests` + 单元套件独立覆盖。

---

## 6. 本次会话提交（branch `claude`，已推送 `origin/claude`）

| commit | 说明 |
|--------|------|
| `881fe53` | Make Settings UI test robust to off-screen Form rows（§3 修复） |
| `de5a93a` | Redesign Live Activity with a semantic phase model（§4.1） |
| `00577ed` | Add search and quality-preset filter to History（§4.2） |
| `01771bc` | Surface the summarizing phase in the Live Activity（§4.1） |
| `53a233a` | Add Live Activity previews for the Xcode canvas（§4.3） |
| `a8c80ec` | Extract History filter into a testable function and cover it（§4.2） |

---

## 7. 证据 / 复现

```bash
# Core
cd project/localScroll_iOS && swift run CoreTests           # → 187/0

# App 全套（无签名，iOS 26.5 模拟器）
cd Code/iosproject/LocalScroll_Xcode
xcodebuild test -scheme LocalScroll -project LocalScroll.xcodeproj \
  -destination 'platform=iOS Simulator,id=<iOS 26.5 device id>' \
  CODE_SIGNING_ALLOWED=NO                                    # → 50: 49 pass / 1 skip
```

| 产物 | 内容 |
|------|------|
| `/tmp/ls_final2.xcresult` | 本次全套测试结果包（50 项） |
| `LocalScrollUITests/LocalScrollUITests.swift` | 验收 UI 测试（含本次健壮性修复） |
| `LocalScrollWidget/ProcessingLiveActivityWidget.swift` | 重设计的 Live Activity + 预览 |

---
*LocalScroll iOS · 验收执行报告 · 2026-06-08 · branch `claude` @ `a8c80ec`*
