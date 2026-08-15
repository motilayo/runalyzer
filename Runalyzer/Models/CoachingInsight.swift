import Foundation
import SwiftData

/// Represents the AI-generated coaching insight associated with a specific run.
/// Persisted locally via SwiftData.
@Model
final class CoachingInsight {
    /// A short, catchy headline summarizing the run analysis. Max 8 words.
    var headline: String

    /// Compare today's Pace/HR/Cadence relationship to the rolling average.
    var longitudinalObservation: String

    /// The structured drill recommendation.
    var drillRecommendation: DrillRecommendation?

    /// The inverse one-to-one relationship back to the `RunRecord` that generated this insight.
    var runRecord: RunRecord?

    init(
        headline: String,
        longitudinalObservation: String,
        drillRecommendation: DrillRecommendation? = nil
    ) {
        self.headline = headline
        self.longitudinalObservation = longitudinalObservation
        self.drillRecommendation = drillRecommendation
    }
}
