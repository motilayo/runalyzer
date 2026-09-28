# 6. Multi-Signal Topological Interval Segmentation and Progression Guardrails

* **Status**: Proposed
* **Date**: 2026-09-28
* **Deciders**: Runalyst Engineering Team
* **Consulted**: Engineering, AI Coaching
* **Informed**: iOS Team

## Context and Problem Statement

On September 28, 2026, a 31:24 outdoor run consisting of three structured work intervals (~5–6 min each at ~5'05"–5'30"/km, 280–301W, 168–175 SPM) separated by 2–3 minute recovery jogs (at ~7'00"–7'46"/km, 195–210W, 142–150 SPM) and preceded by a relaxed warm-up was misclassified by Runalyst as a **"Progression Run"**.

Despite the runner executing an intentional interval session with distinct power square waves, pace surges, and ground contact time drops, the engine failed to classify it as **"Intervals"**.

### Root Cause Analysis

Investigation identified five interrelated structural failures across `FramboiseEngine` and `ModelManager`:

1. **Cadence-Only Global Mean Zero-Crossing (`FramboiseEngine.extractOscillationCycles`)**:
   Phase segmentation into candidate surges vs. recoveries relied exclusively on comparing smoothed cadence to the session-wide arithmetic mean:
   ```swift
   let isSurge = smoothed[index] >= meanCadence
   ```
   In progressive interval workouts or workouts with an easy warm-up, early intervals are run at lower cadences (e.g. 158–162 SPM) than later intervals (e.g. 172–175 SPM). Because the global average is dragged up by the late-run efforts, early surges hover near or below the global mean, causing zero-crossing segmentation to fragment or miss the early work intervals.

2. **Active Recovery & Cardiac Lag Corroboration Rigidities**:
   Corroboration required >= 2 of:
   - Cadence delta >= 8.0 SPM
   - Pace delta >= 15.0 sec/km
   - HR delta >= 5.0 BPM
   In workouts where runners pace intervals primarily via stride length (e.g. 0.85m to 1.1m) and perform active recovery jogs (rather than walking or standing still), cadence only increases by 5–7 SPM and heart rate only dips 2–4 BPM due to excess post-exercise oxygen consumption (EPOC). Despite a massive 90–135 sec/km pace difference, both cadence (< 8) and HR (< 5) failed, causing true intervals to be discarded.

3. **Terminal Interval Recovery Pairing Deadlock**:
   When a workout ends immediately upon completing the final interval (e.g. 3 work intervals separated by 2 recoveries), the final work interval has no succeeding recovery phase (`index + 1 >= phases.count`). If the preceding recovery was already claimed by the prior cycle, the final interval could not pair with any recovery, capping total cycles at 2 (< 3).

4. **Progressive Intervals Trapping in Quintile Progression**:
   When intervals progress in speed (e.g. Warmup ~7:30/km -> Rep 1 ~5:30/km -> Rep 2 ~5:15/km -> Rep 3 ~5:05/km), averaging across five time quintiles produces monotonic pace acceleration (Q1 > Q2 > Q3 > Q4 > Q5), satisfying `evaluateQuintileProgression`. Without checking pace variance (`cv < 0.09`), intermittent workouts masquerade as smooth continuous progression runs.

5. **Incomplete Enumerated Override Whitelist (`ModelManager.swift`)**:
   `ModelManager.predictRunType` invoked CoreML (`RunalystClassifier`), which was trained on scalar aggregates and predicted `"Progression Run"`. The intermittent structural guardrail in `ModelManager.swift` attempted to protect against continuous misclassifications using an incomplete whitelist:
   ```swift
   if (targetClass == "Steady Effort" || targetClass == "Easy Run" || targetClass == "Recovery Run" || targetClass == "Tempo Run") && cycles.count >= 3
   ```
   `"Progression Run"` was omitted from this list, creating a bypass where CoreML's prediction could never be overridden.

## Decision Drivers

1. **Adaptive Baseline Segmentation**: Interval detection must account for warm-up drift without depending on a single static session-wide threshold.
2. **Physiological Corroboration Realism**: Corroboration must reflect active recovery kinematics and cardiac lag, recognizing dominant pace surges (>= 30 s/km).
3. **Terminal Interval Preservation**: Workouts terminating on the final work interval must be capable of completing cycle corroboration against the preceding recovery.
4. **Variance-Gated Progression**: "Progression Run" must require true continuous pace progression with low pace variance (`cv < 0.09`), preventing intermittent workouts from qualifying.
5. **Topological Ground Truth Dominance**: When topological cycle detection validates >= 3 corroborated intermittent cycles, no continuous classification label from CoreML or heuristics may supersede it.

## Decision Outcome

Chosen solution incorporates:
1. **Rolling Local Baseline Segmentation**: Segments candidate phases using a rolling local window in `extractOscillationCycles`.
2. **Calibrated Multi-Signal & Dominant Pace Corroboration**: Cadence threshold calibrated to >= 5.0 SPM, HR threshold to >= 3.0 BPM, and dominant pace surges (>= 30.0 s/km with biometric support or >= 45.0 s/km) validated.
3. **Terminal Rep Pairing**: Allows terminal work intervals to evaluate against the immediate preceding recovery interval.
4. **Variance-Guarded Progression**: Progression classification requires `cv < 0.09` in addition to monotonic quintile acceleration, preventing interval sessions from misclassifying.
5. **Universal Structural Gate**: `ModelManager.swift` overrides any continuous prediction with `Intervals` or `Fartlek` whenever `cycles.count >= 3`.

### Positive Consequences

* Progressive intervals and threshold intervals with gradual warm-ups are reliably segmented and classified as "Intervals".
* Warm-ups and cool-downs will no longer cause steady or interval runs to be mislabeled as "Progression Run".
* The structural invariant is preserved: CoreML predictions cannot override topological oscillation facts.

### Negative Consequences / Tradeoffs

* **Stricter Progression Criteria**: Workouts with a very mild pace drift without true quintile progression will correctly fall into "Steady Effort" rather than "Progression Run". Even with the relaxed >= 3 transitions, some marginal progression runs may be lost compared to the overly-permissive `slope < -0.225` heuristic.
* **Algorithm Complexity**: Using a rolling local baseline requires a slightly more complex sliding window pass compared to computing a single global arithmetic mean.
* **Regression Risk**: Changing the fundamental phase segmentation algorithm risks altering cycle counts on previously correctly classified runs. Extensive regression testing must be applied to `Steady Effort` and `Fartlek` test cases to ensure the local baseline doesn't introduce phantom cycles.

## Pros and Cons of the Options

### Option 1: Rolling Local Baseline (Chosen)
* **Good**: Directly handles warm-up drift and varying baseline effort levels.
* **Good**: Avoids false positives from pace variations on hills.
* **Bad**: Slightly more complex implementation than a global mean.

### Option 2: Dual-Channel Segmentation
* **Good**: Captures efforts where cadence doesn't change but pace does.
* **Bad**: Extremely susceptible to false positives on rolling hills where pace naturally fluctuates without representing a true surge effort.

### Option 3: Whitelist Patch
* **Good**: One-line code change.
* **Bad**: Leaves the broken zero-crossing logic in place; fails to classify the run correctly as "Intervals" (would likely become "Steady Effort" due to `< 3` cycles).

## Links and References

* Supersedes scalar regression fallback from commit `9b14e02`
* Completes the intent of [ADR-0003: Topological Signature Classification for Run Types](0003-topological-signature-classification-for-run-types.md) by removing the slope fallback and refining quintile monotonicity.
