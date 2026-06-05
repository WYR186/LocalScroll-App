const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, AlignmentType,
        HeadingLevel, BorderStyle, WidthType, ShadingType, PageBreak, VerticalAlign } = require('docx');
const fs = require('fs');

const border = { style: BorderStyle.SINGLE, size: 6, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const headerBorder = { style: BorderStyle.SINGLE, size: 6, color: "2E75B6" };
const headerBorders = { top: headerBorder, bottom: headerBorder, left: headerBorder, right: headerBorder };

const doc = new Document({
  styles: {
    default: {
      document: {
        run: { font: "Arial", size: 24 } // 12pt
      }
    },
    paragraphStyles: [
      {
        id: "Heading1",
        name: "Heading 1",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 32, bold: true, font: "Arial", color: "1F4E78" },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 0 }
      },
      {
        id: "Heading2",
        name: "Heading 2",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 28, bold: true, font: "Arial", color: "2E75B6" },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 1 }
      },
      {
        id: "Heading3",
        name: "Heading 3",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 26, bold: true, font: "Arial", color: "2E75B6" },
        paragraph: { spacing: { before: 160, after: 80 }, outlineLevel: 2 }
      }
    ]
  },
  numbering: {
    config: [
      {
        reference: "bullets",
        levels: [
          {
            level: 0,
            format: "bullet",
            text: "•",
            alignment: AlignmentType.LEFT,
            style: {
              paragraph: { indent: { left: 720, hanging: 360 } }
            }
          }
        ]
      }
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    children: [
      // Title Page
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 800, after: 400 },
        children: [new TextRun({ text: "LocalScroll iOS", bold: true, size: 48, color: "1F4E78" })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 200 },
        children: [new TextRun({ text: "Technical & Status Report", size: 28, color: "2E75B6" })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 600 },
        children: [new TextRun({ text: "June 5, 2026", size: 24, italic: true })]
      }),

      // Executive Summary
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("Executive Summary")]
      }),
      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun("The LocalScroll iOS native port is feature-complete and production-ready for initial device testing. All 7 specification phases have been implemented, along with 4 significant beyond-spec enhancements. The app compiles cleanly, passes 187 core algorithm tests and 17 integration tests, and has been successfully deployed to iPhone 15 Pro Max running iOS 26.5.")]
      }),

      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("The codebase is well-structured with clear separation between pure algorithm logic (Core package) and platform-specific adapters (Vision, AVFoundation, CoreImage). All work is committed and ready for runtime validation on real video content.")]
      }),

      // Page Break
      new Paragraph({ children: [new PageBreak()] }),

      // Table of Contents
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("Table of Contents")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Project Overview")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Completion Status")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Architecture & Design")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Technical Implementation")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Testing & Verification")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Device Deployment")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Known Limitations & Future Work")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Project Overview
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("1. Project Overview")]
      }),
      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun("LocalScroll is a native iOS port of the Python LocalScroll scroll-stitching tool. The app processes videos from the user's photo library to extract and deduplicate text transcripts from on-screen scrolling content.")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "Key Requirements:", bold: true })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("100% on-device computation (no network, works in Airplane Mode)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Pure logic core with zero Apple-media imports")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Photo library input via PhotoKit")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("No telemetry, no cloud APIs")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 400 },
        children: [new TextRun("iOS 26 optimized, iOS 17+ compatible where possible")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Target Device")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("Primary: iPhone 15 Pro Max (iOS 26.5) | Hardware UDID: 00008130-001614A11AD8001C | 512GB Storage")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Completion Status
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("2. Completion Status")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Specification Phases (All Complete)")]
      }),

      createPhaseTable(),

      new Paragraph({
        spacing: { before: 400, after: 200 },
        children: [new TextRun({ text: "Beyond-Spec Enhancements (All Committed):", bold: true })]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "1. History + Sequential Queue Processing", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Persistent history via SwiftData; multi-select video queue; per-item progress tracking")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "2. Appearance & Theme Customization", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Light/Dark/Auto theme toggle in Settings")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "3. Two-Stage OCR Coverage Refinement", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Base pass + risk-driven supplemental pass; preset-specific fps (Fast 6, Smart 8, Precise 12); language selector")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "4. Resumable Checkpoints & Background Processing", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Checkpoint persistence; BGProcessingTask scheduling; Live Activity progress; Dynamic Island widget")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Architecture
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("3. Architecture & Design")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Project Structure")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun("The port follows a two-part architecture:")]
      }),

      new Paragraph({
        spacing: { after: 100 },
        children: [new TextRun({ text: "Core Package (Pure Logic)", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Location: project/localScroll_iOS/")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Zero imports of Vision, AVFoundation, CoreImage, UIKit, or PhotoKit")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Pure algorithms: Types, Fuzzy, Dedup, Stitcher, Scheduler, Incremental")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("187 unit tests passing")]
      }),

      new Paragraph({
        spacing: { after: 100 },
        children: [new TextRun({ text: "App Package (Platform Adapters)", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Location: Documents/Code/iosproject/LocalScroll_Xcode/")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Links Core package via SwiftPM")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Platform-specific adapters + SwiftUI UI")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("17 integration tests passing")]
      }),

      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("This separation ensures the correctness-critical algorithm logic remains testable and portable, while platform integrations focus on iOS-specific capabilities.")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Core Algorithms (Ported from Python)")]
      }),

      createCoreAlgorithmsTable(),

      new Paragraph({
        spacing: { before: 200, after: 400 },
        children: [new TextRun("All algorithms are bit-compatible with the Python reference, with special attention to fuzzy matching (rapidfuzz.fuzz.ratio exact parity) and scheduler motion-state classification.")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Technical Implementation
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("4. Technical Implementation")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Platform Adapters")]
      }),

      createAdaptersTable(),

      new Paragraph({
        spacing: { before: 200, after: 400 },
        children: [new TextRun("Each adapter is a distinct Swift protocol/struct implementing the required interface. The pipeline orchestrates these components while maintaining control flow parity with the Python reference.")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("SwiftUI User Interface")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "3-Tab Navigation:", bold: true })]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Extract Tab: Video selection, preset choice (Fast/Smart/Precise), processing progress")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("History Tab: Persistent extraction results, thumbnail+duration, Raw/Cleaned toggle, Copy/Share")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 400 },
        children: [new TextRun("Settings Tab: Theme, caption mode, language, cache toggle, diagnostic info")]
      }),

      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("ContentView is a TabView with shared ProcessingViewModel (@EnvironmentObject) managing the extraction queue and history persistence.")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Key Features")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "Adaptive Motion-Based Sampling:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Smart preset uses VNGenerateOpticalFlowRequest to detect scroll direction and speed, skipping paused frames and reversing on upward scroll")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "Two-Stage OCR:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Base pass identifies high-risk intervals (large displacement, low confidence, discontinuities); supplemental pass runs at preset-specific fps only in risky zones")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "GPU-Optimized Pipeline:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Sequential AVAssetReader decoding (no redundant GOP re-decode); CoreImage preprocessing on GPU; optical flow on scaled frames")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "Resumable Checkpoints:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Interrupted extractions persist OCR samples and can resume without re-importing video or redoing base-pass OCR")]
      }),

      new Paragraph({
        spacing: { after: 160 },
        children: [new TextRun({ text: "Foundation Models Integration:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Optional on-device LLM cleanup (iOS 26+) and transcript summarization; gracefully degrades on older iOS")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Testing & Verification
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("5. Testing & Verification")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Core Algorithm Tests")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun("187 unit tests covering all pure-logic modules:")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Fuzzy matching (rapidfuzz.fuzz.ratio parity across edge cases)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Deduplication logic (tail-window filtering)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Stitcher (anchor selection, membership filter)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Scheduler (motion state classification: PAUSED/FORWARD/REVERSE/FAST_FORWARD/DISCONTINUITY)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 300 },
        children: [new TextRun("Incremental (caption-collapse post-processor)")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun("Run: swift run CoreTests (in project/localScroll_iOS/)")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("App Integration Tests")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun("17 tests passing in LocalScrollTests (Simulator):")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("End-to-end comparison tests (GPU pipeline correctness)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Adapter phase tests (Vision OCR, motion, preprocessing)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Pipeline phase tests (stitching, scheduling, incremental cleanup)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 300 },
        children: [new TextRun("Coverage refinement tests (base + supplemental pass coordination)")]
      }),

      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("Compile verification: xcodebuild -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO (clean with no warnings)")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Runtime Validation (In Progress)")]
      }),

      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("OCR/stitch quality on real video content")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Motion sign correctness (Smart preset paused-skip behavior)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Foundation Models cleanup in Airplane Mode")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Memory footprint on ~4-min 4K video")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 400 },
        children: [new TextRun("Checkpoint resume on device")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Device Deployment
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("6. Device Deployment")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Build Configuration")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "Xcode Version:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("26.5 (Xcode Command Line Tools fully functional)")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "Signing & Provisioning:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Team: R48B46NC85")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Code Sign Identity: Apple Development (w1824661210@gmail.com)")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Provisioning Profile: iOS Team Provisioning Profile: Aaron-Wang.LocalScroll")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "SDK & Deployment Target:", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Base SDK: iOS 26")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Minimum Deployment Target: iOS 18.2")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Installation on iPhone 15 Pro Max")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun("Device Details:")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Model: iPhone 15 Pro Max (iPhone16,2)")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Hardware UDID: 00008130-001614A11AD8001C")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Current OS: iOS 26.5 (build 23F77)")]
      }),
      new Paragraph({
        spacing: { after: 200 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Storage: 512GB")]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Connection: Wired (USB), paired and developer mode enabled")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "Build & Install Command:", bold: true })]
      }),

      createCodeBlockParagraph("xcodebuild build -scheme LocalScroll -project LocalScroll.xcodeproj \\"),
      createCodeBlockParagraph("  -destination 'platform=iOS,id=00008130-001614A11AD8001C' \\"),
      createCodeBlockParagraph("  -allowProvisioningUpdates -derivedDataPath /tmp/ls_dd"),
      createCodeBlockParagraph(""),
      createCodeBlockParagraph("xcrun devicectl device install app --device 00008130-001614A11AD8001C \\"),
      createCodeBlockParagraph("  /tmp/ls_dd/Build/Products/Debug-iphoneos/LocalScroll.app"),
      createCodeBlockParagraph(""),
      new Paragraph({
        spacing: { after: 400 },
        children: [new TextRun("xcrun devicectl device process launch --device 00008130-001614A11AD8001C Aaron-Wang.LocalScroll")]
      }),

      new Paragraph({
        spacing: { after: 200 },
        children: [new TextRun({ text: "Current Status (2026-06-05):", bold: true })]
      }),
      new Paragraph({
        spacing: { after: 400 },
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("✓ Deployed and running on iPhone 15 Pro Max")]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // Known Limitations
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun("7. Known Limitations & Future Work")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Currently Unverified")]
      }),

      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("OCR transcript quality on real video (compared to Python reference)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Motion estimator sign convention (positive dy = forward scroll)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Smart preset paused-skip behavior in practice")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Foundation Models cleanup correctness in Airplane Mode")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Memory footprint on long 4K videos")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 300 },
        children: [new TextRun("Checkpoint resumption on real device")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Next Steps")]
      }),

      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Test on real screen recordings and photo library videos")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Compare OCR output with Python reference on same test videos")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Profile memory and battery usage under typical workloads")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Validate motion estimation in Smart mode (paused frame detection)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Test background processing resumption with interrupted jobs")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Verify Foundation Models offline capability")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 300 },
        children: [new TextRun("Refinements based on real-world usage feedback")]
      }),

      new Paragraph({
        heading: HeadingLevel.HEADING_2,
        children: [new TextRun("Potential Enhancements")]
      }),

      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Live preview of scroll detection (motion visualization)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Batch export (PDF, Markdown, plaintext)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("iCloud sync of history (respecting privacy constraints)")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Waveform visualization of motion/confidence over time")]
      }),
      new Paragraph({
        numbering: { reference: "bullets", level: 0 },
        spacing: { after: 400 },
        children: [new TextRun("Preconfigured presets for common use cases (Zoom, YouTube, social media)")]
      }),

      new Paragraph({
        spacing: { before: 200 },
        children: [new TextRun("---")]
      }),
      new Paragraph({
        spacing: { before: 200, after: 200 },
        alignment: AlignmentType.CENTER,
        children: [new TextRun({ text: "End of Report", italic: true })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [new TextRun({ text: "Compiled: June 5, 2026", size: 20, italic: true })]
      })
    ]
  }]
});

Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync("/Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode/docs/LocalScroll_iOS_Technical_Report.docx", buffer);
  console.log("✓ Report generated: LocalScroll_iOS_Technical_Report.docx");
});

