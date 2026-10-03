# ADR-0008: Feature Vector Extraction and Taxonomic Run Classification Engine

* Status: Proposed
* Date: 2026-10-02
* Deciders: Antigravity Agent, Joshua Agboola
* Consulted: Engineering & Architecture Guidelines (`AGENTS.md`)
* Informs: `FramboiseEngine.swift`, `ModelManager.swift`, `HealthKitManager.swift`, `WorkoutTelemetryVeracityTests.swift`, `GoldenTelemetryFixtures.swift`, `generate_seed_runs.py`, `train_model.py`

## Context and Problem Statement

The Runalyst application classifies workouts into distinct physiological categories to drive downstream AI coaching, drill prescriptions, and baseline longitudinal tracking. 

Historically, run classification relied on a mix of scalar heuristics (`FramboiseEngine`) and an offline-trained tabular model (`RunalystClassifier`). Over time, while UI pickers (`RunDetailView`) and test models referenced 11 canonical classifications ("Steady Effort", "Easy Run", "Tempo Run", "Intervals", "Pyramids", "Progression Run", "Recovery Run", "Hill Repeats", "Long Run", "Fartlek", "Urban Traffic"), the runtime engine only directly resolved a subset (Progression Run, Long Run, Intervals, Fartlek, Recovery Run, Easy Run, Tempo Run, Steady Effort), leaving labels like "Pyramids", "Hill Repeats", and "Urban Traffic" unclassified or relegated to auxiliary tags (`urbanTraffic`).

Furthermore, critical physiological differentiators were underspecified in code:
1. **Intervals vs. Fartlek**: Both exhibit high pace CV and intermittent cycles. The true biomechanical differentiator is the **recovery floor**: walking or standing rest (< 120 SPM) versus active continuous jogging (> 135 SPM).
2. **Pyramids**: Interval ladders that expand and contract work duration symmetrically (e.g. 1-2-3-4-3-2-1 minutes) were penalized by cycle regularity metrics (`calculateCycleRegularity`) because work durations vary by design.
3. **Hill Repeats**: Intermittent hill surges rely on elevation/grade arrays synchronized with heart rate surges, which were not evaluated during cycle extraction.
4. **Urban Traffic**: City running causes sharp 5-15s stops at crosswalks and traffic lights, creating high pace CV without interval symmetry or purposeful recovery floors.
5. **Recovery Runs**: True recovery runs require temporal context (occurring within 24 hours of an Interval, Tempo, or Hill workout) combined with low absolute intensity (strictly Zone 1 / low Zone 2).

## Decision Drivers

1. **Taxonomic Completeness**: The engine must natively classify all 11 canonical run types defined in the Runalyst domain model.
2. **Feature Vector Extraction Architecture**: Rather than feeding raw, noisy, irregularly sampled time-series into heavy neural networks, the engine distills 15-second buckets and 30-second overlapping sliding windows into a compact, deterministic Feature Vector.
3. **Deterministic Structural Priority & Guardrails**: Hard topological rules (e.g., low-variance progression, walking recovery floor, elevation saw-tooth, traffic entropy) act as deterministic gates alongside CoreML tabular inference.
4. **Energy and Battery Efficiency**: Ingestion and feature extraction must execute in sub-millisecond time on Apple Silicon with minimal CPU and memory footprints.
5. **Test Veracity & Golden Fixtures**: All 11 archetypes must be represented by authentic or noise-injected time-series fixtures in `GoldenTelemetryFixtures` adhering to ADR-0007.

## Decision Outcome

We establish the **11-Profile Taxonomic Classification Specification** powered by a **15-Dimensional Feature Vector** extracted from 30-second sliding windows.

### 1. The 11 Canonical Run Profiles & Signatures

1. **Steady Effort**:
   - *Goal*: Controlled, moderate-to-hard aerobic rhythm locked into a single gear.
   - *Signature*: Near-zero pace slope (|paceSlope| <= 0.08), very low pace CV (cv < 0.06), tight cadence variance (cadenceCV < 0.025).
2. **Easy Run**:
   - *Goal*: Aerobic base and capillary density without structural load.
   - *Signature*: Low CV, flat slope, average heart rate strictly capped in Zone 2 (percentZone1And2 >= 0.85, percentZone4 <= 0.10), pace substantially slower than 30-day baseline (paceDelta > 0).
3. **Tempo Run**:
   - *Goal*: Lactate threshold clearance at race or near-race velocities.
   - *Signature*: 3-phase topological profile: 10-15 min warm-up -> sustained plateau of high effort in Zone 3/4 (percentZone4 >= 0.45, plateau cv < 0.05) -> cool-down drop.
