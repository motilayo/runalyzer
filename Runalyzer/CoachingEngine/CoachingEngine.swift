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
    var title: String
    var summary: String
    var drillName: String
    @Guide(description: "Strictly max 3 steps")
    var drillSteps: [String]
    var cadence: String?
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
            let paceDelta = String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), (useMetricSystem ? runData.avgPace : runData.avgPace * 1.609344) - (useMetricSystem ? baseline.avgPace : baseline.avgPace * 1.609344))
            let hrDelta = runData.avgHeartRate - baseline.avgHeartRate
            let cadDelta = runData.avgCadence - baseline.avgCadence

            runStatsPrompt += "BASELINE: \(baselineDistanceFormatted)\(distanceUnit), \(baseline.avgPace.formattedPaceString), \(baseline.avgHeartRate)BPM, \(baseline.avgCadence)SPM. DELTAS: Pace \(paceDelta)min/\(distanceUnit), HR \(hrDelta > 0 ? "+" : "")\(hrDelta), Cadence \(cadDelta > 0 ? "+" : "")\(cadDelta)\n"
        } else {
            runStatsPrompt += "BASELINE: None\n"
        }

        runStatsPrompt += "CURRENT: \(dateFormatted), \(distanceFormatted)\(distanceUnit), \(paceFormatted), \(runData.avgHeartRate)BPM, \(runData.avgCadence)SPM"

        let instructions = """
        You are a run analyst. Compare CURRENT RUN to BASELINE. Write a 1-sentence title. Write a maximum 2-sentence summary of biomechanical differences. Provide 1 specific drill (maximum 3 steps) to improve their weakest metric. Do not use jargon. Be direct.
        Drill title MUST be exactly: "Cadence Pyramids", "Rhythm Intervals", "Tempo Surges", or "Strides".
        IMPORTANT: Respond entirely in \(Locale.current.language.languageCode?.identifier ?? "en").
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
                title: String(localized: "Run Analyzed Successfully"),
                summary: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
                drillName: String(localized: "Strides"),
                drillSteps: [
                    String(localized: "4 × 20s"),
                    String(localized: "60s easy walk"),
                    String(localized: "Focus on relaxed shoulders and quick turnover.")
                ],
                cadence: nil
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
            let steps = payload.drillSteps
            let reps = steps.count > 0 ? steps[0] : ""
            let recovery = steps.count > 1 ? steps[1] : ""
            let cues = steps.count > 2 ? steps[2] : ""

            let drill = DrillRecommendation(
                drillTitle: payload.drillName,
                drillReps: reps,
                drillRecovery: recovery,
                drillCues: cues,
                targetCadence: payload.cadence,
                previousCadence: run.avgCadence,
                isCompleted: false
            )

            let insight = CoachingInsight(
                headline: payload.title,
                longitudinalObservation: payload.summary,
                drillRecommendation: drill
            )

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
