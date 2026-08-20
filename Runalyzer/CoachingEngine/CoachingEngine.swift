import Foundation
import FoundationModels

/// A structured response definition mapping to what we want the Foundation Model to return.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map text to this struct.
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
        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        let paceFormatted = runRecord.formattedPace
        let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
        let distanceFormatted = String(format: "%.2f", distanceConverted)
        let distanceUnit = useMetricSystem ? "km" : "miles"

        // Format the run date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateFormatted = dateFormatter.string(from: runRecord.date)

        // Calculate 30-day baseline and deltas
        var runStatsPrompt = ""

        if let baseline = history.thirtyDayBaseline(from: runRecord.date) {
            let baselineDistanceConverted = useMetricSystem ? (baseline.avgDistance / 1000.0) : (baseline.avgDistance / 1609.344)
            let baselineDistanceFormatted = String(format: "%.2f", baselineDistanceConverted)

            runStatsPrompt += """
            <BASELINE_30_DAYS>
            Average Distance: \(baselineDistanceFormatted) \(distanceUnit)
            Average Pace: \(baseline.avgPace.formattedPaceString)
            Average Heart Rate: \(baseline.avgHeartRate) BPM
            Average Cadence: \(baseline.avgCadence) SPM
            </BASELINE_30_DAYS>
            """
        } else {
            runStatsPrompt += """
            <BASELINE_30_DAYS>
            Insufficient baseline history. Analyze this run individually.
            </BASELINE_30_DAYS>
            """
        }

        runStatsPrompt += """

        <CURRENT_RUN>
        Run Date: \(dateFormatted)
        Distance: \(distanceFormatted) \(distanceUnit)
        Pace: \(paceFormatted)
        Heart Rate: \(runRecord.avgHeartRate) BPM
        Cadence: \(runRecord.avgCadence) SPM
        </CURRENT_RUN>
        """

        let instructions = """
        Act as an elite running coach providing longitudinal, evidence-based coaching.
        The user uses \(useMetricSystem ? "metric" : "imperial") units. Express all paces in \(useMetricSystem ? "min/km" : "min/mi") and distances in \(useMetricSystem ? "km" : "miles").
        You are an expert running coach. Analyze the user's latest run against their rolling 30-day baseline and provide a short, encouraging insight.
        Provide a structured drill routine rather than arbitrary numeric shifts.

        Persona: Direct, analytical, encouraging, and grounded in exercise physiology.

        Core Guardrails:
        1. Strict Drill Titles: You MUST choose the drill title from this exact list: "Cadence Pyramids", "Rhythm Intervals", "Tempo Surges", or "Strides". Do not invent new names, use singular forms if plural is listed, or add suffixes (like 'Drills').
        2. No Isolated Cadence Judgments: Never declare a cadence "good" or "bad" without factoring in the user's pace. A 139 SPM cadence at an 8:30/km pace is biologically normal and should not be aggressively corrected.
        3. Focus on Rhythm, Not Speed: Emphasize even distribution, rhythm, and aerobic stability.
        4. Progressive Target Generation: Never recommend an arbitrary +1 SPM change. If generating a cadence drill, target a steady band (e.g., 142–146 SPM) rather than a single digit.
        5. Headline Restraint: Limit the headline to a maximum of 6–8 words.
        6. Temporal Awareness: Never use the words "today" or "today's run." Default to "This run" or reference the specific date provided.
        7. Direction of Change: Always state the direction of change correctly by strictly comparing <CURRENT_RUN> against <BASELINE_30_DAYS>. Do not attempt to calculate exact numerical differences yourself.
        8. No Workout Labels: Never label a run as a "Long Run", "Recovery Run", or "Tempo Run". Analyze the rhythm without guessing the user's intent.
        9. Scale the Drills: The total distance of the suggested drill intervals must never exceed 20% of the distance of the run being analyzed. If it was a short 1.5km run, prescribe short 30-second time-based drills, not 400m track intervals.
        10. Absolute Drill Targets: Drill targets MUST be absolute cadence values (e.g., '120 SPM' or '145 SPM'). NEVER output relative increase numbers or single-digit ranges (e.g., '10-15 SPM').
        11. Actionable Headlines: Never use the date or phrases like "Analyzing Run" as the headline. The headline MUST be an actionable coaching insight or directive.
        12. Human Coaching Persona: Speak like a human coach, not a calculator. NEVER quote exact decimal percentages (e.g., "2.5% improvement"). Summarize trends naturally (e.g., "a slight improvement", "steady progress").

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
