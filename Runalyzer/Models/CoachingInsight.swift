import Foundation
import SwiftData

/// Represents the AI-generated coaching insight associated with a specific run.
/// Persisted locally via SwiftData.
@Model
final class CoachingInsight {
    /// A short, catchy headline summarizing the run analysis.
    var headline: String

    /// An observation specifically about aerobic effort or biomechanics (e.g., cadence).
    var observation: String

    /// The title of the suggested technique drill.
    var drillTitle: String

    /// Step-by-step instructions on how to perform the drill.
    var drillInstructions: String

    /// Indicates whether the user has completed this drill. Defaults to false.
    var isDrillCompleted: Bool

    /// The inverse one-to-one relationship back to the `RunRecord` that generated this insight.
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
