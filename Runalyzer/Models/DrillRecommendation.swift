import Foundation
import SwiftData

@Model
final class DrillRecommendation {
    var drillTitle: String
    var drillReps: String
    var drillRecovery: String
    var drillCues: String

    var targetCadence: String?
    var previousCadence: Int?
    var isCompleted: Bool

    @Relationship(deleteRule: .nullify, inverse: \CoachingInsight.drillRecommendation)
    var insight: CoachingInsight?

    init(
        drillTitle: String,
        drillReps: String,
        drillRecovery: String,
        drillCues: String,
        targetCadence: String? = nil,
        previousCadence: Int? = nil,
        isCompleted: Bool = false
    ) {
        self.drillTitle = drillTitle
        self.drillReps = drillReps
        self.drillRecovery = drillRecovery
        self.drillCues = drillCues
        self.targetCadence = targetCadence
        self.previousCadence = previousCadence
        self.isCompleted = isCompleted
    }
}
