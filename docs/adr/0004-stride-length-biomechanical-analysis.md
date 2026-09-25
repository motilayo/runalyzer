# 4. Incorporating Stride Length into Biomechanical Analysis and Coaching

* **Status**: Proposed
* **Date**: 2026-09-24
* **Deciders**: Runalyst Engineering Team
* **Consulted**: Architecture & AI Coaching Working Group
* **Informed**: Runalyst Core Contributors

## Context and Problem Statement

In running biomechanics, horizontal running speed is governed by the fundamental velocity equation:

$$\text{Speed} = \text{Cadence} \times \text{Stride Length}$$

Currently, Runalyst captures and analyzes pace, cadence, heart rate, and vertical oscillation across its data ingestion, aggregation (`FramboiseEngine`), and AI coaching (`CoachingEngine` / `RunAnalyzerActor`) pipelines. However, **stride length is completely absent** from persistent storage (`RunRecord`), baseline calculations (`BaselineStats`), and coaching directives:

1. **Permissions without Persistence**: `HealthKitManager.swift` requests read authorization for `HKQuantityTypeIdentifier.runningStrideLength`, and `LiveCoachDTOs.swift` defines `WatchRunRecordDTO.strideLength`. However, `WatchConnectivityManager.saveRunRecord` drops the field, and `HealthKitManager` never queries it during sync.
2. **Blunt Heuristic for Overstriding**: In `RunAnalyzerActor.swift`, overstriding is diagnosed using a single scalar cadence floor:
   ```swift
   if run.workingAvgCadence < 150 {
       directiveContext = "The runner is overstriding (low cadence). Prescribe a drill focused on Form, specifically quickening cadence." + goalSuffix
   }
   ```
   This creates false positives for tall runners with naturally long, efficient strides, as well as easy recovery runs where cadence is lower without braking forces. Conversely, it fails to detect true braking overstriding at cadences between 150–165 SPM.
3. **Missing Running Economy Benchmark (Vertical Ratio)**: Apple Watch captures both vertical oscillation (VO) and stride length. The ratio of the two—**Vertical Ratio** ($\frac{\text{Vertical Oscillation}}{\text{Stride Length}} \times 100\%$)—is the gold-standard metric for running economy, describing the percentage of energy directed upward (wasted bounce) versus forward. Runalyst currently cannot compute this metric.

## Decision Drivers

* **Biomechanical Fidelity**: Distinguish between cadence-driven vs. stride-driven pace adaptations, and detect actual braking overstriding rather than using an arbitrary cadence threshold.
* **Running Economy Scoring**: Enable computation of Vertical Ratio ($VR$), a key metric for form efficiency.
* **Schema Safety & Zero Redundant Compute**: Model changes must use additive optional fields (`Double?`) to avoid breaking existing SwiftData stores, and working averages must be computed during initial ingestion without launch-time repair scans (per `AGENTS.md`).
* **Deterministic Math over LLM Hallucinations**: Calculate baseline deltas, acceleration mechanics, and vertical ratios deterministically in Swift, injecting concise contextual English strings into the FoundationModels prompt (adhering to Apple TN3193 4,096-token limits).
* **Parity Between Watch and Phone**: Ensure both HealthKit historical sync and watchOS Live Coach transfers capture, persist, and analyze stride length identically.

## Considered Options

* **Option 1 (Full-Pipeline Biomechanical Integration)**: Ingest `runningStrideLength` from HealthKit and watchOS, persist `rawAvgStrideLength` and `workingAvgStrideLength` on `RunRecord`, calculate 30-day weighted baselines and Vertical Ratio in Swift, and inject deterministic acceleration/form directives into `RunAnalyzerActor`.
* **Option 2 (Display-Only Ingestion)**: Ingest and store stride length on `RunRecord` for presentation in `RunDetailView`, but omit it from `BaselineStats`, `FramboiseEngine`, and AI coaching.
* **Option 3 (Status Quo)**: Continue using cadence as an indirect proxy for stride dynamics and overstriding.

## Decision Outcome

Chosen option: **Option 1 (Full-Pipeline Biomechanical Integration)**, because stride length completes the velocity equation, eliminates false-positive overstriding diagnoses, and enables Vertical Ratio calculations with minimal token and storage overhead.

---

## Technical Specification & Architecture

### 1. SwiftData Model Changes (`RunRecord.swift`)

Add additive optional properties to `RunRecord` (preserving backwards compatibility without migration plan breaks):

```swift
// Biomechanical Stride Metrics (meters)
var rawAvgStrideLength: Double?
var workingAvgStrideLength: Double?

/// Computed Vertical Ratio (percentage of vertical bounce relative to forward stride)
var verticalRatio: Double? {
    guard let stride = workingAvgStrideLength ?? rawAvgStrideLength, stride > 0,
          let oscCm = workingAvgVerticalOscillation ?? rawAvgVerticalOscillation, oscCm > 0 else {
        return nil
    }
    // oscCm is in centimeters; stride is in meters -> (oscCm / (stride * 100)) * 100 = oscCm / stride
    return oscCm / stride
}
```

### 2. Ingestion Pipeline

