import Foundation
import SwiftData

@Model
final class CoachingInsight {
    var headline: String
    var observation: String
    var drillTitle: String
    var drillInstructions: String
    var isDrillCompleted: Bool

    // Inverse relationship back to RunRecord
    var runRecord: RunRecord?

    init(
        headline: String,
        observation: String,
        drillTitle: String,
        drillInstructions: String,
        isDrillCompleted: Bool = false
    ) {
        self.headline = headline
        self.observation = observation
        self.drillTitle = drillTitle
        self.drillInstructions = drillInstructions
        self.isDrillCompleted = isDrillCompleted
    }
}
