# Runalyst v2.2.0 — Stride Biomechanics & Dual-Scope Sync Lifecycle 🏃‍♂️⚡

Runalyst 2.2 brings deep biomechanical stride analysis and an overhauled dual-scope synchronization architecture to on-device running intelligence. With native Apple Watch stride length telemetry, dynamic overstriding detection, and isolated single-run refresh lifecycles, Runalyst delivers faster, safer, and more nuanced AI coaching than ever before.

---

### 🌟 What's New in v2.2.0

#### 1. 📏 Biomechanical Stride Length Analytics & Overstriding Detection (ADR-0004)
- **Native Stride Length Telemetry**: Extracted directly from Apple Watch `HKQuantityTypeIdentifier.runningStrideLength` with seamless metric (meters) and imperial (feet/inches) formatting.
- **Dynamic Overstriding & Vertical Ratio**: Calculates running stride ratio (vertical oscillation / stride length) to identify bounding, excessive ground impact, and kinetic energy loss.
- **Cadence–Stride Dynamic Interplay**: Evaluates how cadence interacts with stride length across paces, distinguishing rhythm stability from overstriding-induced fatigue.
- **AI Coaching Engine Integration**: FoundationModels coaching engine enhanced to synthesize stride length observations, form cues, and tailored drills (Cadence Pyramids, Strides, Rhythm Intervals).
- **8-Card Biomechanical Grid**: Upgraded workout detail metrics to an 8-card responsive layout displaying Average Pace, Cadence, Vertical Oscillation, Ground Contact Time, Stride Length, Heart Rate, Elevation, and Aerobic Efficiency.

#### 2. 🔄 Dual-Scope Refresh & HealthKit Sync Lifecycle (ADR-0005)
- **Decoupled Refresh Scopes**: Architecturally separates global macro-sync from single-run micro-refresh, eliminating expensive historical database re-scans when inspecting a single run.
- **Micro-Scope Run Detail Refresh**: Pull-to-refresh on `RunDetailView` re-queries the authentic `HKWorkout`, updates SwiftData in-place, and re-analyzes coaching insights without locking or resetting other runs.
- **User Correction Preservation**: Micro-refresh strictly preserves user manual classification corrections (`TrainingCorrection`) and custom drill links (`userLinkedDrill` / `userUnlinkedDrill`).
- **Macro-Scope Dashboard Pull-to-Refresh**: Re-queries global VO2 Max, recalculates 30-day baseline biometrics, invalidates temporal headline caches, and triggers macro readiness coaching.
- **Task Safety & Cancellation Handling**: Gracefully handles pull-to-refresh cancellation during SwiftUI view re-renders, preventing duplicate concurrent background tasks.

---

### 🛠️ Technical Improvements & Architecture
- **Expanded Test Suite**: Test coverage broadened from 95 to 101 automated unit and integration tests across 5 specialized test domains (`RunalystTests`) with 100% pass rate.
- **New Unit & Integration Tests**: Added rigorous test suites for stride length conversions, schema persistence, vertical ratio math, and dual-scope sync lifecycle execution in `HealthKitManagerTests`, `FramboiseEngineTests`, and `RunRecordModelAndSchemaTests`.
- **Strict SwiftLint Quality Gate**: 100% compliance across all 48 Swift source files with zero violations under `--strict`.
- **Architectural Standards Enforced**: Codified ADR-0004 and ADR-0005 guidelines directly into `AGENTS.md` and updated ADR indices.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.1.0...v2.2.0