* **HealthKit Sync (`HealthKitManager.swift`)**:
  - In `fetchWorkouts()`, execute an `HKStatisticsQuery` for `.runningStrideLength` with unit `HKUnit.meter()`.
  - Extract the average quantity and assign to `rawAvgStrideLength`.
* **Working Stats Engine (`FramboiseEngine.swift`)**:
  - Extract stride length samples per time bucket.
  - Trim idle/dead-stop buckets using existing threshold logic.
  - Return `workingAvgStrideLength: Double?`.
* **Watch Transfer (`WatchConnectivityManager.swift`)**:
  - In `saveRunRecord(from dto: WatchRunRecordDTO, context: ModelContext)`, map `dto.strideLength` to `rawAvgStrideLength` and `workingAvgStrideLength`.

### 3. Baseline & Coaching Integration (`RunAnalyzerActor`)

Extend `BaselineStats` to track 30-day weighted stride length:

```swift
struct BaselineStats {
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double
    let avgOscillation: Double
    let avgStrideLength: Double? // in meters
}
```

#### Deterministic Form & Overstriding Directive

Replace the scalar `cadence < 150` check with multi-signal evaluation:

1. **True Overstriding / High Braking Signature**:
   - `cadence < 155 SPM` AND `verticalRatio > 9.5%` (or vertical oscillation $> 10.0\text{ cm}$ with stride length exceeding baseline by $> 5\%$).
   - Directive: `"The runner shows high vertical bounce relative to stride length (VR: X%), indicating overstriding and braking forces. Prescribe Cadence Pyramids or Rhythm Intervals to quicken turnover."`
2. **Acceleration Mechanics (Cadence vs. Stride Expansion)**:
   - When pace is faster than baseline:
     - If `cadenceDelta > 4` and `strideDelta <= 0.03`: `"Pace increase driven primarily by turnover frequency (+X SPM)."`
     - If `strideDelta > 0.05` and `cadenceDelta <= 2`: `"Pace increase driven by stride extension (+X cm), maintaining steady rhythm."`
     - If both increased: `"Balanced acceleration via both turnover and stride extension."`
3. **Late-Run Stride Collapse (Fatigue)**:
   - When cadence remains stable but pace drops and stride length compresses by $> 8\%$, flag mechanical fatigue rather than pure cardiovascular drift.

### 4. FoundationModels Prompt Injection

To stay strictly within Apple's TN3193 4,096-token limit, compact biomechanical context into `GROUP_B_FORM`:

```text
Current: 168 SPM, 1.18m stride, 8.1cm osc (VR: 6.9%). Baseline: 165 SPM, 1.15m stride, 8.4cm osc (VR: 7.3%). Deltas: +3 SPM, +0.03m stride, -0.3cm osc. Turnover quickened with improved vertical efficiency.
```

---

## Positive Consequences

* **Accurate Overstriding Attribution**: Runners are no longer penalized with overstriding warnings based purely on height or easy pace.
* **Vertical Ratio Availability**: Unlocks a standard, industry-recognized mechanical efficiency metric directly on workout summary screens.
* **Speed Profile Insights**: Gives runners visibility into whether their speed gains stem from cadence turnover or stride power.
* **Zero Breaking Migrations**: Optional properties allow seamless upgrades for existing SwiftData stores.

## Negative Consequences / Tradeoffs

* **Sensor Dependency**: Stride length requires an Apple Watch Series 6 or newer running watchOS 9+, or paired footpod sensors. Workouts imported from third-party GPS units without dynamics will leave these fields `nil`. All downstream logic must handle `Double?` gracefully.
* **Minor Ingestion Query Overhead**: Syncing historical runs requires querying one additional `HKQuantityTypeIdentifier` per workout. Batching and 5s iteration spacing must be preserved as mandated by `AGENTS.md`.

## Pros and Cons of Considered Options

### Option 1: Full-Pipeline Biomechanical Integration

* Good, because it provides holistic form coaching and accurate overstriding diagnostics.
* Good, because it enables Vertical Ratio calculation ($VO / \text{Stride Length}$).
* Good, because it utilizes data already authorized in HealthKit and present in watchOS DTOs.
* Bad, because it requires modifications across ingestion, storage, coaching directives, and UI.

### Option 2: Display-Only Ingestion

* Good, because it is simpler to implement.
* Bad, because AI coaching remains handicapped by the blunt `cadence < 150` heuristic.
* Bad, because `BaselineStats` will not track longitudinal stride length adaptation.

### Option 3: Status Quo

* Good, because zero code changes are required.
* Bad, because overstriding diagnostics will continue producing false positives and hallucinations.
* Bad, because HealthKit read permissions for stride length remain requested but wasted.

---

## Links and References

* [AGENTS.md](../../AGENTS.md) — Section 1 (SwiftData & Concurrency Architecture), Section 2 (FoundationModels Token Limits & Deterministic Directives), Section 3 (HealthKit & Data Management).
* [ADR 0003: Topological Signature Classification for Run Types](0003-topological-signature-classification-for-run-types.md).
* Apple Developer Documentation: [`HKQuantityTypeIdentifier.runningStrideLength`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/3926079-runningstridelength).
