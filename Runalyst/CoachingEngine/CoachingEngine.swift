import Foundation
import SwiftData
import FoundationModels

struct BaselineStats: Sendable {
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double
}

struct RunDataForAI: Sendable {
    let directiveContext: String
    let paceContext: String
    let hrContext: String
    let cadenceContext: String
    let zone4Context: String
    let cvContext: String
    let slopeContext: String
    let intervalCadence: String
    let recoveryCadence: String
}

struct AggregateRunDataForAI: Sendable {
    let paceContext: String
    let hrContext: String
    let cadenceContext: String
    let zone4Context: String
    let cvContext: String
    let slopeContext: String
    let stageContext: String
}

@available(iOS 26.0, *)
@Generable
struct DashboardFatigueInsight {
    @Guide(description: "Constrain strictly to a 2–4 word title. Use a positive or descriptive tone (e.g. 'Consistent Endurance', 'Acute Fatigue Detected').")
    var headline: String

    @Guide(description: "Write exactly 1 to 2 short sentences translating physiological data into relatable, everyday language. Frame feedback positively. Zero numbers.")
    var body: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestedDrill {
    @Guide(description: "A recognized drill name. Keep it extremely concise.")
    var drillTitle: String
    
    @Guide(description: "Must be exactly one of: cadence_pyramids, rhythm_intervals, tempo_surges, strides, neuromuscular_primer, aerobic_flush, fartlek_primer, hill_bounds, recovery_jog")
    var preRunDrillId: String

    @Guide(description: "Why this drill fixes their specific physiological flaws based on the coaching directive. Keep it short and direct.")
    var drillPurpose: String

    @Guide(description: "A specific biomechanical form cue. Keep it short and actionable.")
    var drillCues: String
}

@available(iOS 26.0, *)
@Generable
struct RunInsight {
    @Guide(description: "Constrain strictly to a 2–4 word title. Forbid full sentences, punctuation-heavy titles, numbers, and digits.")
    var headline: String

    @Guide(description: "Write exactly one qualitative sentence for each metric group provided in the prompt. Combine them into one cohesive, encouraging paragraph. Focus on biomechanics, be a good coach.")
    var observation: String

    @Guide(description: "One targeted short pre-run technique drill by default, with an optional second drill only when it directly reinforces the primary Swift directive. The drills together must take about 5 to 10 minutes. Do not prescribe stretches, warm-ups, cooldowns, or a full running workout. MAX 2 DRILLS.")
    var drills: [SuggestedDrill]
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    private init() {}

    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"
        
        let instructions = """
        persona: elite_running_coach
        task: synthesize_precomputed_metrics_into_coaching_advice
        rules:
        - use_a_conversational_and_motivational_tone_do_not_sound_like_a_textbook
        - speak directly to user using second person ("You", "Your")
        - you_must_strictly_follow_the_swift_directive_for_the_overall_tone_and_drill_focus
        - for the `observation` field, write exactly ONE single sentence of qualitative feedback per metric group provided. 
        - explain what the grouped trends indicate about their form and efficiency.
        - Cadence is ALWAYS SPM. Heart Rate is ALWAYS BPM. Never mix these up.
        - preRunDrillId MUST be exactly one of: cadence_pyramids, rhythm_intervals, tempo_surges, strides, neuromuscular_primer, aerobic_flush, fartlek_primer, hill_bounds, recovery_jog
        - prescribe only short technique drills to perform immediately before the next run, after the user's normal stretches and warm-up
        - generate exactly 1 targeted drill by default; add exactly 1 second drill only when it directly reinforces the primary DIRECTIVE
        - make every returned drill highly targeted to the primary DIRECTIVE; never generate unrelated drills
        - for overstriding or excessive vertical bounce, prefer cadence_pyramids or rhythm_intervals
        - for aerobic strain or heart-rate control, prefer rhythm_intervals
        - for faster pace with lower heart rate, prefer tempo_surges
        - use strides only as an optional second drill when they directly reinforce the primary DIRECTIVE
        - prefer one excellent drill over multiple generic drills
        - do not prescribe stretches, warm-ups, cooldowns, or a full running workout
        - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let useMetric = UserDefaults.standard.bool(forKey: "useMetricSystem")
        let unitContext = useMetric ? "Pace is in min/km." : "Pace is in min/mi."

        var promptTemplate = """
        You are a running coach.
        \(unitContext)
        [RUN_DATA_START]
        DIRECTIVE: {{DIRECTIVE_CONTEXT}}
        TARGET_DRILL_CADENCES:
        - INTERVAL_CADENCE: {{INTERVAL_CADENCE}}
        - RECOVERY_CADENCE: {{RECOVERY_CADENCE}}
        
        --- METRIC GROUP A: CARDIOVASCULAR EFFICIENCY ---
        HEART_RATE_BPM: {{HR_CONTEXT}}
        ZONE4_PERCENT: {{ZONE4_CONTEXT}}
        
