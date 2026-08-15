import Foundation
import FoundationModels

/// A structured response definition mapping to what we want the Foundation Model to return.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map text to this struct.
@available(iOS 26.0, *)
@Generable
struct CoachingInsightPayload {
    @Guide(description: "A short, catchy headline summarizing the run analysis. Strict max 8 words.")
    var headline: String

    @Guide(description: "Compare today's Pace/HR/Cadence relationship to the rolling average.")
    var longitudinalObservation: String

    @Guide(description: "The title of a suggested technique drill to improve their form or fitness based on the observation.")
    var drillTitle: String

    @Guide(description: "e.g., '4 × 30s at target cadence'")
    var drillReps: String

    @Guide(description: "e.g., '60s easy walk between sets'")
    var drillRecovery: String

    @Guide(description: "Specific form cues (e.g., 'Focus on quick foot turnover')")
    var drillCues: String

    @Guide(description: "Target cadence as a steady band or target value, if applicable. Return null if no specific target.")
    var targetCadence: Int?
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    private init() {}

    /// Analyzes a run record and generates a CoachingInsight using on-device FoundationModels
    func generateInsight(for runRecord: RunRecord, history: [RunRecord]) async throws -> CoachingInsight {

        // Ensure Foundation Models are available on device
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        // Define the prompt string
        let paceFormatted = String(format: "%.2f", runRecord.avgPace)
        let distanceKm = runRecord.distance / 1000.0
        let distanceFormatted = String(format: "%.2f", distanceKm)

        // Calculate rolling 5-run average
        let recentRuns = Array(history.prefix(5))
        var rollingAvgPrompt = "Rolling 5-Run Avg: None"
        if !recentRuns.isEmpty {
            let avgPace = recentRuns.map { $0.avgPace }.reduce(0, +) / Double(recentRuns.count)
            let avgHR = recentRuns.map { $0.avgHeartRate }.reduce(0, +) / recentRuns.count
            let avgCadence = recentRuns.map { $0.avgCadence }.reduce(0, +) / recentRuns.count

            rollingAvgPrompt = """
            Rolling 5-Run Avg: Pace \(String(format: "%.2f", avgPace)) min/km, HR \(avgHR) BPM, Cadence \(avgCadence) SPM
            """
        }

        let runStatsPrompt = """
        Current Run: Pace \(paceFormatted) min/km, HR \(runRecord.avgHeartRate) BPM, Cadence \(runRecord.avgCadence) SPM
        \(rollingAvgPrompt)
        """

        let instructions = """
        Act as an elite running coach providing longitudinal, evidence-based coaching.
        Analyze the provided run statistics against the rolling average baseline.
        Provide a structured drill routine rather than arbitrary numeric shifts.

        Persona: Direct, analytical, encouraging, and grounded in exercise physiology.

        Core Guardrails:
        1. No Isolated Cadence Judgments: Never declare a cadence "good" or "bad" without factoring in the user's pace. A 139 SPM cadence at an 8:30/km pace is biologically normal and should not be aggressively corrected.
        2. Focus on Rhythm, Not Speed: Emphasize even distribution, rhythm, and aerobic stability.
        3. Progressive Target Generation: Never recommend an arbitrary +1 SPM change. If generating a cadence drill, target a steady band (e.g., 142–146 SPM) rather than a single digit.
        4. Headline Restraint: Limit the headline to a maximum of 6–8 words.
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let prompt = """
        Context Payload:
        \(runStatsPrompt)
        """

        // Execute the prompt expecting the @Generable struct output
        let generatedInsight = try await session.respond(to: prompt, generating: CoachingInsightPayload.self)

        let drillRecommendation = DrillRecommendation(
            title: generatedInsight.content.drillTitle,
            reps: generatedInsight.content.drillReps,
            recovery: generatedInsight.content.drillRecovery,
            cues: generatedInsight.content.drillCues,
            targetCadence: generatedInsight.content.targetCadence,
            previousCadence: runRecord.avgCadence,
            isCompleted: false
        )

        // Map the generated struct to our SwiftData model
        let newInsight = CoachingInsight(
            headline: generatedInsight.content.headline,
            longitudinalObservation: generatedInsight.content.longitudinalObservation,
            drillRecommendation: drillRecommendation
        )

        return newInsight
    }
}
