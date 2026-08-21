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
    let cadenceContext: String
    let paceContext: String
    let hrContext: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestedDrill {
    var drillName: String
    @Guide(description: "Strictly max 3 steps")
    var drillSteps: [String]
    var cadence: String?
}

@available(iOS 26.0, *)
@Generable
struct RunInsight {
    @Guide(description: "A short, encouraging title (e.g., 'Solid Pace Improvement'). DO NOT use the drill name here.")
    var headline: String

    @Guide(description: "STRICTLY 2 or 3 sentences maximum. Synthesize the context strings. DO NOT include drill instructions or steps in this field.")
    var observation: String

    var drill: SuggestedDrill
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    private init() {}

    /// Analyzes a run record and generates a CoachingInsight using on-device FoundationModels
    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {

        // Ensure Foundation Models are available on device
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let instructions = """
        persona: elite_running_coach
        task: synthesize_precomputed_metrics_into_coaching_advice
        rules:
          - speak_directly_to_user_using_second_person ("You", "Your")
          - observation_must_not_contain_drill_steps
          - drill_target_cadence_must_be_between_150_and_180_spm
          - never_prescribe_cadence_below_150_spm
          - no_conversational_filler
          - drill_title_must_be_one_of: [Cadence Pyramids, Rhythm Intervals, Tempo Surges, Strides]
          - target_cadence_generation_must_be_absolute_e_g_120_spm_or_142_146
          - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        var promptTemplate = """
        context:
          cadence_analysis: {{CADENCE_CONTEXT}}
          pace_analysis: {{PACE_CONTEXT}}
          heart_rate_analysis: {{HR_CONTEXT}}
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)

        let prompt = promptTemplate

        // Execute the prompt expecting the @Generable struct output
        do {
            let generatedInsight = try await session.respond(to: prompt, generating: RunInsight.self)

            return generatedInsight.content
        } catch {
            print("FoundationModels Generation Error: \(error.localizedDescription)")

            // Graceful fallback for unsupported languages/locales or generation failures
            return RunInsight(
                headline: String(localized: "Run Analyzed Successfully"),
                observation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
                drill: SuggestedDrill(
                    drillName: String(localized: "Strides"),
                    drillSteps: [
                        String(localized: "4 × 20s"),
                        String(localized: "60s easy walk"),
                        String(localized: "Focus on relaxed shoulders and quick turnover.")
                    ],
                    cadence: nil
                )
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

        // Precompute Context Strings for LLM
        let cadenceContext: String
        let paceContext: String
        let hrContext: String

        if let base = baseline {
            // Cadence Logic
            let cadenceFloor = 150
            let cadenceStatus = run.avgCadence < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            let cadenceDelta = run.avgCadence - base.avgCadence
            let cadenceTrend = cadenceDelta >= 0 ? "+\(cadenceDelta) SPM higher than baseline" : "\(abs(cadenceDelta)) SPM lower than baseline"
            cadenceContext = "\(run.avgCadence) SPM (\(cadenceStatus). \(cadenceTrend))."

            // Pace Logic
            // Assuming average pace is stored in minutes per kilometer as a Double
            // We convert to total seconds for easier comparison
            let runPaceSeconds = Int(run.avgPace * 60)
            let basePaceSeconds = Int(base.avgPace * 60)
            let paceDiff = basePaceSeconds - runPaceSeconds // Positive = faster
            let paceTrend = paceDiff >= 0 ? "\(abs(paceDiff)) seconds FASTER than baseline" : "\(abs(paceDiff)) seconds SLOWER than baseline"
            paceContext = "\(run.formattedPace) (\(paceTrend))."

            // HR Logic
            let hrDelta = run.avgHeartRate - base.avgHeartRate
            let hrTrend = hrDelta <= 0 ? "\(abs(hrDelta)) BPM LOWER than baseline" : "+\(hrDelta) BPM HIGHER than baseline"
            hrContext = "\(run.avgHeartRate) BPM (\(hrTrend))."
        } else {
            let cadenceFloor = 150
            let cadenceStatus = run.avgCadence < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(run.avgCadence) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(run.formattedPace) (No baseline available)."
            hrContext = "\(run.avgHeartRate) BPM (No baseline available)."
        }

        // 5. Run the LLM Prompt
        do {
            let runData = RunDataForAI(
                cadenceContext: cadenceContext,
                paceContext: paceContext,
                hrContext: hrContext
            )

            // Execute prompt asynchronously
            let payload = try await CoachingEngine.shared.generateInsight(for: runData)

            // 6. Save directly to the background context (Main UI updates automatically)
            let steps = payload.drill.drillSteps
            let reps = steps.count > 0 ? steps[0] : ""
            let recovery = steps.count > 1 ? steps[1] : ""
            let cues = steps.count > 2 ? steps[2] : ""

            let drill = DrillRecommendation(
                drillTitle: payload.drill.drillName,
                drillReps: reps,
                drillRecovery: recovery,
                drillCues: cues,
                targetCadence: payload.drill.cadence,
                previousCadence: run.avgCadence,
                isCompleted: false
            )

            let insight = CoachingInsight(
                headline: payload.headline,
                longitudinalObservation: payload.observation,
                drillRecommendation: drill
            )

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