        --- METRIC GROUP B: RUNNING ECONOMY & FORM ---
        CADENCE_SPM: {{CADENCE_CONTEXT}}
        PACE: {{PACE_CONTEXT}}
        
        --- METRIC GROUP C: PACING DYNAMICS ---
        PACE_VARIABILITY: {{CV_CONTEXT}}
        PACE_SLOPE: {{SLOPE_CONTEXT}}
        [RUN_DATA_END]
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{INTERVAL_CADENCE}}", with: runData.intervalCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{RECOVERY_CADENCE}}", with: runData.recoveryCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{DIRECTIVE_CONTEXT}}", with: runData.directiveContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{ZONE4_CONTEXT}}", with: runData.zone4Context)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CV_CONTEXT}}", with: runData.cvContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{SLOPE_CONTEXT}}", with: runData.slopeContext)

        do {
            let generatedInsight = try await session.respond(to: promptTemplate, generating: RunInsight.self)
            return generatedInsight.content
        } catch {
            print("FoundationModels Generation Error: \(error.localizedDescription)")
            return RunInsight(
                headline: String(localized: "Run Analyzed Successfully"),
                observation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
                drills: [SuggestedDrill(
                    drillTitle: String(localized: "Strides"),
                    preRunDrillId: "strides",
                    drillPurpose: String(localized: "Builds turnover and neural recruitment."),
                    drillCues: String(localized: "Focus on relaxed shoulders and quick turnover.")
                )]
            )
        }
    }
    func generateDashboardInsight(for timeFrame: String, runData: AggregateRunDataForAI) async throws -> DashboardFatigueInsight {
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"
        
        let focusDirective: String
        if timeFrame == "7 Days" {
            focusDirective = "Focus on week-over-week cadence drops, heart rate spikes, and immediate readiness for acute fatigue."
        } else if timeFrame == "30 Days" {
            focusDirective = "Focus on lactate threshold improvements, aerobic base building, and long-term trends for chronic adaptation."
        } else {
            focusDirective = "Focus on the runner's current stage progression."
        }
        
        let instructions = """
        persona: elite_running_coach
        task: evaluate_macro_physiological_trends_and_provide_conversational_insight
        rules:
        - Role & Tone: You are an empathetic, expert running coach. Your tone must be warm, encouraging, and conversational. Speak directly to the runner using "you."
        - Translate physiological data into relatable, everyday language. (e.g., instead of "acute neuromuscular fatigue," say "your legs are carrying some fatigue").
        - Always frame feedback positively. If their form is breaking down, frame it as an opportunity to recover and bounce back.
        - Strict Length: Your response must be exactly 1 to 2 short sentences.
        - Zero Numbers: Do not prescribe specific metrics, target paces, or times. Offer qualitative guidance only.
        - \(focusDirective)
        - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        var promptTemplate = """
        [AGGREGATE_DATA_START]
        TIMEFRAME: \(timeFrame)
        STAGE: {{STAGE_CONTEXT}}
        
        --- METRICS ---
        HEART_RATE_BPM: {{HR_CONTEXT}}
        ZONE4_PERCENT: {{ZONE4_CONTEXT}}
        CADENCE_SPM: {{CADENCE_CONTEXT}}
        PACE: {{PACE_CONTEXT}}
        PACE_VARIABILITY: {{CV_CONTEXT}}
        PACE_SLOPE: {{SLOPE_CONTEXT}}
        [AGGREGATE_DATA_END]
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{STAGE_CONTEXT}}", with: runData.stageContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{ZONE4_CONTEXT}}", with: runData.zone4Context)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CV_CONTEXT}}", with: runData.cvContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{SLOPE_CONTEXT}}", with: runData.slopeContext)

        do {
            let generatedInsight = try await session.respond(to: promptTemplate, generating: DashboardFatigueInsight.self)
            return generatedInsight.content
        } catch {
            print("FoundationModels Generation Error: \(error.localizedDescription)")
            return DashboardFatigueInsight(
                headline: String(localized: "Keep It Up"),
                body: String(localized: "Keep up the consistent training rhythm.")
            )
        }
    }
}

@available(iOS 26.0, *)
@ModelActor

