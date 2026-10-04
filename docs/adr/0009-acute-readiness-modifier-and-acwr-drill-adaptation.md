# Acute Readiness Modifier and ACWR Drill Target Adaptation

* **Status**: Accepted
* **Date**: 2026-10-04
* **Deciders**: Runalyst Engineering
* **Consulted**: Sports Physiology Literature (Gabbett ACWR, Banister Impulse-Response), Apple WorkoutKit & HealthKit guidelines
* **Informed**: Runalyst AI Coaching & WatchKit Teams

## Context and Problem Statement

Runalyst prescribes pre-run neuromuscular and biomechanical drills (e.g., Strides, Cadence Pyramids, Tempo Surges) parameterized by the runner's rolling 30-day baseline cadence. 

A 30-day rolling aggregate measures **Chronic Training Load (CTL)** or accumulated structural adaptation. Because it smooths telemetry over 4 weeks, it has a critical physiological blind spot:
1. **Acute Fatigue Blindness**: It cannot detect that a runner is carrying acute muscular damage, glycogen depletion, or neuromuscular fatigue from a hard interval workout 36 hours prior. Prescribing an overspeed target (e.g., +5% to +10% over baseline, pushing 165+ SPM) to a fatigued runner forces compensatory mechanics, vertical collapse, and injury risk.
2. **Deload Week Disruption**: During planned taper or deload periods (where 7-day mileage drops 25%–40% at low intensity), prescribing high-volume neuromuscular drill sets (e.g., 6 x 20s Strides or 5 x 45s Rhythm Intervals) undermines muscular recovery and glycogen supercompensation.

We need an adaptive **Readiness Modifier** that modulates chronic 30-day targets with 7-day acute workload metrics (Acute-to-Chronic Workload Ratio, ACWR) and acute telemetry markers, without tearing down the existing SwiftData pipeline or delegating deterministic math to generative LLMs.

## Decision Drivers

* **Physiological Veracity**: Drill targets must respect acute physiological strain (Gabbett's ACWR model and cardiac/cadence drift markers).
* **Deterministic Guardrails**: As mandated in `AGENTS.md`, competing priorities and physiological trade-offs must be evaluated deterministically in Swift rather than by LLM prompt reasoning.
* **Apple Watch & WorkoutKit Invariance**: Any target or volume modification presented in the iOS UI must propagate with exact 1-to-1 fidelity down to the Apple Watch `WorkoutPlan` via `WorkoutBridge`.
* **Zero Disruption to Productive Training**: When acute load is balanced with chronic load (ACWR 0.8–1.3), the runner receives their standard 30-day personalized prescription without modification.
* **Transparent Runner Context**: The runner must see why their prescription was modified directly in the pre-run drill half-sheet (`DrillInterstitialReadoutView`).

## Considered Options

* **Option 1 (Chosen) - Deterministic ACWR & Multi-Signal Telemetry Modifier**:
  Evaluate the 7-day vs 28-day workload ratio along with acute telemetry flags (`cadenceFade`, `cardiacDrift`, back-to-back hard sessions). Modulate cadence targets and rep volume deterministically in Swift. Feed the adapted specification into `PreRunDrill`, `DrillReadout`, and `WorkoutBridge`.
* **Option 2 - LLM-Driven Prompt Adaptation**:
  Pass 7-day and 30-day aggregates into the FoundationModels LLM prompt and instruct the model to suggest relaxed targets or reduced volume in text.
* **Option 3 - Global Target Suppression**:
  When fatigue is detected, cancel all drills entirely and force an easy aerobic run.

## Decision Outcome

Chosen option: **Option 1**, because it maintains mathematical determinism, guarantees Apple Watch plan synchronization, strictly follows `AGENTS.md` guidelines on avoiding LLM math, and preserves training continuity during deloads and acute fatigue instead of blunt cancellation.

### Mathematical & Physiological Rules

1. **Workload Definition (Session TRIMP Proxy)**:
   `Session Load = Duration (minutes) * (1.0 + 2.0 * Percent Zone 4)`
   Zone 4/5 time receives 3x weighting over Zone 1/2 aerobic time.

2. **Acute-to-Chronic Workload Ratio (ACWR)**:
   `ACWR = Acute Load (7-Day Sum) / Chronic Weekly Load (28-Day Sum / 4.0)`
   * ACWR > 1.5 indicates an acute strain spike.
   * Trailing history requires >= 14 days and >= 4 sessions to avoid early false-positive spikes for new users.

3. **Acute Fatigue Triggers**:
   * **ACWR Spike**: ACWR > 1.5.
   * **Consecutive Hard Days**: Hard sessions (Intervals, Tempo, Pyramids, Hill Repeats, or >= 35% Zone 4) on 2 consecutive calendar days within the last 72 hours.
   * **Cadence Fade**: Progressive turnover decay in the final third across the prior 2 runs.
   * **Cardiac Drift**: Steady pace with climbing heart rate on the most recent run.
   * **Action**: Soften overspeed cadence target back to neutral baseline range (`[baseline - 3, baseline + 3]`); scale interval reps by 0.5 (halved volume, minimum 2 reps).

4. **Deload Week Triggers**:
   * **Mileage Reduction**: 7-day total mileage drops by >= 25% compared to the trailing 3-week weekly average.
   * **Controlled Intensity**: Weighted Zone 4 fraction <= 10% across the 7-day window, with zero hard workouts.
   * **Action**: Maintain turnover intensity (keep target cadence unchanged); scale interval volume by 0.5 (halve reps); extend recovery intervals by 1.5x (e.g., 60s -> 90s) to prevent lactic accumulation.

5. **Exemptions**:
   Continuous recovery drills (`.aerobicFlush`, `.recoveryJog`, `.zone2Run`) are already active recovery sessions and are never downscaled.

### Positive Consequences

* Runner is protected from mechanical breakdown when carrying acute fatigue.
* Deload weeks maintain neuromuscular sharpness without inducing fatigue.
* Readout sheet displays exact adaptation: adjusted target vs baseline target, volume reduction, and clear coach explanation.
* Apple Watch WorkoutKit plan matches the UI timeline byte-for-byte.

### Negative Consequences / Tradeoffs

* Workouts scheduled to Apple Watch during acute fatigue have fewer reps, requiring clear user communication that this is intentional coaching, not a bug.

## Links and References

* `AGENTS.md` (Sections 1, 2, and 3: Deterministic guardrails over prompt guardrails)
* `ADR-0002`: Structural Sequence Parsing for Interval Workouts
* `ADR-0005`: Dual-Scope Refresh and HealthKit Sync Lifecycle
* Tim Gabbett (2016): *The training—injury prevention paradox: should athletes be training smarter and harder?* British Journal of Sports Medicine.
