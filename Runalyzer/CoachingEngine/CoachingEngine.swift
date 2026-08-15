import Foundation
import FoundationModels

/// A structured response definition mapping to what we want the Foundation Model to return.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map text to this struct.
@Generable
struct GeneratedCoachingInsight {
    @Guide(description: "A short, catchy headline summarizing the run analysis")
    var headline: String

    @Guide(description: "An observation specifically about the runner's aerobic effort (heart rate) or biomechanics (specifically cadence/SPM).")
    var observation: String

    @Guide(description: "The title of a suggested technique drill to improve their form or fitness based on the observation.")
    var drillTitle: String

    @Guide(description: "A short, actionable step-by-step instruction on how to perform the drill.")
    var drillInstructions: String
}

@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    private init() {}

    /// Analyzes a run record and generates a CoachingInsight using on-device FoundationModels
    func generateInsight(for runRecord: RunRecord) async throws -> CoachingInsight {

        // Ensure Foundation Models are available on device
        guard SystemLanguageModel.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        // Define the prompt string
        let paceFormatted = String(format: "%.2f", runRecord.avgPace)
        let distanceKm = runRecord.distance / 1000.0
        let distanceFormatted = String(format: "%.2f", distanceKm)

        let runStatsPrompt = """
        Distance: \(distanceFormatted) km
        Average Pace: \(paceFormatted) min/km
        Average Heart Rate: \(runRecord.avgHeartRate) BPM
        Average Cadence: \(runRecord.avgCadence) SPM
        """

        let instructions = """
        Act as an elite running coach.
        Analyze the provided run statistics.
        Provide a short headline, an observation about their aerobic effort or biomechanics (specifically cadence), and suggest one actionable technique drill.
        Your tone should be professional and encouraging.
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let prompt = """
        Analyze this run:
        \(runStatsPrompt)
        """

        // Execute the prompt expecting the @Generable struct output
        let generatedInsight: GeneratedCoachingInsight = try await session.respond(to: prompt)

        // Map the generated struct to our SwiftData model
        let newInsight = CoachingInsight(
            headline: generatedInsight.headline,
            observation: generatedInsight.observation,
            drillTitle: generatedInsight.drillTitle,
            drillInstructions: generatedInsight.drillInstructions,
            isDrillCompleted: false
        )

        return newInsight
    }
}
