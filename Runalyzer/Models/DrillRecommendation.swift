import Foundation
import SwiftData

@Model
final class DrillRecommendation {
    var title: String
    var reps: String
    var recovery: String
    var cues: String

    var targetCadence: String?
    var previousCadence: Int?
    var isCompleted: Bool

    @Relationship(deleteRule: .nullify, inverse: \CoachingInsight.drillRecommendation)
    var insight: CoachingInsight?

    init(
        title: String,
        reps: String,
        recovery: String,
        cues: String,
        targetCadence: String? = nil,
        previousCadence: Int? = nil,
        isCompleted: Bool = false
    ) {
        self.title = title
        self.reps = reps
        self.recovery = recovery
        self.cues = cues
        self.targetCadence = targetCadence
        self.previousCadence = previousCadence
        self.isCompleted = isCompleted
    }
}
