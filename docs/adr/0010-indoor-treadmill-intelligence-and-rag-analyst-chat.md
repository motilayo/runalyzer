# Indoor Treadmill Intelligence, Glass-Box ML Classification, and Interactive RAG Analyst Coaching

* **Status**: Accepted
* **Date**: 2026-10-08
* **Deciders**: Runalyst Engineering
* **Consulted**: Exercise Physiology (Treadmill Biomechanics, Thermoregulation & Drift), CoreML & FoundationModels SDK Guidelines
* **Informed**: Runalyst iOS & WatchKit Engineering

## Context and Problem Statement

Treadmill running introduces unique biomechanical, physiological, and sensor challenges compared to outdoor running:
1. **Sensor Accuracy & Mutation**: Wrist accelerometers on treadmills estimate speed from arm swing, leading to high noise and calibration mismatches. Post-workout, Apple Watch often prompts runners to calibrate treadmill distance, which mutates the `HKWorkout` retroactively.
2. **Pace Variance Artificiality**: Treadmill belts artificially lock running speed. A runner doing an interval surge or incline climb will show zero pace variance (`pace_cv`), confounding standard ML classifiers that rely on pace changes.
3. **Incline Telemetry Blindness**: HealthKit contains no incline data stream for standard treadmills. When runners perform incline climbs, pace remains flat while heart rate spikes and cadence drops, confusing traditional classifiers.
4. **Coaching Persona & Explainability**: Runners want to question the AI about their telemetry (cardiac drift, indoor pace strain, efficiency factor) without the AI hallucinating medical prescriptions, recommending shoe brands, or pretending indoor GPS exists.

## Decision Drivers

* **Ground-Truth Data Paths**: Differentiate between GymKit-connected treadmills (trusted belt speed and incline) vs. wrist-accelerometer estimations (defensive smoothing required).
* **Calibration Reconciliation**: Ingestion must silently detect and reconcile post-workout HealthKit distance mutations.
* **Glass-Box ML & Confidence Gate**: CoreML classifications with probability < 75% must refuse to guess and present `"Mixed Effort (Review)"` to the runner with full probability breakdowns.
* **Persona Framework**: The AI must adopt the "Mind of an Analyst, Voice of a Coach" persona, providing deep biomechanical insights while speaking in accessible runner language.
* **Strict Guardrails**: Hard refusal boundaries against medical diagnosis/prescription (refer to PT/physician), hardware inquiries (explain lack of indoor GPS), and subjective gear recommendations (focus on biomechanics).
* **Token Efficiency (TN3193)**: Compact `key: value` lines rather than bulky JSON for RAG context payloads (`MacroProfile` and `RunSignature`).

## Decision Outcome

Chosen Architecture:
1. **Data Ingestion & Calibration Reconciliation**:
   - Centralized `syncData()` detects when stored distance differs by > 5 meters from HealthKit, invoking in-place recalculation via `refreshWorkoutMetrics()`.
   - Data source is tagged as `"gymkit"`, `"footpod"`, or `"wrist"`. For wrist runs, median filtering and 25% outlier clamping are applied to smooth spurious arm-swing spikes.
2. **Machine Learning & CoreML (v7)**:
   - Synthetic dataset retrained with `hrCV` and indoor features to 98.84% accuracy.
   - For non-GymKit indoor workouts, `paceCV` and `paceSlope` are deprioritized.
   - Pure deterministic incline inference detects high HR variance with flat pace and decaying cadence, flagging the workout for user review ("Were you running incline intervals?").
   - 75% confidence gate maps low-probability classifications to `"Mixed Effort (Review)"` with quick-select confirmation buttons.
3. **Interactive RAG AI Analyst (`AnalystChatEngine`)**:
   - `MacroProfile` (ACWR, acute/chronic load) and `RunSignature` (phase segmentation, cadence floor) are computed once at ingestion and stored locally.
   - Prompts inject compact `key: value` telemetry lines.
   - Interactive chat provides runner chips, streaming responses, and `TelemetryHighlighter` rendering numbers and units in bold accent color.
   - Rigid deterministic guardrails for medical, hardware, and equipment queries.
4. **Glass-Box UI Components**:
   - `IndoorTrackGraphic`: Vector graphic visual for treadmill runs.
   - `RunVarianceMapView`: Segmented timeline of Work, Recovery, and Steady phases with cadence floor marker.
   - `ReadinessMathModal`: Transparent modal sheet breaking down ACWR math, acute 7-day load, and chronic 28-day load.
   - Footpod biomechanics filter: Hides vertical oscillation and stride length cards when recorded indoors without a footpod.

## Consequences

* **Positive**: Treadmill runs receive first-class intelligence without hallucinations or false interval classifications.
* **Positive**: Full backwards compatibility with existing SwiftData models via additive optional properties.
* **Positive**: Strict adherence to zero-LaTeX formatting and on-device model token limits.
* **Compliance**: Validated against comprehensive unit test suites in `IndoorIntelligenceTests` with 100% pass rate.
