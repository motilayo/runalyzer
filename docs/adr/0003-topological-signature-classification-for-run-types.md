# 3. Topological Signature Classification for Run Types

* **Status**: Accepted
* **Date**: 2026-09-24
* **Deciders**: Runalyst Engineering Team

## Context and Problem Statement

The run classification engine in `FramboiseEngine.classifyRun()` misclassifies continuous steady-effort runs as "Fartlek" when the runner's natural warmup-to-cruise-to-fade pacing arc produces aggregate variance metrics that cross scalar thresholds. On September 24, 2026, a 32:46 outdoor run at 7'03"/km average pace and 154 SPM average cadence was classified as "Fartlek" despite:

- The on-device AI coaching engine (`CoachingEngine`) correctly identifying it as a steady effort with controlled heart rate and improving cadence.
- Apple Fitness rating the effort as "6 — Moderate."
- Kilometre splits showing a simple inverted-U pacing arc (7'31" → 6'42" → 7'31") with no repeated surges.

### Root Cause Analysis

The current Phase 1 Structural Gate in `FramboiseEngine.classifyRun()` uses two scalar Coefficients of Variation to decide whether a run is intermittent (Fartlek or Intervals) or continuous:

```swift
let isIntermittentCandidate = cadenceCV >= 0.025 && cv >= 0.07

if isIntermittentCandidate {
    if cv >= 0.12 || cadenceCV >= 0.038 {
        return "Intervals"
    } else {
        return "Fartlek"
    }
}
```

The Coefficient of Variation compresses an entire time series into a single scalar by computing σ/μ. This compression **destroys all temporal ordering information**. Two fundamentally different workout morphologies can produce identical CV values:

- **Workout A (Steady Effort with warmup/fade)**: A smooth inverted-U curve — slow start, sustained plateau, tired finish. Cadence is broadly stable with a natural late-run dip (e.g., 155 → 148 SPM in the final kilometre from fatigue).
- **Workout B (True Fartlek)**: 5–6 intentional surges to 170+ SPM alternating with 140 SPM recovery jogs.

Both can produce `cadenceCV ≈ 0.028` and `cv ≈ 0.08`. But Workout A has **zero** alternating surge-and-recovery oscillation cycles, while Workout B has **five or more**. The scalar CV cannot distinguish between them.

