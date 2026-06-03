# LocalScroll iOS — 进展报告

**日期：** 2026-06-03  
**分支：** `ios-port-phases-2-7`  
**Xcode：** 26.5 (Build 17F42) · iOS 26.5 SDK

---

## 项目结构总览

```
LocalScroll_Xcode/
├── LocalScroll/
│   ├── Adapters/          # 平台适配层（Vision、AVFoundation、CoreImage）
│   ├── Features/          # SelectedMovie（PhotosPicker 导入）
│   ├── Persistence/       # ★ NEW：SwiftData 历史持久化 + 视频缓存
│   ├── Pipeline/          # 提取管线（协调所有 Adapter）
│   ├── Queue/             # ★ NEW：串行队列处理器
│   ├── Settings/          # QualityPreset（Fast/Smart/Precise）
│   ├── Views/             # ★ NEW：History / Settings / Cache 视图
│   ├── ContentView.swift  # ★ 改造为 TabView（Extract/History/Settings）
│   └── LocalScrollApp.swift # ★ 挂 .modelContainer
└── LocalScrollTests/      # XCTest 单元 + 适配器测试
```

`LocalScrollCore` 纯算法 SwiftPM 包（`project/localScroll_iOS`）**未改动**。

---

## 本次新增功能（History + Queue）

### 1. 本地持久化历史（SwiftData）

| 文件 | 说明 |
|------|------|
| `Persistence/HistoryRecord.swift` | `@Model final class HistoryRecord` — 存缩略图(JPEG, @externalStorage)、时长、rawLines/cleanedLines、行数、预设、可选缓存视频文件名 |
| `Persistence/VideoThumbnail.swift` | `VideoThumbnail.generate(url:)` — 复用 `AVAssetImageGenerator` 取 ~10% 处帧生成 JPEG；`DurationFormat.string(_:)` 格式化 `m:ss` / `h:mm:ss` |
| `Persistence/VideoCacheStore.swift` | 管理 `Application Support/CachedVideos/` — `store` / `url(for:)` / `delete` / `allCached` / `totalSizeBytes` |

`LocalScrollApp.swift` 加 `.modelContainer(for: HistoryRecord.self)`。

### 2. 排队处理（Sequential Queue）

| 文件 | 说明 |
|------|------|
| `Queue/QueueItem.swift` | `@ObservableObject`，持有 `.pending/.processing/.done/.failed` 状态 + 进度 + 来源（picker item 或缓存 URL） |
| `Queue/ProcessingViewModel.swift` | 串行队列驱动器：`enqueue(items:)` → 单个 `Task` 顺序执行 `process(_:)` → 写 `HistoryRecord` → 删临时文件。抽取了 `buildPipeline(...)` 供复用；`enqueueCachedVideo(...)` 供 History 发起重新处理 |

**行为要点：**
- 一次选多个视频（`PhotosPicker`，不限数量），入队后逐个处理
- 单条失败标 `.failed` + 继续下一个，不中断整列
- 处理完成自动写入 SwiftData，`Clear`/重启不丢失

### 3. UI 三 Tab 重构

| Tab | 视图 | 说明 |
|-----|------|------|
| **Extract** | `ContentView.swift` → `ExtractView` | 多选 PhotosPicker、Quality/Caption/AI Cleanup 控件、队列列表（状态图标 + 单条进度条）、最近完成字幕预览 |
| **History** | `Views/HistoryListView.swift` → `HistoryDetailView.swift` | `@Query` 按时间倒序；每行：缩略图 + 时长角标 + 行数 + 日期；滑动删除（同步清缓存引用）；详情：缩略图+元数据、Raw/Cleaned 切换、Copy/Share、可选"重新处理" |
| **Settings** | `Views/SettingsView.swift` → `CachedVideoManagerView.swift` | `@AppStorage("cacheOriginalVideos")` 开关（开启后处理时保留原视频）；缓存管理：列表+占用大小+单条/全部删除（同步清 HistoryRecord 引用） |

`ProcessingViewModel` 作为 `@EnvironmentObject` 挂在 `ContentView` 并注入全部子视图，History 详情的"重新处理"可直接把缓存视频推入 Extract 队列并自动切换 tab。

---

## 测试结果

### Core 纯算法包（`project/localScroll_iOS`）

```
LocalScrollCore — Phase iOS-1 parity suite

✓ Types suite
✓ Fuzzy suite
✓ Dedup suite
✓ Stitcher suite
✓ Scheduler suite
✓ Incremental suite
✓ Incremental-parity (vs Python) suite

checks: 187   failures: 0   failing tests: 0
ALL PASS ✅
```

