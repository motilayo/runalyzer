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
    let avgVerticalOscillation: Double
    let avgVo2Max: Double
    let avgGroundContactTime: Double
    let avgStrideLength: Double
}

struct RunDataForAI: Sendable {
    let directiveContext: String
    let vo2Context: String
    let cadenceContext: String
    let paceContext: String
    let hrContext: String
    let vertOscContext: String
    let gctContext: String
    let strideContext: String
    let targetCadenceContext: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestedDrill {
    @Guide(description: "A recognized drill name (e.g., 'Cadence Pyramids', 'Rhythm Intervals', 'Tempo Surges', 'Strides').")
    var drillTitle: String

    @Guide(description: "Why this drill fixes their specific physiological flaws based on the coaching directive. Keep it short and direct.")
    var drillPurpose: String

    @Guide(description: "Combine sets, reps, active target cadence, AND recovery instructions into a single cohesive field.")
    var drillWork: String

    @Guide(description: "A specific biomechanical or mental form cue to execute during the drill. Keep it short and actionable.")
    var drillCues: String

    @Guide(description: "The intended intensity level or Rate of Perceived Exertion (RPE) for the drill (e.g., 'Moderate aerobic effort', 'RPE 7/10', 'Hard but controlled').")
    var drillEffort: String

}

@available(iOS 26.0, *)
@Generable
struct RunInsight {
    @Guide(description: "A short, encouraging title. YOU MUST NOT use the drill name here.")
    var headline: String