4. **Intervals**:
   - *Goal*: Maximum anaerobic output requiring ATP resynthesis.
   - *Signature*: High pace CV (cv >= 0.09), corroborated surge-and-recovery cycles (>= 3 cycles), and **recovery cadence floor < 120 SPM** (standing/walking rest).
5. **Pyramids**:
   - *Goal*: Structured ladder intervals scaling up and down in work duration.
   - *Signature*: High pace CV, intermittent cycles with bell-curve duration symmetry (workBlockSymmetry >= 0.70) across the session.
6. **Progression Run**:
   - *Goal*: Starting slow, finishing fast to practice pace control under fatigue.
   - *Signature*: Steep negative pace slope (paceSlope <= -0.22), low continuous pace variance (cv < 0.09), monotonic quintile pace acceleration, and parallel upward cardiac staircase (Zone 1/2 -> Zone 4/5).
7. **Recovery Run**:
   - *Goal*: Active blood flow to flush legs without accumulating fatigue.
   - *Signature*: Slowest absolute pace (paceDelta >= 30 s/km) and HR in user database; strictly Zone 1 / low Zone 2 (percentZone4 <= 0.03); duration < 40 minutes; occurring within 24 hours of an Interval, Tempo, or Hill workout.
8. **Hill Repeats**:
   - *Goal*: Neuromuscular power and stride drive against gravity.
   - *Signature*: Repeated saw-tooth elevation gain (elevation arrays / flights climbed) correlated with heart rate surges (elevationHrCorrelation >= 0.60) followed by descending recoveries.
9. **Long Run**:
   - *Goal*: Time on feet, slow-twitch fiber resilience, glycogen capacity.
   - *Signature*: Duration >= 90 minutes (or distance >= 1.5x rolling 7-day average run distance), flat pace slope, low-to-moderate CV (cv < 0.08).
10. **Fartlek**:
    - *Goal*: Unstructured speed play surging and recovering in continuous motion.
    - *Signature*: High pace CV (cv >= 0.08), >= 3 cycles with irregular timing (cycle regularity < 0.65 or high work duration variance), and **recovery cadence floor > 135 SPM** (active continuous jog).
11. **Urban Traffic**:
    - *Goal*: Environmental interruption (crosswalks, pedestrians, streetlights).
    - *Signature*: Chaotic, asymmetric 5-15s drops in cadence (< 70 SPM) and pace; absence of periodic interval ratios; high traffic entropy ratio (trafficEntropyRatio >= 0.12).

---

### 2. The 15-Dimensional Feature Vector

The feature extractor distills the run's 30-second overlapping sliding windows into the following 15 scalar features:

1. `paceDelta`: Difference between average pace and 30-day baseline (s/km).
2. `hrDelta`: Difference between average HR and 30-day baseline (BPM).
3. `percentZone1And2`: Fraction of workout time spent in Zone 1 and Zone 2 (0.0 to 1.0).
4. `percentZone4`: Fraction of workout time spent in Zone 4 and Zone 5 (0.0 to 1.0).
5. `cadenceDelta`: Difference between average cadence and 30-day baseline (SPM).
6. `verticalOscillation`: Mean vertical oscillation (cm).
7. `paceCV`: Coefficient of variation of pace across sliding windows (stdDev / mean).
8. `cadenceCV`: Coefficient of variation of cadence across sliding windows.
9. `paceSlope`: Macro linear regression slope of pace over time (normalized sec/km per minute).
10. `durationMinutes`: Total active duration in minutes.
11. `recoveryCadenceFloor`: Mean cadence of the lowest 20th percentile pace windows (SPM).
12. `workBlockSymmetry`: Structural symmetry of work interval durations around the session midpoint (0.0 to 1.0).
13. `elevationHrCorrelation`: Pearson correlation r between window elevation climb rate and 15s-lagged HR change (-1.0 to 1.0).
14. `trafficEntropyRatio`: Ratio of abrupt, non-periodic 5-15s dead-stop buckets (< 70 SPM) to total buckets.
15. `hoursSinceHeavyEffort`: Hours elapsed since the user's most recent Interval, Tempo, or Hill workout (capped at 168h / 7 days).

---

### 3. Mathematical Extraction Formulas (Plain Markdown)

#### Recovery Cadence Floor
Let W be the set of 30-second sliding windows sorted by pace ascending (fastest to slowest).
Let R be the subset of windows comprising the slowest 20% of the duration:
recoveryCadenceFloor = (1 / |R|) * Sum(cadence_w for w in R)

