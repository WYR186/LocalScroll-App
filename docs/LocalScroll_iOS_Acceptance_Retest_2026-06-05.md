# LocalScroll iOS — 补强验收测试报告

**日期：** 2026-06-05  
**设备：** iPhone 17 Pro Max Simulator · iOS 26.5  
**目的：** 修正首次报告中的证据缺口，补强测试手册，并重新执行可在模拟器覆盖的项目。

## 1. 本轮改动

| 范围 | 内容 |
|------|------|
| 测试手册 | `LocalScroll_iOS_Acceptance_Test.docx` 新增执行口径、证据归档规范、自动化补测流程、重点回归项；同步更新 `docs/generate_acceptance.js` |
| 单元测试 | 修复摘要分块 trim 断言；新增反向滚动、空结果、preset/OCR/外观/重复历史记录独立性测试 |
| E2E 测试 | `EndToEndComparisonTests` 增加自动发现真实素材、纯黑视频空结果用例、空/非空断言 |
| 证据归档 | 新建 `docs/acceptance-artifacts/2026-06-05-rerun/`，保存 build/unit/e2e/ui 日志与 xcresult |

## 2. 重新执行结果

| 项 | 结果 | 证据 |
|----|------|------|
| Build for testing | PASS | `acceptance-artifacts/2026-06-05-rerun/build.log`；尾部 `TEST BUILD SUCCEEDED` |
| `LocalScrollTests` | PASS | `unit-fixed.log`；完整套件 `TEST SUCCEEDED` |
| 真实视频 E2E | PASS | `e2e-fixed.log`；`iosPipelineMatchesPythonFastBaselineOnRealVideo()` 约 39s；转写归档 `ios_vision_fast.txt`，205 行 |
| 纯黑视频 E2E | PASS | `e2e-fixed.log`；输入 `localscroll_blank_10s.mp4`；`blankVideoProducesEmptyTranscript()` 约 27s；测试断言 transcript 为空 |
| UI 验收 | PASS with expected skip | `ui.log` / `ui.xcresult`；S-01、History/Settings、F-39 通过；S-02→S-05 因 headless PHPicker 未提交被明确 SKIP |
| 手册渲染 QA | PASS | `render/LocalScroll_iOS_Acceptance_Test.pdf`，抽查新增证据页和自动化页无截断 |

## 3. 本轮新增覆盖

| 验收点 | 补强方式 |
|--------|----------|
| BUG-001 单测失败 | 已修复测试断言，完整 `LocalScrollTests` 全绿 |
| F-12 反向滚动 | 新增 `smartPipelineCommitsReverseScrollFrames()`，确认 Smart/commitReverse 会保留反向滚动新内容 |
| F-13/F-50 空结果 | 新增 `blankVideoPipelineCompletesWithZeroLines()` + 纯黑视频 E2E |
| F-08/F-41/F-39/F-55 配置契约 | 新增 `AcceptanceLogicTests` 覆盖 preset、OCR 语言、外观、重复历史记录独立性 |
| 证据可审计性 | 本轮日志、xcresult、转写文件、手册渲染件均归档到项目内 |

## 4. 仍未闭环

| 项 | 当前状态 | 下一步 |
|----|----------|--------|
| S-02→S-05 相册完整 UI 链路 | 模拟器 headless PHPicker 未提交，UI 测试明确 SKIP | 需真机或交互式控制跑 Photos → Add → queue → process → History → Copy |
| F-01/F-52 多选提交 | 同受 PHPicker 限制 | 真机补测多选 3/10 个视频 |
| F-02/F-03 Files UI 路径 | 逻辑/类型覆盖，未驱动系统 Files UI | 真机或可控 UI 环境补测 |
| F-07/F-08/F-09 真实素材质量对比 | 逻辑覆盖；未用停顿、Precise 对比、字幕专项素材量化 | 准备专项素材后补跑行数/重复率/耗时对比 |
| AI / Live Activity / 后台 / 资源压力 | 模拟器不可完整验证 | iOS 26 真机补测 |

## 5. 关键证据路径

- `docs/acceptance-artifacts/2026-06-05-rerun/build.log`
- `docs/acceptance-artifacts/2026-06-05-rerun/unit-fixed.log`
- `docs/acceptance-artifacts/2026-06-05-rerun/e2e-fixed.log`
- `docs/acceptance-artifacts/2026-06-05-rerun/ui.log`
- `docs/acceptance-artifacts/2026-06-05-rerun/ios_vision_fast.txt`
- `docs/acceptance-artifacts/2026-06-05-rerun/localscroll_blank_10s.mp4`
- `docs/acceptance-artifacts/2026-06-05-rerun/xcresults/`
- `docs/acceptance-artifacts/2026-06-05-rerun/render/`