    @Guide(description: "Synthesize the context strings and provide feedback driven by the run context. DO NOT include drill steps or give instructions. Keep it short and meaningful, 3 sentences or less.")
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
          - you_must_strictly_follow_the_swift_directive_for_the_overall_tone_and_drill_focus
          - observation_must_not_contain_drill_steps
          - do_not_invent_or_calculate_math_in_the_observation_only_synthesize_the_strings
          - use_gait_metrics_to_diagnose_overstriding_or_bouncing
          - drill_target_cadence_must_be_between_150_and_180_spm
          - never_prescribe_cadence_below_150_spm
          - no_conversational_filler
          - use_a_conversational_and_motivational_tone_do_not_sound_like_a_textbook
          - drill_title_must_be_one_of: [Cadence Pyramids, Rhythm Intervals, Tempo Surges, Strides]
          - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        var promptTemplate = """
        context:
          swift_directive: {{DIRECTIVE_CONTEXT}}
          target_cadence: {{TARGET_CADENCE_CONTEXT}}
          global_fitness_vo2: {{VO2_CONTEXT}}
          cadence_analysis: {{CADENCE_CONTEXT}}
          pace_analysis: {{PACE_CONTEXT}}
          heart_rate_analysis: {{HR_CONTEXT}}
          vertical_oscillation: {{OSCILLATION_CONTEXT}}
          ground_contact_time: {{GCT_CONTEXT}}
          stride_length: {{STRIDE_CONTEXT}}
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{TARGET_CADENCE_CONTEXT}}", with: runData.targetCadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{DIRECTIVE_CONTEXT}}", with: runData.directiveContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{VO2_CONTEXT}}", with: runData.vo2Context)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{OSCILLATION_CONTEXT}}", with: runData.vertOscContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{GCT_CONTEXT}}", with: runData.gctContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{STRIDE_CONTEXT}}", with: runData.strideContext)

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
                    drillTitle: String(localized: "Strides"),
                    drillPurpose: String(localized: "Builds turnover and neural recruitment."),
                    drillWork: String(localized: "4 × 20s with 60s easy walk recovery"),
                    drillCues: String(localized: "Focus on relaxed shoulders and quick turnover."),
                    drillEffort: String(localized: "Comfortably hard"),
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
            let avgVertOsc = priorRuns.map(\.verticalOscillation).reduce(0, +) / Double(priorRuns.count)

            let runsWithVo2 = priorRuns.filter { $0.vo2Max > 0 }
            let avgVo2Max = runsWithVo2.isEmpty ? 0.0 : runsWithVo2.map(\.vo2Max).reduce(0, +) / Double(runsWithVo2.count)

            let avgGct = priorRuns.map(\.groundContactTime).reduce(0, +) / Double(priorRuns.count)
            let avgStride = priorRuns.map(\.strideLength).reduce(0, +) / Double(priorRuns.count)

            baseline = BaselineStats(avgDistance: avgDistance, avgPace: avgPace, avgHeartRate: avgHR, avgCadence: avgCadence, avgVerticalOscillation: avgVertOsc, avgVo2Max: avgVo2Max, avgGroundContactTime: avgGct, avgStrideLength: avgStride)
        }

        // Precompute Context Strings for LLM
        let directiveContext: String
        let vo2Context: String
        let cadenceContext: String
        let paceContext: String
        let hrContext: String
        let vertOscContext: String
        let gctContext: String
        let strideContext: String

        if let base = baseline {
            // VO2 Max Logic
            if run.vo2Max > 0 && base.avgVo2Max > 0 {
                let vo2Delta = run.vo2Max - base.avgVo2Max
                let vo2Trend = vo2Delta == 0 ? "Steady compared to baseline" : (vo2Delta > 0 ? String(format: "+%.1f HIGHER than baseline", vo2Delta) : String(format: "%.1f LOWER than baseline", abs(vo2Delta)))
                vo2Context = String(format: "%.1f (%@).", run.vo2Max, vo2Trend)
            } else if run.vo2Max > 0 {
                vo2Context = String(format: "%.1f (No baseline available).", run.vo2Max)
            } else {
                vo2Context = "No VO2 Max data recorded for this run."
            }

            // Cadence Logic
            let cadenceFloor = 150
            let cadenceStatus = run.avgCadence < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            let cadenceDelta = run.avgCadence - base.avgCadence
            let cadenceTrend = cadenceDelta >= 0 ? "+\(cadenceDelta) SPM higher than baseline" : "\(abs(cadenceDelta)) SPM lower than baseline"
            cadenceContext = "\(run.avgCadence) SPM (\(cadenceStatus). \(cadenceTrend))."

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

            // Vertical Oscillation Logic
            let vertOscDelta = run.verticalOscillation - base.avgVerticalOscillation
            let vertOscTrend = vertOscDelta >= 0 ? String(format: "+%.1f cm MORE bounce than baseline", vertOscDelta) : String(format: "%.1f cm LESS bounce than baseline", abs(vertOscDelta))
            vertOscContext = String(format: "%.1f cm (%@).", run.verticalOscillation, vertOscTrend)

            // Ground Contact Time Logic
            let gctDelta = run.groundContactTime - base.avgGroundContactTime
            let gctTrend = gctDelta >= 0 ? String(format: "+%.0f ms LONGER contact than baseline", gctDelta) : String(format: "%.0f ms SHORTER contact than baseline", abs(gctDelta))
            gctContext = String(format: "%.0f ms (%@).", run.groundContactTime, gctTrend)

            // Stride Length Logic
            let strideDelta = run.strideLength - base.avgStrideLength
            let strideTrend = strideDelta >= 0 ? String(format: "+%.2f m LONGER stride than baseline", strideDelta) : String(format: "%.2f m SHORTER stride than baseline", abs(strideDelta))
            strideContext = String(format: "%.2f m (%@).", run.strideLength, strideTrend)

            // Directive Logic (Swift Diagnoses the Issue)
            if run.avgCadence < 150 || (run.verticalOscillation > 10.0 && run.verticalOscillation > base.avgVerticalOscillation) {
                directiveContext = "The runner is either bounding too much (high vertical oscillation) or overstriding (low cadence). Prescribe a drill focused on Form, specifically quickening cadence and reducing vertical bounce."
            } else if paceDiff < 0 && hrDelta > 0 {
                directiveContext = "The runner was slower and had a higher heart rate than baseline, indicating fatigue or aerobic strain. Praise consistency but prescribe a drill focused on Easy Aerobic Recovery and HR control."
            } else if paceDiff > 0 && hrDelta < 0 {
                directiveContext = "The runner was faster with a lower heart rate, indicating strong fitness improvements. Praise performance and prescribe an optional Speed or Tempo drill."
            } else {
                directiveContext = "The runner is steady. Provide positive reinforcement and prescribe a general maintenance Rhythm drill."
            }

        } else {
            directiveContext = "Evaluate this isolated run and provide a basic introductory drill."
            vo2Context = run.vo2Max > 0 ? String(format: "%.1f (No baseline available).", run.vo2Max) : "No VO2 Max data recorded for this run."
            let cadenceFloor = 150
            let cadenceStatus = run.avgCadence < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(run.avgCadence) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(run.formattedPace) (No baseline available)."
            hrContext = "\(run.avgHeartRate) BPM (No baseline available)."
            vertOscContext = String(format: "%.1f cm (No baseline available).", run.verticalOscillation)
            gctContext = String(format: "%.0f ms (No baseline available).", run.groundContactTime)
            strideContext = String(format: "%.2f m (No baseline available).", run.strideLength)
        }

        let targetCadence = min(180, max(150, Int(Double(run.avgCadence) * 1.05)))
        let targetCadenceContext = "\(targetCadence) SPM"

        // 5. Run the LLM Prompt
        do {
            let runData = RunDataForAI(
                directiveContext: directiveContext,
                vo2Context: vo2Context,
                cadenceContext: cadenceContext,
                paceContext: paceContext,
                hrContext: hrContext,
                vertOscContext: vertOscContext,
                gctContext: gctContext,
                strideContext: strideContext,
                targetCadenceContext: targetCadenceContext
            )

            // Execute prompt asynchronously
            let payload = try await CoachingEngine.shared.generateInsight(for: runData)

            // 6. Save directly to the background context (Main UI updates automatically)
            let drill = DrillRecommendation(
                drillTitle: payload.drill.drillTitle,
                drillPurpose: payload.drill.drillPurpose,
                drillWork: payload.drill.drillWork,
                drillCues: payload.drill.drillCues,
                drillEffort: payload.drill.drillEffort,
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
