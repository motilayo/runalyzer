import Foundation
import FoundationModels

/// A structured response definition mapping to what we want the Foundation Model to return.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map text to this struct.
@available(iOS 26.0, *)
@Generable
struct CoachingInsightPayload {
    @Guide(description: "A short, catchy headline summarizing the run analysis. Strict max 8 words.")
    var headline: String

    @Guide(description: "Compare this run's Pace/HR/Cadence relationship to the rolling average.")
    var longitudinalObservation: String

    @Guide(description: "The title of a suggested technique drill. Must be EXACTLY one of the following: 'Cadence Pyramids', 'Rhythm Intervals', 'Tempo Surges', or 'Strides'. Do not invent new names or add suffixes.")
    var drillTitle: String

    @Guide(description: "e.g., '4 × 30s at target cadence'")
    var drillReps: String

    @Guide(description: "e.g., '60s easy walk between sets'")
    var drillRecovery: String

    @Guide(description: "Specific form cues (e.g., 'Focus on quick foot turnover')")
    var drillCues: String

    @Guide(description: "Target cadence as a steady band (e.g. '142-146'), if applicable. Return null if no specific target.")
    var targetCadence: String?
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
        let paceFormatted = runRecord.formattedPace
        let distanceKm = runRecord.distance / 1000.0
        let distanceFormatted = String(format: "%.2f", distanceKm)

        // Format the run date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateFormatted = dateFormatter.string(from: runRecord.date)

        // Calculate 30-day baseline and deltas
        var runStatsPrompt = """
        Run Date: \(dateFormatted)
        Distance: \(distanceFormatted) km
        Current Run: Pace \(paceFormatted), HR \(runRecord.avgHeartRate) BPM, Cadence \(runRecord.avgCadence) SPM
        """

        if let baseline = history.thirtyDayBaseline() {
            let hrDelta = runRecord.avgHeartRate - baseline.avgHeartRate
            let hrDeltaString = hrDelta == 0 ? "same as baseline" : (hrDelta > 0 ? "\(hrDelta) BPM higher than baseline" : "\(abs(hrDelta)) BPM lower than baseline")

            let cadenceDelta = runRecord.avgCadence - baseline.avgCadence
            let cadenceDeltaString = cadenceDelta == 0 ? "same as baseline" : (cadenceDelta > 0 ? "\(cadenceDelta) SPM higher than baseline" : "\(abs(cadenceDelta)) SPM lower than baseline")

            runStatsPrompt += """

            30-Day Baseline: Pace \(baseline.avgPace.formattedPaceString), HR \(baseline.avgHeartRate) BPM, Cadence \(baseline.avgCadence) SPM
            Deltas: HR is \(hrDeltaString). Cadence is \(cadenceDeltaString).
            """
        } else {
            runStatsPrompt += """

            Baseline: Insufficient baseline history. Analyze this run individually.
            """
        }

        let instructions = """
        Act as an elite running coach providing longitudinal, evidence-based coaching.
        Analyze the provided run statistics against the rolling average baseline.
        Provide a structured drill routine rather than arbitrary numeric shifts.

        Persona: Direct, analytical, encouraging, and grounded in exercise physiology.

        Core Guardrails:
        1. Strict Drill Titles: You MUST choose the drill title from this exact list: "Cadence Pyramids", "Rhythm Intervals", "Tempo Surges", or "Strides". Do not invent new names, use singular forms if plural is listed, or add suffixes (like 'Drills').
        2. No Isolated Cadence Judgments: Never declare a cadence "good" or "bad" without factoring in the user's pace. A 139 SPM cadence at an 8:30/km pace is biologically normal and should not be aggressively corrected.
        3. Focus on Rhythm, Not Speed: Emphasize even distribution, rhythm, and aerobic stability.
        4. Progressive Target Generation: Never recommend an arbitrary +1 SPM change. If generating a cadence drill, target a steady band (e.g., 142–146 SPM) rather than a single digit.
        5. Headline Restraint: Limit the headline to a maximum of 6–8 words.
        6. Temporal Awareness: Never use the words "today" or "today's run." Default to "This run" or reference the specific date provided.
        7. No Math Guesses: Do not attempt to calculate differences yourself; rely strictly on the higher/lower comparisons provided in the payload.
        8. No Workout Labels: Never label a run as a "Long Run", "Recovery Run", or "Tempo Run". Analyze the rhythm without guessing the user's intent.
        9. Scale the Drills: The total distance of the suggested drill intervals must never exceed 20% of the distance of the run being analyzed. If it was a short 1.5km run, prescribe short 30-second time-based drills, not 400m track intervals.
        10. Absolute Drill Targets: Drill targets MUST be absolute cadence values (e.g., '120 SPM' or '145 SPM'). NEVER output relative increase numbers or single-digit ranges (e.g., '10-15 SPM').

        Output Requirements:
        You must return the analysis mapped exactly to these fields:
        - headline: A 6-8 word punchy summary.
        - longitudinalObservation: A 2-3 sentence analysis comparing this run's Pace, HR, and Cadence to the rolling baseline.
        - drillTitle: A professional name for the drill. MUST BE EXACTLY one of: "Cadence Pyramids", "Rhythm Intervals", "Tempo Surges", "Strides".
        - drillReps: The exact interval structure with realistic, absolute numbers (e.g., "6 x 400m at 142 SPM").
        - drillRecovery: The rest period (e.g., "2 minutes easy jog").
        - drillCues: A single sentence focusing on running form or biomechanics.
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
            drillTitle: generatedInsight.content.drillTitle,
            drillReps: generatedInsight.content.drillReps,
            drillRecovery: generatedInsight.content.drillRecovery,
            drillCues: generatedInsight.content.drillCues,
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
