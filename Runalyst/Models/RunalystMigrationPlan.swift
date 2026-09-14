import Foundation
import SwiftData

/// Schema Version 1.0.0 definition for Runalyst SwiftData persistence.
/// Represents the clean baseline schema encompassing workouts, biomechanical working metrics,
/// AI coaching insights, drill recommendations with user completion state, and classification training corrections.
enum RunalystSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            RunRecord.self,
            CoachingInsight.self,
            DrillRecommendation.self,
            TrainingCorrection.self
        ]
    }
}

/// Explicit SchemaMigrationPlan managing SwiftData schema evolution.
///
/// ### Architecture & Migration Policy:
/// 1. **User Action State Preservation**:
///    - State representing user decisions—such as `DrillRecommendation.isCompleted` or `TrainingCorrection` classification
///      overrides—must be preserved across all future schema versions. Never drop or reset user state during migrations.
/// 2. **Adding Future Schema Versions**:
///    - When introducing structural or non-optional model changes, declare a new `VersionedSchema` (e.g. `RunalystSchemaV2: VersionedSchema`).
///    - Register it in `schemas`: `[RunalystSchemaV1.self, RunalystSchemaV2.self]`.
///    - Add an explicit `MigrationStage`:
///      - Use `MigrationStage.lightweight(fromVersion: RunalystSchemaV1.self, toVersion: RunalystSchemaV2.self)` for additive optional changes.
///      - Use `MigrationStage.custom(fromVersion:toVersion:willMigrate:didMigrate:)` when transforming tables or backfilling user action data.
/// 3. **Zero Redundant Compute**:
///    - Avoid post-launch data repair loops on every app launch. Ingested data should be validated and finalized on first write.
enum RunalystMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RunalystSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // Register MigrationStages here as new schema versions are added.
        []
    }
}
