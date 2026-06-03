# Changelog

All notable LocalScroll iOS app changes are tracked here.

## Unreleased - 2026-06-03

### Added

- Added persistent processing checkpoints that save imported working videos and OCR frame samples so interrupted jobs can resume without re-importing or redoing completed base-pass OCR.
- Added automatic restoration of unfinished processing jobs when the app starts or receives a background processing wake.
- Added `beginBackgroundTask` support around active video processing so short jobs can keep running briefly after lock/background.
- Added ActivityKit progress updates for the current video job; this exposes app-side Live Activity state without treating it as a background execution guarantee.
- Added a WidgetKit Live Activity extension with Lock Screen and Dynamic Island progress views for active video processing.
- Added BGProcessingTask registration and scheduling for best-effort long-video checkpoint continuation.
- Added two-stage OCR coverage refinement: each extraction now runs a base pass, records per-frame OCR diagnostics, detects risky intervals, and performs higher-FPS supplemental OCR only inside those intervals.
- Added risk detection for large scroll displacement, discontinuities, low OCR confidence, sudden OCR line drops, weak text overlap, and insufficient vertical bounding-box overlap.
- Added time-ranged video sampling so supplemental passes can decode only the risky video segments.
- Added OCR language settings for Automatic, English, Simplified Chinese, and Traditional Chinese.
- Added tests for bounded OCR concurrency, coverage-refinement backfill, and time-ranged video sampling.
- Added a resume-state test that verifies checkpointed OCR samples are reused instead of reprocessed.

### Changed

- Replaced random-access exact frame extraction with sequential `AVAssetReader` decoding to reduce repeated GOP decoding work on long screen recordings.
- Added bounded concurrent OCR for non-adaptive extraction paths while preserving timestamp order before stitching.
- Changed Vision OCR defaults from a fixed three-language set to automatic detection unless a single preferred language is selected.
- Reduced smart-mode optical-flow cost by running motion analysis on scaled frames and mapping displacement back to original pixels.
- Enabled preset-specific supplemental OCR rates: Fast refines at 6 fps, Smart at 8 fps, and Precise at 12 fps.

### Verified

- `git diff --check`
- `swift run CoreTests` in `/Users/ipanda/Documents/project/localScroll_iOS` — 187 checks, 0 failures
- `xcodebuild -project LocalScroll.xcodeproj -scheme LocalScroll -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing -derivedDataPath /private/tmp/LocalScrollDerived -clonedSourcePackagesDirPath /private/tmp/LocalScrollSPM`
- `xcodebuild test -project LocalScroll.xcodeproj -scheme LocalScroll -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:LocalScrollTests -derivedDataPath /private/tmp/LocalScrollDerived -clonedSourcePackagesDirPath /private/tmp/LocalScrollSPM` — 17 tests passed