function createPhaseTable() {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [1200, 3000, 5160],
    rows: [
      new TableRow({
        children: [
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Phase", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Name", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Components", bold: true, color: "FFFFFF" })] })]
          })
        ]
      }),
      createPhaseRow("1", "Core Port + Fuzzy Parity", "Types.swift, Fuzzy.swift, Dedup.swift"),
      createPhaseRow("2", "AVFoundation Frame Extraction", "AVAssetVideoSource, frame sampling"),
      createPhaseRow("3", "Vision OCR Backend", "VisionOCRBackend, text detection"),
      createPhaseRow("4", "Pipeline (Scroll Mode)", "Pipeline.swift, stitching orchestration"),
      createPhaseRow("5", "Motion-Adaptive Sampling", "VisionMotionEstimator, Scheduler"),
      createPhaseRow("6", "iOS 26 Foundation Models", "FoundationModelTranscriptCleaner/Summarizer"),
      createPhaseRow("7", "UI Polish", "SwiftUI ContentView, Settings, History")
    ]
  });
}

function createPhaseRow(phase, name, components) {
  return new TableRow({
    children: [
      new TableCell({
        borders,
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun(phase)] })]
      }),
      new TableCell({
        borders,
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun(name)] })]
      }),
      new TableCell({
        borders,
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun(components)] })]
      })
    ]
  });
}

