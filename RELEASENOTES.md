# Runalyst v2.1.0 — Topological Classification & Longitudinal Progression 🏃‍♂️📈

Runalyst 2.1 introduces major advancements in biomechanical intelligence, longitudinal training analytics, and guided onboarding. Powered by continuous-topology time-series classification and native Apple Charts, Runalyst delivers deeper physiological insights, refined prescribed drill adherence, and interactive temporal scoping.

---

### 🌟 What's New in v2.1.0

#### 1. 📐 Continuous Topological Signature Classification (ADR-0003)
- **Time-Series Classification Engine**: Replaced legacy scalar heuristics with continuous topological signature matching (`FramboiseEngine.classifyRunTopologically`).
- **Elimination of Fallbacks**: Fully eliminated legacy scalar classification fallbacks in favor of continuous metric curve analysis (cadence stability CV, heart rate kinetics, pace variance).
- **Nuanced Run Type Recognition**: Superior discrimination across *Intervals*, *Tempo Surges*, *Strides*, *Steady Effort*, *Long Run*, and *Recovery Run*.
- **Architectural Documentation**: Standardized design decision formally documented in `docs/adr/0003-topological-signature-classification-for-run-types.md`.

#### 2. 📊 Dashboard Temporal Scoping & Native Apple Charts Progression
- **Multi-Window Temporal Scoping**: Interactive timeframe filters (*7D*, *30D*, *90D*, *1Y*, *All Time*) across the Hero Dashboard to observe trends across distinct training blocks.
- **Longitudinal Progression Visualization**: Native Apple Charts interactive visualizer (`ProgressionChartView`) tracking Cadence, Pace, and Vertical Oscillation over time with smooth area gradients.
- **Run Type Filter Chips**: Streamlined single-select carousel allowing runners to isolate biomechanical progression for specific workout archetypes.
- **Physiological Trends**: Dedicated cardiovascular and aerobic trends view, decoupling global VO2 Max tracking from short-window workout cards.

#### 3. 🎯 Strict Drill Signature Matching & Asymmetric Tolerances
- **Exact Drill Signatures**: Enforced strict interval schedule signatures and cadence bounds to eliminate false-positive automatic drill matching.
- **Guided Workout Protection**: Automatic exemption for structured, guided workouts to preserve manual execution intent.
- **Asymmetric Rhythm Tolerances**: Refined tolerance algorithms accounting for the physiological difference between active work intervals and aerobic recovery.
- **Prioritized Activity Statistics**: Direct extraction and utilization of native Apple Watch activity metrics when available.

#### 4. 🚀 First-Install Onboarding Walkthrough & Spotlight
- **Interactive First-Launch Experience**: Multi-step onboarding tour introducing new runners to AI biomechanical coaching.
- **Background HealthKit Ingestion**: Seamless asynchronous health data synchronization with animated loading feedback.
- **Explainer Spotlights**: Tap-to-inspect (ⓘ) modal explainers educating runners on Cadence CV, Vertical Oscillation, Ground Contact Time, and Aerobic Stability.

---

### 🛠️ Technical Improvements & Architecture
- **Expanded Test Suite**: Test coverage broadened from 69 to 95 automated unit and integration tests across 5 specialized test domains (`RunalystTests`) with 100% pass rate.
- **Modular Test Architecture**: Separated monolithic test files into domain-specific suites (`CardiacGuardrailTests`, `FramboiseEngineTests`, `PrescribedDrillRecognitionTests`, `ProgressionAndTemporalScopingTests`).
- **Strict SwiftLint Quality Gate**: 100% compliance across all 48 Swift source files with zero violations under `--strict`.
- **Refined Working Stats Engine**: Enhanced zero-trimming and duration boundary filtering for uninterrupted steady efforts.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.0.0...v2.1.0
