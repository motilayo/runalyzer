import Foundation
import SwiftData
import FoundationModels

/// A structured response definition mapping to what we want the Foundation Model to return.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map text to this struct.

struct BaselineStats: Sendable {
    let avgDistance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
}

struct RunDataForAI: Sendable {
    let date: Date
    let distance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
    let formattedPace: String
    let baseline: BaselineStats?
}

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
    func generateInsight(for runData: RunDataForAI) async throws -> CoachingInsightPayload {

        // Ensure Foundation Models are available on device
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        // Define the prompt string
        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        let paceFormatted = runData.formattedPace
        let distanceConverted = useMetricSystem ? (runData.distance / 1000.0) : (runData.distance / 1609.344)
        let distanceFormatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), distanceConverted)
        let distanceUnit = useMetricSystem ? "km" : "miles"

        // Format the run date
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateFormatted = dateFormatter.string(from: runData.date)

        // Calculate 30-day baseline and deltas
        var runStatsPrompt = ""

        if let baseline = runData.baseline {
            let baselineDistanceConverted = useMetricSystem ? (baseline.avgDistance / 1000.0) : (baseline.avgDistance / 1609.344)
            let baselineDistanceFormatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), baselineDistanceConverted)

            runStatsPrompt += """
            <BASELINE_30_DAYS>
            Average Distance: \(baselineDistanceFormatted) \(distanceUnit)
            Average Pace: \(baseline.avgPace.formattedPaceString)
            Average Heart Rate: \(baseline.avgHeartRate) BPM
            Average Cadence: \(baseline.avgCadence) SPM
            </BASELINE_30_DAYS>

            <DELTAS>
            Pace Delta: \(String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), (useMetricSystem ? runData.avgPace : runData.avgPace * 1.609344) - (useMetricSystem ? baseline.avgPace : baseline.avgPace * 1.609344))) min/\(distanceUnit)
            Heart Rate Delta: \(runData.avgHeartRate - baseline.avgHeartRate) BPM
            Cadence Delta: \(runData.avgCadence - baseline.avgCadence) SPM
            </DELTAS>
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
        Heart Rate: \(runData.avgHeartRate) BPM
        Cadence: \(runData.avgCadence) SPM
        </CURRENT_RUN>
        """

        let instructions = """
        Act as an elite running coach providing longitudinal, evidence-based coaching.
        The user uses \(useMetricSystem ? "metric" : "imperial") units. Express all paces in \(useMetricSystem ? "min/km" : "min/mi") and distances in \(useMetricSystem ? "km" : "miles").
        You are an expert running coach. Analyze the user's latest run against their rolling 30-day baseline and provide a short, encouraging insight.
        IMPORTANT: You must translate your final response and answer entirely in the language corresponding to this language code: \(Locale.current.language.languageCode?.identifier ?? "en").
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
        - targetCadence: Target cadence as a steady band (e.g. '142-146'), if applicable. Return null if no specific target.
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
        do {
            let generatedInsight = try await session.respond(to: prompt, generating: CoachingInsightPayload.self)

            return generatedInsight.content
        } catch {
            print("FoundationModels Generation Error: \(error.localizedDescription)")

            // Graceful fallback for unsupported languages/locales or generation failures
            return CoachingInsightPayload(
                headline: String(localized: "Run Analyzed Successfully"),
                longitudinalObservation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
                drillTitle: String(localized: "Strides"),
                drillReps: String(localized: "4 × 20s"),
                drillRecovery: String(localized: "60s easy walk"),
                drillCues: String(localized: "Focus on relaxed shoulders and quick turnover."),
                targetCadence: nil
            )
        }
    }
}

@available(iOS 26.0, *)
@ModelActor
actor RunAnalyzerActor {
    func generateAnalysis(for runID: PersistentIdentifier) async {
        // 1. Safely fetch the target run on the background thread
        guard let run = modelContext.model(for: runID) as? RunRecord else { return }

        // 2. Calculate Relative Window
        let targetDate = run.date
        let targetID = run.id
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else { return }

        // 3. Fetch past 30 days relative ONLY to this run
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetID }
        )
        let priorRuns = (try? modelContext.fetch(descriptor)) ?? []

        // 4. Swift calculates the baseline math (No AI involved)
        var baseline: BaselineStats? = nil
        if priorRuns.count >= 3 {
            let avgDistance = priorRuns.map(\.distance).reduce(0, +) / Double(priorRuns.count)
            let avgPace = priorRuns.map(\.avgPace).reduce(0, +) / Double(priorRuns.count)
            let avgHR = priorRuns.map(\.avgHeartRate).reduce(0, +) / priorRuns.count
            let avgCadence = priorRuns.map(\.avgCadence).reduce(0, +) / priorRuns.count
            baseline = BaselineStats(avgDistance: avgDistance, avgPace: avgPace, avgHeartRate: avgHR, avgCadence: avgCadence)
        }

        // 5. Run the LLM Prompt
        do {
            let runData = RunDataForAI(
                date: run.date,
                distance: run.distance,
                avgPace: run.avgPace,
                avgHeartRate: run.avgHeartRate,
                avgCadence: run.avgCadence,
                formattedPace: run.formattedPace,
                baseline: baseline
            )

            // Execute prompt asynchronously
            let payload = try await CoachingEngine.shared.generateInsight(for: runData)

            // 6. Save directly to the background context (Main UI updates automatically)
            let drill = DrillRecommendation(
                drillTitle: payload.drillTitle,
                drillReps: payload.drillReps,
                drillRecovery: payload.drillRecovery,
                drillCues: payload.drillCues,
                targetCadence: payload.targetCadence,
                previousCadence: run.avgCadence,
                isCompleted: false
            )

            let insight = CoachingInsight(
                headline: payload.headline,
                longitudinalObservation: payload.longitudinalObservation,
                drillRecommendation: drill
            )

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