The specific failure mode on the reported run:
1. **Pace CV crossed 0.07**: The 49-second spread between the warmup split (7'31"/km) and peak split (6'42"/km) pushed pace variance past the 7% threshold across 30-second rolling windows.
2. **Cadence CV crossed 0.025**: Late-run fatigue dropped cadence to 148 SPM in the final kilometre while the middle kilometres held 155–156 SPM, pushing cadence CV just above 2.5% (a standard deviation of only ±3.85 SPM at 154 SPM average).
3. Neither metric was extreme enough for "Intervals" (`cv >= 0.12` or `cadenceCV >= 0.038`), so the engine fell into the `else` branch: **"Fartlek"**.
4. **Phase 2 and Phase 3 were never evaluated**. Had the run reached Phase 3's Continuous Intensity Matrix, it would have been correctly classified as "Steady Effort" (total intensity ≈ 55–62, not Recovery, not Easy, not Tempo).

This is structurally identical to the problem solved in [ADR-0002](0002-structural-sequence-parsing-for-interval-workouts.md): a flat scalar threshold misclassifying physiologically distinct workout structures because it cannot inspect temporal morphology.

## Decision Drivers

1. **Physiological Invariant**: Every run type possesses a distinct topological time-series signature that is independent of runner experience level or absolute pace. A Fartlek *must* contain repeated intentional surge-and-recovery alternations. A steady effort *must not*. This structural property is invariant — no amount of scalar threshold tuning can replicate it.
2. **Eliminating False Positives at the Root**: Adjusting scalar thresholds (e.g., raising `cadenceCV` from `0.025` to `0.036`) only shifts the failure boundary without eliminating it. A different runner's warmup arc or a hillier course would eventually produce a new false positive at the new threshold.
3. **Architectural Alignment**: `DrillPatternRecognizer` already performs topological cycle detection for structured drills (Strides, Cadence Pyramids, Rhythm Intervals, Tempo Surges) with multi-signal corroboration, minimum duration guards, and cadence contrast requirements. The general classifier should use the same proven pattern, not a separate scalar heuristic.
4. **Classifier-Coaching Consistency**: The AI coaching engine (`CoachingEngine`) and the run classifier (`FramboiseEngine`) must agree. The coaching engine evaluates aggregate baseline deltas and produces a single deterministic directive. The classifier must arrive at a structurally compatible classification.

## Considered Options

* **Option 1 (Topological Signature Classification)**: Replace the scalar CV gate with a three-layer architecture: (1) count actual surge/recovery oscillation cycles in the smoothed time series with multi-signal corroboration, (2) sub-classify intermittent runs by cycle regularity, (3) sub-classify continuous runs by intensity matrix and trend morphology.
* **Option 2 (Raised Scalar Thresholds)**: Increase the `cadenceCV` threshold from `0.025` to `0.036` and `cv` from `0.07` to `0.095`.
* **Option 3 (ML-Only Classification)**: Rely exclusively on the CoreML `RunalystClassifier` and remove `FramboiseEngine` classification.

## Decision Outcome

Chosen option: **Option 1 (Topological Signature Classification)**, because it eliminates the root cause (information destruction from scalar compression) rather than moving the failure boundary, and it unifies the classifier with the proven architecture in `DrillPatternRecognizer`.

### Algorithm Specification

The new `classifyRun` method accepts the full `[BucketData]` time series (smoothed 30-second overlapping windows) in addition to the existing aggregate scalars. Classification proceeds through three layers:

#### Layer 1: Structural Gate — Oscillation Cycle Count

Determines whether a run is **continuous** (single sustained effort) or **intermittent** (alternating surges and recoveries).

1. **Smoothing**: Apply a 2-bucket (30-second) sliding-window average to the cadence time series to suppress GPS and sensor noise. This matches the existing smoothing in `DrillPatternRecognizer.recognizeDrill()`.

2. **Cycle Detection via Zero-Crossing**: Compute the deviation of each smoothed cadence value from the session mean. Count the number of zero-crossings (transitions from above-mean to below-mean or vice versa). Each pair of consecutive crossings represents one potential oscillation cycle.

3. **Multi-Signal Corroboration**: A detected cadence cycle only counts as a **valid surge-recovery oscillation** if at least 2 of 3 signals corroborate the transition:
   - **Cadence**: Surge phase averages ≥ 8 SPM above recovery phase.
   - **Pace**: Surge phase pace is ≥ 15 sec/km faster than recovery phase.
   - **Heart Rate**: Surge phase HR averages ≥ 5 BPM above recovery phase (accounting for ~15s physiological lag; compare surge HR to the preceding recovery's HR).

4. **Minimum Duration Guards**: Each surge and recovery phase must satisfy minimum durations to exclude momentary environmental disruptions:
   - Surge phase ≥ 15 seconds
   - Recovery phase ≥ 20 seconds

5. **Decision**:
   - `validCycleCount < 3` → **Continuous Run** → proceed to Layer 3.
   - `validCycleCount >= 3` → **Intermittent Run** → proceed to Layer 2.

**Rationale for ≥ 3 cycles**: A single broad pacing arc (warmup → cruise → fade) produces 0–1 peaks. A run with one mid-run hill or traffic stop produces at most 1–2 peaks. Only deliberate, repeated speed play or structured intervals produce ≥ 3 distinct oscillation cycles. This threshold is a physiological invariant: no amount of environmental noise on a continuous run produces 3+ corroborated surge-recovery alternations.

#### Layer 2: Intermittent Sub-Classification — Cycle Regularity Score

Distinguishes between **Intervals** (structured, metronomic) and **Fartlek** (organic, variable).

1. Collect the durations of all validated surge (work) phases and recovery phases from Layer 1.

2. Compute the **Cycle Regularity Score**:
   ```
   workDurationCV  = σ(work_durations) / μ(work_durations)
   recoveryDurationCV = σ(recovery_durations) / μ(recovery_durations)
   regularityScore = 1.0 - ((workDurationCV + recoveryDurationCV) / 2.0)
   ```

3. **Decision**:
   - `regularityScore >= 0.65` → **"Intervals"** (consistent rep timing indicates structured workout).
   - `regularityScore < 0.65` → **"Fartlek"** (variable surge lengths indicate informal speed play).

**Rationale**: Structured intervals from WorkoutKit or coached sessions produce near-identical work and recovery durations (e.g., 60s work / 90s rest × 4). Fartleks are freeform by definition — the runner surges "when they feel like it" — producing high variance in phase durations. This metric directly measures the structural distinction rather than relying on aggregate pace/cadence variance.

#### Layer 3: Continuous Sub-Classification — Trend Morphology + Intensity Matrix

For runs confirmed as continuous (< 3 oscillation cycles), classification proceeds through structural archetypes followed by the intensity matrix.

**3a. Trend Morphology (Progression Run Detection)**:

Replace the current single linear-regression slope test (`slope < -0.225`) with a **quintile monotonicity test**:

1. Divide the run's smoothed pace time series into 5 equal-duration segments (quintiles).
2. Compute the mean pace of each quintile: `Q1, Q2, Q3, Q4, Q5`.
3. Count the number of strictly faster transitions: where `Q[i+1] < Q[i]` (lower sec/km = faster pace).
4. **Decision**: If ≥ 4 of the 5 quintiles show monotonic acceleration AND the final quintile `Q5` is the fastest AND `durationMinutes >= 20.0` → **"Progression Run"**.

**Rationale**: A true progression run *must* get continuously faster through the session, finishing at peak pace. The current slope test can be triggered by a single fast split at the end (e.g., a sprint finish on a steady run). The quintile monotonicity test requires sustained, distributed acceleration across the entire session — a structural invariant of the progression archetype.

**3b. Structural Archetypes (Volume)**:

Unchanged from current implementation:
- `durationMinutes >= 68.0 && slope > -0.20 && zone4 < 0.45` → **"Long Run"**

**3c. Continuous Intensity Matrix**:

Unchanged from current implementation. Operates on the weighted combination of Zone 4 score (45%), HR strain score (35%), and pace effort score (20%):
- `totalIntensity < 22.0 && zone4 <= 0.03 && durationMinutes < 35.0` → **"Recovery Run"**
- `totalIntensity < 48.0 && zone4 <= 0.20` → **"Easy Run"**
- `totalIntensity >= 72.0 && zone4 >= 0.50 && durationMinutes >= 20.0` → **"Tempo Run"**
- Otherwise → **"Steady Effort"**

### Signature Changes to `classifyRun()`

The method signature expands to accept the smoothed bucket time series:

```swift
func classifyRun(
    buckets: [BucketData],       // smoothed 30-second overlapping windows (required)
    cv: Double,                  // retained for Phase 3 (Long Run archetype)
    slope: Double,               // retained for Phase 3 fallback
    zone4: Double,
    durationMinutes: Double,
    cadenceCV: Double = 0.0,     // retained for ModelManager guardrails
    averageHR: Double? = nil,
    paceDelta: Double? = nil,
    hrDelta: Double? = nil
) -> String
```

**Clean V2 Migration (No Legacy Fallbacks)**: Because V2 is currently live only on TestFlight and has not yet been deployed to the public App Store, forcing backward compatibility for scalar-only callers is unnecessary. `classifyRun()` and `ModelManager.predictRunType()` strictly require `buckets: [BucketData]`. The legacy scalar-only heuristic (`cadenceCV >= 0.025 && cv >= 0.07`), which was the root cause of the misclassification bug, has been completely eliminated from the codebase rather than preserved as a fallback. All callers and unit tests provide the bucket time series directly.

### Impact on ModelManager CoreML Guardrails

The structural guardrails in `ModelManager.predictRunType()` currently use `cadenceCV < 0.025` to override CoreML Fartlek/Intervals predictions. These guardrails are updated to use pure topological cycle logic:

1. Pass the `[BucketData]` array into `ModelManager.predictRunType()`.
2. Replace scalar overrides with: if `validCycleCount < 3`, override any CoreML Fartlek/Intervals prediction with the `FramboiseEngine` weighted classification.
3. If `validCycleCount >= 3 && regularityScore >= 0.65`, override continuous CoreML predictions with "Intervals".

### Positive Consequences

* **Root Cause Elimination**: Continuous runs with natural warmup/fade arcs can never be classified as Fartlek, regardless of how high their scalar CV values are, because they produce 0 corroborated oscillation cycles.
* **Level-Agnostic**: A beginner jogging at 145 SPM and an elite running at 185 SPM follow the same topological signatures. No absolute-value thresholds are involved in the structural gate.
* **Noise-Immune**: Multi-signal corroboration and minimum duration guards prevent traffic stops, GPS jitter, hill crests, and intersection turns from creating phantom cycles.
* **Fartlek/Intervals Distinction Improved**: Cycle regularity directly measures the structural property that distinguishes the two intermittent types (consistent vs. variable rep timing), rather than relying on aggregate variance proxies.
* **Progression Run Accuracy**: Quintile monotonicity prevents sprint finishes on steady runs from triggering false Progression Run classifications.
* **Classifier-Coaching Alignment**: The structural gate produces classifications that are structurally compatible with the coaching engine's deterministic directive logic.
* **Architectural Unification**: The classifier and `DrillPatternRecognizer` share the same time-series analysis philosophy (cycle detection, segmentation, multi-signal corroboration), reducing conceptual fragmentation.

### Negative Consequences / Tradeoffs

* **Expanded Method Signature**: `classifyRun()` now requires the `[BucketData]` time series in addition to aggregate scalars. All call sites (`HealthKitManager`, `ModelManager`) must be updated to pass the overlapping windows through.
* **Computational Cost**: Cycle detection adds an O(N) pass over the smoothed bucket array. For a typical 30-minute run with 15-second buckets (N ≈ 120 buckets, ~60 overlapping windows), this is negligible.
* **Quintile Monotonicity is Stricter**: Some progression runs with a brief early plateau (e.g., steady first 10 minutes then progressive acceleration) may not satisfy 4-of-5 quintile monotonicity. The linear slope test is retained as a secondary fallback for these cases.

## Pros and Cons of the Options

### Option 1: Topological Signature Classification

* Good, because it eliminates the root cause (information destruction) rather than shifting the failure boundary.
* Good, because oscillation cycle count is a physiological invariant, not a tunable threshold.
* Good, because it unifies the classifier with the proven `DrillPatternRecognizer` architecture.
* Good, because multi-signal corroboration makes it robust to single-signal environmental noise.
* Bad, because it requires passing the bucket time series through to `classifyRun()`, expanding the method signature.

### Option 2: Raised Scalar Thresholds

* Good, because it is a minimal code change (two constant adjustments).
* Bad, because it only shifts the failure boundary — a different runner's warmup arc or hillier course will eventually produce a new false positive at the new thresholds.
* Bad, because it does not address the fundamental information loss from scalar compression.
* Bad, because the "correct" threshold values are empirically fragile and will require repeated tuning as training data evolves.

### Option 3: ML-Only Classification

* Good, because it delegates classification entirely to a trained model.
* Bad, because the CoreML model is also trained on the same scalar features (`cv`, `cadenceCV`, etc.) and exhibits the same failure mode — it predicted Fartlek for the same run. Structural guardrails are still needed.
* Bad, because removing `FramboiseEngine` classification eliminates the deterministic fallback for devices where CoreML is unavailable.
* Bad, because ML models are opaque and harder to audit for physiological correctness than explicit structural algorithms.

## Links and References

* Root cause incident: September 24, 2026 — 32:46 outdoor run at 7'03"/km misclassified as "Fartlek" despite AI coaching insight identifying it as steady effort.
* Current implementation: `Runalyst/Engine/FramboiseEngine.swift` (`classifyRun`)
* CoreML guardrails: `Runalyst/Engine/ModelManager.swift` (`predictRunType`)
* Existing signature matching: `Runalyst/Engine/DrillPatternRecognizer.swift` (`recognizeDrill`, `detectTempoSurges`)
* Related ADR: [ADR-0002 — Structural Sequence Parsing for Interval Workouts](0002-structural-sequence-parsing-for-interval-workouts.md)
* Architectural rules: `AGENTS.md` (Section 2: Deterministic Math & Directives — "Mathematical computations... must be completely deterministic and computed locally in Swift")
