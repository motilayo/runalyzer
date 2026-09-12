# Runalyst v2.0.0 — The Proactive AI Biomechanical Coach 🏃‍♂️⚡

Runalyst 2.0 transforms your running data into proactive, on-device biomechanical coaching. Powered by Apple FoundationModels and CoreML, Runalyst analyzes your past runs entirely on-device to prescribe tailored pre-run corrective drills, track longitudinal 30-day form baselines, and sync structured workouts directly to your Apple Watch via WorkoutKit.

---

### 🌟 What's New in v2.0.0

#### 1. 🎯 Pre-Run Corrective Drills Library & WorkoutKit Watch Handoff
- **10 Biomechanical Drills**: Complete engine library categorized under *Foundation & Recovery*, *Speed & Efficiency*, and *Threshold & Form*:
  - *Cadence Pyramids*, *Rhythm Intervals*, *Tempo Surges*, *Strides*, *Form Primers (Neuromuscular)*, *Hill Bounds*, *Fartlek Primers*, *Aerobic Flush*, *Recovery Jog*, and *Zone 2 Run*.
- **Seamless Apple Watch Handoff**: Preview structured intervals in native SwiftUI and schedule custom workouts directly to Apple Watch under **Runalyst** with tactile haptic feedback and targeted cadence/heart rate alerts.
- **Heart Rate Zone Alerts**: Zone 1 HR target alerts for recovery runs and Zone 2 HR alerts for aerobic base building with interactive metric explainers.
- **Auto-Syncing Watch Workouts**: Seamlessly clears stale workouts and schedules updated drills to Apple Watch when your baseline cadence shifts.
- **Previous Drill Completion Feedback**: The coaching engine detects when you have executed a previously prescribed drill, compares your actual average cadence against the target cadence, and delivers targeted feedback on your drill execution.

#### 2. 📊 Hero Dashboard & 30-Day Biomechanical Baselines
- **Longitudinal Baseline Engine**: Real-time rolling 30-day averages for cadence (SPM), aggregate pace, and vertical oscillation (cm).
- **Workout Density & Trend Badges**: Visual indicators for workout density tiers (*Low*, *Moderate*, *Optimal*, *High*) and week-over-week / month-over-month performance deltas.
- **Zone 2 Primer & Action Cards**: Instant daily coaching recommendations tailored to your recent training load.
- **Passive HealthKit Sync**: Reads previous running workouts seamlessly without requiring continuous background GPS tracking.

#### 3. 🧠 On-Device Intelligence & CoreML Personalization
- **High-Accuracy CoreML Classifier**: Integrated `RunalystClassifier.mlmodel` trained on continuous probability distributions with 98% classification accuracy.
- **User Correction Feedback Loop**: Correct classifications directly in the app to refine local training memory in SwiftData.
- **Deterministic Swift Guardrails**: Evaluates cardiovascular and biomechanical data deterministically in Swift before invoking on-device FoundationModels (`LanguageModelSession`)—overriding aspirational race goals with recovery priorities whenever acute fatigue or aerobic strain is detected.
- **100% Private & Local**: AI analysis runs entirely on-device with zero cloud data transmission or third-party tracking.

#### 4. ⚡ Mathematical & Biomechanical Precision
- **Pure Aggregate Pace Math**: True distance-over-time pace calculation decoupling raw averages from short fluctuations.
- **Robust Working Heart Rate & Metric Filtering**: Ignores invalid zero/negative samples, pause intervals, and non-running segments to preserve biomechanical accuracy.
- **Vertical Oscillation Ratio Alignment**: Calibrated directly against HealthKit workout statistics.
- **Indoor & Outdoor Run Tagging**: Contextual badge tagging for treadmill versus road/trail running workouts.

---

### 🛠️ Technical Improvements & Architecture
- **Swift 6 Concurrency**: Strict concurrency compliance across all actors, models, and background tasks.
- **SwiftData Schema Migration**: Versioned `RunalystSchemaV1` schema supporting lightweight model migrations.
- **Dynamic User Profile**: Experience level and weekly volume dynamically calculated from recent 30-day SwiftData history.
- **On-Demand AI Insights**: Pull-to-refresh on `RunDetailView` and `DashboardView` allows instant recalculation of coaching insights.
- **Automated CI/CD Quality Gates**: Strict SwiftLint enforcement, Gitleaks secret scanning, CoreML seed data generation pipeline, and 37 comprehensive unit & integration tests.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/commits/v2.0.0