actor RunAnalyzerActor {
    func generateAnalysis(for runID: PersistentIdentifier) async {
        guard let run = modelContext.model(for: runID) as? RunRecord else { return }

        if run.insight != nil { return } // Already analyzed

        let targetDate = run.date
        let targetID = run.id
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else {
            return
        }

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetID }
        )
        let priorRuns = (try? modelContext.fetch(descriptor)) ?? []

        var baseline: BaselineStats? = nil
        if priorRuns.count >= 3 {
            let avgPace = priorRuns.map(\.workingAvgPace).reduce(0, +) / Double(priorRuns.count)
            let avgHR = priorRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(priorRuns.count)
            let avgCadence = priorRuns.map(\.workingAvgCadence).reduce(0, +) / Double(priorRuns.count)
            baseline = BaselineStats(avgPace: avgPace, avgCadence: avgCadence, avgHR: avgHR)
        }

        let directiveContext: String
        let paceContext: String
        let hrContext: String
        let cadenceContext: String
        let zone4Context = "\(Int(run.percentZone4 * 100))% of run spent in high aerobic/anaerobic zone."
        let cvContext = "Pace Variability (CV): \(String(format: "%.3f", run.paceCV))"
        let slopeContext = "Pace Slope: \(String(format: "%.3f", run.paceSlope))"

        if let base = baseline {
            let cadenceDelta = run.workingAvgCadence - base.avgCadence
            let isCadenceImproved = cadenceDelta >= 0 || run.workingAvgCadence >= 170
            let cadenceImpact = isCadenceImproved ? "This is a GOOD trend for reducing impact." : "This is a BAD trend, increasing injury risk."
            cadenceContext = "Current: \(Int(run.workingAvgCadence)) SPM, Baseline: \(Int(base.avgCadence)) SPM, Deltas: \(Int(cadenceDelta)). \(cadenceImpact)"

            let runPace = PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)
            let basePace = PaceFormatter.formatPace(secondsPerKilometer: base.avgPace)
            let paceDiff = base.avgPace - run.workingAvgPace // positive diff means faster
            let paceImpact = paceDiff >= 0 ? "A POSITIVE trend in speed." : "A NEGATIVE trend indicating slower turnover."
            paceContext = "Current: \(runPace), Baseline: \(basePace), Deltas: \(Int(abs(paceDiff))) sec diff. \(paceImpact)"

            let hrDelta = run.workingAvgHeartRate - base.avgHR
            let hrImpact = hrDelta <= 0 ? "A GOOD trend indicating aerobic efficiency." : "A BAD trend indicating higher cardiovascular strain."
            hrContext = "Current: \(Int(run.workingAvgHeartRate)) BPM, Baseline: \(Int(base.avgHR)) BPM, Deltas: \(Int(hrDelta)). \(hrImpact)"

            if run.workingAvgCadence < 150 {
                directiveContext = "The runner is overstriding (low cadence). Prescribe a drill focused on Form, specifically quickening cadence."
            } else if paceDiff < 0 && hrDelta > 0 {
                directiveContext = "The runner was slower and had a higher heart rate than baseline, indicating fatigue or aerobic strain. Praise consistency but prescribe a drill focused on Easy Aerobic Recovery and HR control."
            } else if paceDiff > 0 && hrDelta < 0 {
                directiveContext = "The runner was faster with a lower heart rate, indicating strong fitness improvements. Praise performance and prescribe an optional Speed or Tempo drill."
            } else {
                directiveContext = "The runner is steady. Provide positive reinforcement and prescribe a general maintenance Rhythm drill."
            }
        } else {
            directiveContext = "Evaluate this isolated run and provide a basic introductory drill."
            let cadenceFloor = 150
            let cadenceStatus = Int(run.workingAvgCadence) < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(Int(run.workingAvgCadence)) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)) (No baseline available)."
            hrContext = "\(Int(run.workingAvgHeartRate)) BPM (No baseline available)."
        }

        let intervalTarget = min(180, max(150, Int(run.workingAvgCadence * 1.05)))
        let recoveryTarget = max(140, Int(run.workingAvgCadence))

        do {
            let runData = RunDataForAI(
                directiveContext: directiveContext,
                paceContext: paceContext,
                hrContext: hrContext,
                cadenceContext: cadenceContext,
                zone4Context: zone4Context,
                cvContext: cvContext,
                slopeContext: slopeContext,
                intervalCadence: "\(intervalTarget)",
                recoveryCadence: "\(recoveryTarget)"
            )

            let payload = try await CoachingEngine.shared.generateInsight(for: runData)

            let insight = CoachingInsight(
                headline: payload.headline,
                longitudinalObservation: payload.observation
            )

            var drillRecs: [DrillRecommendation] = []
            for (index, suggestedDrill) in payload.drills.enumerated() {
                let preRunId = PreRunDrillId(rawValue: suggestedDrill.preRunDrillId) ?? .strides
                let preRunDrill = PreRunDrill(id: preRunId, previousCadence: Int(run.workingAvgCadence))
                
                let targetCadenceStr = preRunDrill.computedCadence != nil ? "\(preRunDrill.computedCadence!) SPM" : nil
                
                let drill = DrillRecommendation(
                    drillTitle: suggestedDrill.drillTitle,
                    preRunDrillId: preRunId.rawValue,
                    drillPurpose: suggestedDrill.drillPurpose,
                    drillWork: preRunDrill.defaultWorkString,
                    drillCues: suggestedDrill.drillCues,
                    drillEffort: preRunDrill.defaultEffortString,
                    drillRecovery: preRunDrill.defaultRecoveryString,
                    targetCadence: targetCadenceStr,
                    previousCadence: preRunDrill.previousCadence,
                    isCompleted: false,
                    orderIndex: index
                )
                drillRecs.append(drill)
            }
            insight.drillRecommendations = drillRecs

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