function createCoreAlgorithmsTable() {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [2000, 2000, 5360],
    rows: [
      new TableRow({
        children: [
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Python Module", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Swift File", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Purpose", bold: true, color: "FFFFFF" })] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("types.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Types.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("BBox, Line, Frame, Transcript data types")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("fuzzy.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Fuzzy.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Indel-distance normalized similarity (bit-exact parity)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("dedup.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Dedup.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Tail-window deduplication primitives")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("stitcher.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Stitcher.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Two-stage stitching (anchor + membership filter)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("scheduler.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Scheduler.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Motion state classification (PAUSED/FORWARD/REVERSE/etc.)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("incremental.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Incremental.swift")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Caption-collapse post-processor")] })]
          })
        ]
      })
    ]
  });
}

function createAdaptersTable() {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [2200, 2200, 4960],
    rows: [
      new TableRow({
        children: [
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Python Adapter", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Framework", bold: true, color: "FFFFFF" })] })]
          }),
          new TableCell({
            borders: headerBorders,
            shading: { fill: "2E75B6", type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun({ text: "Swift Implementation", bold: true, color: "FFFFFF" })] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("video_ffmpeg.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("AVFoundation")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("AVAssetVideoSource (sequential AVAssetReader)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("ocr_vision.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Vision")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("VisionOCRBackend (VNRecognizeTextRequest)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("motion_opencv.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Vision")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("VisionMotionEstimator (VNGenerateOpticalFlowRequest)")] })]
          })
        ]
      }),
      new TableRow({
        children: [
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("preprocess.py")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("Core Image")] })]
          }),
          new TableCell({
            borders,
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [new TextRun("CoreImagePreprocessor (perspective, contrast, glare)")] })]
          })
        ]
      })
    ]
  });
}

function createCodeBlockParagraph(text) {
  return new Paragraph({
    spacing: { after: 0 },
    children: [new TextRun({
      text: text,
      font: "Courier New",
      size: 20,
      color: "333333"
    })]
  });
}
