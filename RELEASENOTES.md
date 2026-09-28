# Runalyst v2.2.1 — Interval Corroboration Calibration & Tactical Fatigue Readiness 🏃‍♂️🎯

Runalyst 2.2.1 is a targeted patch release that refines continuous topological interval recognition, safeguards progressive interval sessions against false continuous classification, and introduces a calibrated three-tier fatigue readiness architecture to the AI Tactical Coach.

---

### 🌟 What's New in v2.2.1

#### 1. ⏱️ Topological Interval Corroboration & Terminal Rep Pairing (ADR-0006)
- **Calibrated Multi-Signal Corroboration**: Calibrated active recovery surge validation thresholds (`cadenceDiff >= 5.0` SPM, `hrDiff >= 3.0` BPM) to accommodate cardiac lag, EPOC, and active recovery kinematics without rejecting valid intervals.
- **Dominant Pace Surge Validation**: Added direct recognition for prominent pace surges (`paceDiff >= 30.0` s/km with biometric backing, or `paceDiff >= 45.0` s/km) to capture interval efforts driven primarily by stride extension rather than cadence alone.
- **Terminal Rep Pairing**: Workouts terminating on a final hard interval without a subsequent recovery jog now reliably pair with the preceding recovery phase to validate completion of the final cycle.
- **Progression Pace Variance Guardrail**: Added a pace coefficient of variation guardrail (`cv < 0.09`) to continuous progression detection, preventing high-variance, fast-finishing interval workouts from misclassifying as "Progression Run".
- **SwiftData Fault Safety**: Reinforced detached model context access with safe state checking in `RunRecord`.

#### 2. 🛡️ Three-Tier Tactical Fatigue Readiness & Personalized Baseline Cadence
- **Calibrated Three-Tier Fatigue Architecture**:
  - **Tier 1 (Critical Fatigue / Acute Overload)**: Triggered strictly upon genuine physiological overreaching (3+ heavy workouts in 7 days or back-to-back workouts within 36 hours with verified turnover decay or cardiac drift), prescribing full rest.
  - **Tier 2 (Moderate / Productive Fatigue)**: Identifies standard quality training load (2 heavy workouts, mild turnover decay, or high acute density) and prescribes Zone 2 active aerobic recovery rather than alarmist rest warnings.
  - **Tier 3 (High Readiness)**: Confirms balanced training density and stable biomechanics, priming the athlete for scheduled quality sessions.
- **Personalized Rolling Baseline Cadence**: Prioritizes the runner's authentic 30-day duration-weighted cadence, falling back to 7-day historical windows, preventing arbitrary 160 SPM baseline penalties for natural 152–158 SPM runners.
- **Accurate Telemetry Directives**: Informs the FoundationModels prompt whether turnover declined (`cadenceDelta >= 3.5` SPM) or remained stable during high training density.

---

### 🛠️ Technical Improvements & Architecture
- **Expanded Test Suite**: Test coverage broadened from 101 to 112 automated unit and integration tests across 5 specialized test domains (`RunalystTests`) with 100% pass rate.
- **New Unit Tests**: Added regression coverage for 3-rep terminal interval workouts, pace CV variance guardrails, and tactical coach fatigue tier evaluation.
- **Strict SwiftLint Quality Gate**: 100% compliance across all 48 Swift source files with zero violations under `--strict`.
- **Architectural Documentation**: Standardized design decision codified in `docs/adr/0006-multi-signal-topological-interval-segmentation-and-progression-guardrails.md`.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.2.0...v2.2.1
