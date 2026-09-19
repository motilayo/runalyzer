# 2. Structural Sequence Parsing and Work-Only Adherence for Interval Workouts

* **Status**: Accepted
* **Date**: 2026-09-18
* **Deciders**: Runalyst Engineering Team

## Context and Problem Statement

When evaluating structured interval workouts (such as Cadence Pyramids or Rhythm Intervals) recorded on Apple Watch, runners reported inaccurate scorecard results. In one 15-minute Cadence Pyramids workout with 4 prescribed work intervals:
- The UI displayed: **"Interval Adherence: 7 of 8 on Target (88%)"**
- The UI rendered 8 pips instead of 4.
- Work cadence was reported as 151 SPM instead of the true 157 SPM.

### Root Cause Analysis

The workout on Apple Watch contained 10 sequential `HKWorkoutActivity` entities:
1. Segment 0: Warmup (180s, 140 SPM)
2. Segments 1–8: 4 Work intervals (60s at 152, 156, 159, 161 SPM) alternating with 4 Recovery intervals (90s at 144, 142, 140 SPM jog, 95 SPM walk)
3. Segment 9: Cooldown (120s, 100 SPM)

The previous implementation in `DrillIntervalEvaluator` used a flat scalar midpoint threshold across all activities:
```
threshold = (min_cadence + max_cadence) / 2.0 = (95 + 161) / 2.0 = 127.5 SPM
```

Because the runner jogged recoveries 1–3 at 140–144 SPM and warmed up at 140 SPM, segments 0 through 7 all exceeded 127.5 SPM and were each classified as separate "Work" intervals.

## Decision Drivers

1. **Physiological Invariant**: In running physiology, recovery intervals are meant for metabolic reset and heart rate recovery. They must **never** be graded for target adherence or counted as work intervals. Recovery cadence is reported strictly as descriptive context (`recoveryCadenceAvg`).
2. **WatchOS Interval Invariance**: WorkoutKit custom workouts follow an invariant structural execution model: an optional Warmup, an interval block of repeating `(Work, Recovery)` pairs, and an optional Cooldown.
3. **Robustness to Runner Behavior**: The evaluation must produce correct results regardless of whether the runner walks (95 SPM), jogs (142 SPM), or stands still during recoveries.

## Considered Options

* **Option 1 (Structural Sequence Parser with Stride-2 Pairing)**: Model the workout as a formal grammar stream. Strip warmup/cooldown bookends based on template iteration count and duration, then group remaining segments into alternating pairs `(Work_i, Recovery_i)` with a stride of 2.
* **Option 2 (Dynamic K-Means / Clustering)**: Cluster segments into 2 cadence clusters (high vs low).
* **Option 3 (Tuned Scalar Threshold)**: Adjust threshold to `max(baselineCadence, (min + max) / 2)`.

## Decision Outcome

Chosen option: **Option 1 (Structural Sequence Parser with Stride-2 Pairing)**.

### Algorithm Specification

1. **Grammar Model**:
   Interval workouts follow the structural grammar:
   ```
   [Warmup] -> (Work + Recovery) x N -> [Cooldown]
   ```
   where `N` is the expected iteration count from `DrillTemplate` (e.g., `N = 4`).

2. **Bookend Stripping**:
   - Total segments `M`:
     - If `M == 2N + 2`: Segment 0 is Warmup, Segment `M - 1` is Cooldown. Both are stripped.
     - If `M == 2N + 1`: Evaluated against `schedule.warmup` duration to determine whether Segment 0 (Warmup) or Segment `M - 1` (Cooldown) is present.
     - If `M == 2N`: No bookends recorded; exactly `N` pairs.
   - For irregular segment counts (e.g. ad-hoc lap presses), Segment 0 is stripped if duration `>= min(100s, warmupSec * 0.6)` and `>= workSec * 1.2`. Trailing segments with cooldown duration after completed pairs are stripped.

3. **Stride-2 Sequence Pairing**:
   The remaining `2N` segments are processed in pairs of two:
   ```
   Pair k = (Segment 2k, Segment 2k + 1)
   ```
   In WorkoutKit structured intervals, `Segment 2k` is Work and `Segment 2k + 1` is Recovery. Each pair produces exactly one `DrillIntervalRep`.

4. **Work-Only Target Adherence**:
   - `isMet` is graded **exclusively on work cadence** (`repWorkCadence`).
   - `totalIntervals = reps.count = N`.
   - `workCadenceAvg` is the mean of work segments.
   - `recoveryCadenceAvg` is the mean of recovery segments.

### Positive Consequences

* **Immune to Recovery Effort**: Whether recovery is a 144 SPM jog or a 90 SPM walk, recovery segments are never graded as work reps.
* **UI Pip Invariance**: A 4-interval drill always renders exactly 4 pips in the UI, matching user expectations.
* **Unified Engine**: Consolidates `HKWorkoutActivity` (Tier 1) and `HKWorkoutEvent` (Tier 2) into a single shared `evaluateSegments` pipeline.

### Negative Consequences / Tradeoffs

* Relies on the drill's duration category (`DrillDuration`) and template schedule to know expected iterations `N`. `Context` was updated to carry `durationCategory`.

## Links and References

* Implementation: `Runalyst/Engine/DrillIntervalEvaluator.swift` (`evaluateSegments`)
* Unit Test: `RunalystTests/RunalystTests.swift` (`testCadencePyramidsWithJoggedRecoveriesDoesNotCreateSpuriousWorkReps`)
* Architectural Rule: `AGENTS.md` (Section 2: Deterministic Math & Directives, Section 3: Working Stats Engine)