运行命令：`swift run CoreTests`（在 `project/localScroll_iOS`）

### Xcode 单元测试（iPhone 16 Pro Simulator，iOS 26.5）

`xcresult` 汇总：**14 passed · 0 failed · 0 skipped — Passed ✅**

| 测试 | 结果 |
|------|------|
| `LocalScrollTests/example()` | ✅ PASS |
| `AdapterPhaseTests/visionBoundingBoxConvertsToTopLeftPixels()` | ✅ PASS |
| `AdapterPhaseTests/avAssetVideoSourceSamplesContiguousFrames()` | ✅ PASS |
| `AdapterPhaseTests/coreImagePreprocessorScalesFrameForOCR()` | ✅ PASS |
| `AdapterPhaseTests/visionOCRReadsGeneratedStillFrame()` | ✅ PASS |
| `PipelinePhaseTests/scrollPipelineDeduplicatesOverlappingFrames()` | ✅ PASS |
| `PipelinePhaseTests/adaptivePipelineSkipsPausedFrames()` | ✅ PASS |
| `PipelinePhaseTests/captionModeCollapsesIncrementalLines()` | ✅ PASS |
| `PipelinePhaseTests/pipelineCancellationStopsPromptly()` | ✅ PASS |
| `PipelinePhaseTests/fourMinuteEquivalentPipelineCompletesWithoutFrameAccumulation()` | ✅ PASS（已修复） |
| `TranscriptCleanupTests/cleanupResultRetainsRawTranscript()` | ✅ PASS |
| `TranscriptCleanupTests/repeatedCompleteSentenceCollapseKeepsUniqueContent()` | ✅ PASS |
| `TranscriptCleanupTests/conservativeModelResponseFallsBackWhenOutputIsUnrelated()` | ✅ PASS |
| `Phase7PolishTests/privacyManifestDeclaresNoCollectionOrTracking()` | ✅ PASS |

### 预存失败的修复（`PipelinePhaseTests.swift`）

该测试**始终失败**（此前以为是 flaky，实为 `-only-testing` 用 Swift-Testing 路径过滤匹配到 0 个用例而误报 SUCCEEDED；xcresult 实测 `totalTestCount: 0`）。根因是测试 mock 数据的两处缺陷（均在测试侧，非生产代码）：

1. **`lines.count == 480` 失败** — `SequentialOCRBackend` 产出 `"Unique frame 0"` / `"Unique frame 1"`，相邻字符串 `fuzzRatio` ≈ 92% > Stitcher 去重阈值 80%，被当作重叠行折叠成 ~1 行。
   - **修复：** 改用 `distinctSubtitleText(forFrame:)` —— splitmix64 哈希帧号生成 20 字符 base-36 字符串，相邻帧相似度远低于 80%，且确定性可复现。
2. **`fractionCompleted == 1` 失败** — `MockVideoSource.durationSeconds` 返回 `Double(frameCount)=480`，而 `fps=2.0` 使 `expectedFrames=960`，分数封顶 0.5。
   - **修复：** `MockVideoSource` 新增可选 `durationSeconds` 参数（默认 `Double(frameCount)`，不影响其他用例）；4-min 测试传入 `Double(frameCount)/fps = 240`，使 `expectedFrames == 480`、分数到 1。

修复仅触动 `LocalScrollTests/PipelinePhaseTests.swift`，未改动任何 Pipeline/Stitcher/Core 生产代码。该测试现真实跑完 480 帧（5.47s）通过。

### 编译验证

```bash
# 无签名，iOS Simulator
xcodebuild build -scheme LocalScroll -project LocalScroll.xcodeproj \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
# → BUILD SUCCEEDED（仅 1 个预存 deprecation warning，不在新代码中）
```

---

## 当前 Git 状态

```
branch: ios-port-phases-2-7
tracked modified:  ContentView.swift, LocalScrollApp.swift
untracked new:     Persistence/, Queue/, Views/
未提交
```

---

## 下一步

| 优先 | 事项 |
|------|------|
| 高 | 在真机（iPhone 15 Pro Max，UDID `00008130-001614A11AD8001C`）安装并跑一遍多视频排队、历史持久化、缓存管理 |
| 高 | 提交本次改动到 `ios-port-phases-2-7` 分支 |
| 低 | 验证 Foundation Models AI Cleanup 在 Settings > AI 关闭时的降级行为（待 iOS 26 正式版） |
| 低 | 对 History 列表加搜索/筛选（按预设、日期） |
