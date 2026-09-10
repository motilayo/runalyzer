import Foundation
import SwiftData

/// Schema Version 1.0.0 definition for Runalyst SwiftData persistence.
enum RunalystSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            RunRecord.self,
            CoachingInsight.self,
            DrillRecommendation.self,
            TrainingCorrection.self
        ]
    }
}

/// Explicit SchemaMigrationPlan managing SwiftData schema evolution and protecting historical user runs and insights.
enum RunalystMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RunalystSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // Migration stages (e.g. lightweight or custom migrations) are registered here as schemas evolve.
        []
    }
}