* If recoveryCadenceFloor < 120 SPM -> Walking/standing rest (Intervals).
* If recoveryCadenceFloor >= 135 SPM -> Active continuous jog (Fartlek).

#### Work Block Symmetry (Pyramids)
Given k corroborated work interval phases with durations D_1, D_2, ..., D_k:
midpoint = k / 2
symmetryError = Sum(|D_i - D_(k - i + 1)| for i in 1...midpoint) / Sum(D_i for i in 1...k)
workBlockSymmetry = max(0.0, 1.0 - (2.0 * symmetryError))

A classic pyramid (e.g. 60s, 120s, 180s, 120s, 60s) yields symmetryError ~= 0.0 -> workBlockSymmetry >= 0.85.

#### Traffic Entropy Ratio (Urban Traffic)
Let deadStops be the count of 15s buckets where cadence < 70 SPM and pace > 600 s/km.
Let stopDurations be the lengths in seconds of contiguous dead-stop clusters.
If any stop duration >= 45s with structured work blocks, it is an interval recovery.
If stop durations are predominantly 5 to 20 seconds with high duration variance (CV_stops > 0.50):
trafficEntropyRatio = Sum(duration of erratic stops) / totalWorkoutDuration

#### Elevation-Cardiac Correlation (Hill Repeats)
Let deltaElevation_i be the elevation gain in window i.
Let deltaHR_lagged_i be the heart rate change in window i+1 (lagged by 15-30s).
elevationHrCorrelation = Pearson_r(deltaElevation, deltaHR_lagged)

#### Cardiac Staircase (Progression Runs)
Divide the run into 5 time quintiles Q_1 to Q_5:
A run qualifies as a progression staircase if:
1. pace(Q_1) > pace(Q_2) > pace(Q_3) > pace(Q_4) > pace(Q_5) (pace gets faster)
2. hr(Q_1) <= hr(Q_2) <= hr(Q_3) <= hr(Q_4) <= hr(Q_5) (heart rate ramps upward)
3. paceCV < 0.09 (steady acceleration without intermittent surges)

---

### 4. Classification Layering in FramboiseEngine

The runtime engine evaluates classifications in deterministic order:

* **Layer 0: Environmental Interruption Gate**
  * If `trafficEntropyRatio >= 0.12` and cycles < 3 -> `"Urban Traffic"`.
* **Layer 1: Continuous Monotonic Progression**
  * If `durationMinutes >= 20.0`, `paceCV < 0.09`, `evaluateQuintileProgression`, and positive HR staircase -> `"Progression Run"`.
* **Layer 2: Topographic Sawtooth Climbs**
  * If `elevationHrCorrelation >= 0.60` with >= 3 distinct climb surges -> `"Hill Repeats"`.
* **Layer 3: Intermittent Structural Gate (>= 3 Corroborated Cycles)**
  * If `workBlockSymmetry >= 0.70` and cycles.count >= 3 -> `"Pyramids"`.
  * If `recoveryCadenceFloor < 120.0` or `regularityScore >= 0.65` -> `"Intervals"`.
  * If `recoveryCadenceFloor >= 135.0` or `regularityScore < 0.65` -> `"Fartlek"`.
* **Layer 4: Volume Gate**
  * If `durationMinutes >= 90.0` and `paceSlope > -0.20` and `percentZone4 < 0.40` -> `"Long Run"`.
* **Layer 5: Continuous Intensity Matrix**
  * If `percentZone1And2 >= 0.90`, `percentZone4 <= 0.03`, `durationMinutes < 40.0`, and `hoursSinceHeavyEffort <= 24.0` -> `"Recovery Run"`.
  * If `percentZone1And2 >= 0.80`, `percentZone4 <= 0.20`, and `paceDelta > 0` -> `"Easy Run"`.
  * If `percentZone4 >= 0.45` and `durationMinutes >= 20.0` and sustained plateau -> `"Tempo Run"`.
  * Otherwise -> `"Steady Effort"`.

## Consequences

### Positive
- All 11 user-facing run classifications are first-class citizens in the classification engine.
- Biomechanical recovery floor (< 120 vs > 135 SPM) eliminates ambiguity between Intervals and Fartlek.
- Pyramids are no longer penalized by variance-based interval regularity scores.
- Crosswalk stops are accurately categorized as Urban Traffic rather than corrupting steady run baselines.
- Fully backwards compatible with existing `BucketData` callers via optional parameters and default values.
