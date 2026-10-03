# Runalyst v2.3.0 — 11-Profile Taxonomic Classifier, Workout Timelines & Drill Readout Modal 🏃‍♂️🧬

Runalyst 2.3 is a major release introducing continuous 11-profile taxonomic workout classification, interactive workout phase timelines, bespoke sports-science biomechanical illustrations, and an interstitial mental preparation drill readout modal.

---

### 🌟 What's New in v2.3.0

#### 1. 🧬 11-Profile Taxonomic Classification Engine (ADR-0008)
- **15-Dimensional Feature Vectors**: `FramboiseEngine` extracts multi-resolution sliding-window features—analyzing acceleration gradients, peak cadence clustering, elevation correlation, and stop-to-run transition dynamics.
- **New Biomechanical Profiles**: Adds high-accuracy detection for *Pyramid Workouts* (ascending/descending interval structures), *Hill Repeats* (elevation–cadence gradient coupling), and *Urban Traffic Runs* (frequent pause recovery cycles) alongside Intervals, Tempo Surges, Strides, Steady Effort, Long Run, Recovery Run, Progression Run, and Fartlek.
- **Retrained CoreML Model**: CoreML `RunalystClassifier.mlmodel` retrained on authentic multi-runner time-series datasets, boosting classification accuracy to 98.26%.
- **Continuous vs. Intermittent Topological Guardrails**: Safeguards continuous tempo and progression efforts against misclassification under transient speed spikes.

#### 2. ⏱️ Workout Phase Timeline Visualizer
- **Proportional Phase Geometry**: `WorkoutPhaseTimelineView` visualizes warmups, hard surges, recovery intervals, and cooldowns with proportionally scaled horizontal blocks.
- **Embedded Everywhere**: Integrated into `DrillPrimerCardView`, `DrillCardView`, and the main dashboard for quick pre-run visualization.
- **Adaptive Color Coding**: Visual feedback across warmup (amber), work surges (emerald), recoveries (sky blue), and cooldowns (indigo).

#### 3. 🧘 Interstitial Mental Preparation Readout Modal
- **Comprehensive Drill Readiness**: `DrillInterstitialReadoutView` delivers an expandable half-sheet modal before starting a prescribed drill.
- **Structured 5-Point Readout**: Presents Target Cues, Biomechanical Focus, Phase Breakdown, Execution Strategy, and Effort Bands.
- **Dynamic Duration Scaling**: Seamlessly scales work and rest cycles across 5-minute, 10-minute, and 15-minute presets.
- **Direct Apple Watch Export**: One-tap handoff sends customized interval workouts directly to Apple Watch WorkoutKit.

#### 4. 🏃 Kinematic Stride Illustrations & Overstride Biomechanics
- **Sports-Science Kinematics**: Bespoke royalty-free anatomical illustrations contrasting optimal elastic recoil against high-braking overstride.
- **3-Pillar Overstride Logic**: Evaluates overstride risk as a physical conjunction of low cadence, excessive stride length, and elevated ground contact time.
- **Kinematic Cues & Apple Watch Bridge**: Actionable cues (*“Quick off the ground”*, *“Run on ice”*, *“Drive through glutes”*) paired with wrist-based inertial ranges.

#### 5. 📱 App Store Screenshot Packages & Media Assets
- **Multi-Form Factor Previews**: High-resolution iPhone (1284x2778, 1242x2688) and iPad (2048x2732, 2064x2752) App Store presentation assets.
- **Promo Video Showcase**: Refined visual tour demonstrating live cadence deltas, 30-day baselines, and local AI coaching.

---

### 🛠️ Technical Improvements & Architecture
- **Expanded Test Suite**: Broadened test coverage from 112 to 137 automated unit and integration tests across 7 specialized test domains (`RunalystTests`) with 100% pass rate.
- **Golden Telemetry Fixtures**: Added authentic golden fixtures for Pyramids, Hill Repeats, Urban Traffic, and Interstitial Drill Readouts.
- **Strict SwiftLint Quality Gate**: 100% compliance across all 57 Swift source files with zero violations under `--strict`.
- **Architectural Documentation**: Standardized design decisions codified in `docs/adr/0008-feature-vector-extraction-and-taxonomic-classification-engine.md`.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.2.1...v2.3.0
