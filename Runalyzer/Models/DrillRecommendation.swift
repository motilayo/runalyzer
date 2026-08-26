import Foundation
import SwiftData

/// Represents an actionable technique or form drill recommended by the AI Coaching Engine.
/// Persisted locally via SwiftData.
@Model
final class DrillRecommendation {
    var drillTitle: String
    var drillWork: String?
    var drillCues: String?
    var drillEffort: String?
    var drillPurpose: String?

    var targetCadence: String?
    var previousCadence: Int?
    var isCompleted: Bool

    var orderIndex: Int?

    @Relationship(deleteRule: .nullify, inverse: \CoachingInsight.drillRecommendations)
    var insight: CoachingInsight?

    init(
        drillTitle: String,
        drillPurpose: String? = nil,
        drillWork: String? = nil,
        drillCues: String? = nil,
        drillEffort: String? = nil,
        targetCadence: String? = nil,
        previousCadence: Int? = nil,
        isCompleted: Bool = false,
        orderIndex: Int? = nil
    ) {
        self.drillTitle = drillTitle
        self.drillWork = drillWork
        self.drillCues = drillCues
        self.drillEffort = drillEffort
        self.drillPurpose = drillPurpose
        self.targetCadence = targetCadence
        self.previousCadence = previousCadence
        self.isCompleted = isCompleted
        self.orderIndex = orderIndex
    }
}
