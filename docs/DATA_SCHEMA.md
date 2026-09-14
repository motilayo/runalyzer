# Data Schema & Persistence

Runalyst uses **SwiftData** with an underlying SQLite store to persist AI insights locally. However, **Apple HealthKit** remains the definitive source of truth for the raw workout biometrics.

## Caching Strategy

The local SwiftData store acts purely as a *cache* for the expensive and slow AI generations.
1. When the app launches, it syncs with HealthKit.
2. If a workout exists in HealthKit but not in SwiftData, the app creates a `RunRecord`.
3. Background tasks iteratively process each new `RunRecord` using the CoreML and FoundationModels pipelines, saving the generated `CoachingInsight` to SwiftData.
4. If the user ever taps **"Resync Health Data & Rebuild AI Insights"** in settings, the app simply purges the entire SwiftData cache and re-pulls from HealthKit.

## The `RunRecord` Schema

The `RunRecord` model contains two distinct classes of metrics:
1. **Raw Metrics**: (`rawAvgPace`, `rawAvgHeartRate`) Data pulled directly from the `HKWorkout`. This data is often inaccurate for city running because it averages in dead-stops at traffic lights.
2. **Working Metrics**: (`workingAvgPace`, `workingAvgHeartRate`, `paceCV`) Data processed by the `FramboiseEngine` to exclude non-active time and compute advanced statistical deviations.

**Future Code Context**: Always pass the **Working Metrics** into the CoreML classifier and FoundationModels prompt. Passing raw metrics will result in skewed AI insights.

## Migrations

Between V1.1 and V2.0, the schema underwent massive breaking changes (types changed from Int to Double, massive additions of non-optional analytical fields).

Because the local SwiftData store is treated as a disposable cache, **we do not provide a complex V1 -> V2 Migration Stage**.
Instead, `RunalystApp.swift` is configured to catch `ModelContainer` initialization errors (schema mismatches) in production. If a user upgrades from V1 to V2, SwiftData fails to load the V1 store. The app catches this, deletes the `.sqlite` files from disk, builds a fresh V2 container, and automatically re-ingests the user's data from HealthKit to generate V2-compatible insights.

**Future Code Context**: 
- If you add *new* fields to `RunRecord` in minor updates (e.g., V2.1), mark them as `Optional` (`String?`, `Double?`). SwiftData will automatically perform a lightweight migration for existing V2 rows without crashing.
- Do NOT use inline default values (e.g., `var newField: String = ""`) to try and bypass migrations. CoreData requires Optional types for true zero-code lightweight migrations when adding attributes to an existing entity.
