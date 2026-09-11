import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

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

#if canImport(FoundationModels)
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

    @Guide(description: "A prescriptive running form or breathing cue (e.g. 'Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you', 'Toes wide and quick ground contact', 'Focus on your breathing'). Never include SPM numbers, reps, or workout intervals.")
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
        - conversational, motivational tone; speak directly to the runner ("You", "Your")
        - strictly_follow_the_DIRECTIVE_for_tone_and_drill_selection
        - observation: write exactly ONE qualitative sentence per metric group explaining form and efficiency trends
        - Cadence is ALWAYS SPM, Heart Rate is ALWAYS BPM
        - preRunDrillId MUST be one of: cadence_pyramids, rhythm_intervals, tempo_surges, strides, neuromuscular_primer, aerobic_flush, fartlek_primer, hill_bounds, recovery_jog, zone_2_run
        - generate 1 targeted pre-run drill (max 2 if the second directly reinforces the DIRECTIVE); prefer quality over quantity
        - drill selection: overstriding → cadence_pyramids/rhythm_intervals; aerobic strain → zone_2_run/rhythm_intervals; fitness gains → tempo_surges; strides only as optional reinforcement
        - drill cues: prescriptive biomechanical/somatic cues only (posture, breathing, foot positioning). No numbers, reps, or workout stats in cues.
        - never prescribe stretches, warm-ups, cooldowns, or full workouts
        - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let useMetric = UserDefaults.standard.bool(forKey: "useMetricSystem")
        let unitContext = useMetric ? "Pace is in min/km." : "Pace is in min/mi."

        var promptTemplate = """
        \(unitContext)
        [RUN_DATA_START]
        DIRECTIVE: {{DIRECTIVE_CONTEXT}}
        DRILL_CADENCES: interval={{INTERVAL_CADENCE}}, recovery={{RECOVERY_CADENCE}}
        GROUP_A_CARDIO: HR={{HR_CONTEXT}}, ZONE4={{ZONE4_CONTEXT}}
        GROUP_B_FORM: CADENCE={{CADENCE_CONTEXT}}, PACE={{PACE_CONTEXT}}
        GROUP_C_PACING: CV={{CV_CONTEXT}}, SLOPE={{SLOPE_CONTEXT}}
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
                    drillCues: String(localized: "Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you.")
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
        task: evaluate_macro_physiological_trends
        rules:
        - warm, conversational tone; speak directly to the runner ("you"); translate data into everyday language
        - frame feedback positively; breakdowns are opportunities to recover
        - response: exactly 1–2 short sentences, zero numbers or specific metrics
        - \(focusDirective)
        - respond_entirely_in_\(language)
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let trainingGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"

        var promptTemplate = """
        [AGGREGATE_DATA_START]
        GOAL: \(trainingGoal)
        TIMEFRAME: \(timeFrame)
        STAGE: {{STAGE_CONTEXT}}
        HR: {{HR_CONTEXT}}, ZONE4: {{ZONE4_CONTEXT}}
        CADENCE: {{CADENCE_CONTEXT}}, PACE: {{PACE_CONTEXT}}
        PACE_CV: {{CV_CONTEXT}}, PACE_SLOPE: {{SLOPE_CONTEXT}}
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
#else
@available(iOS 26.0, *)
struct DashboardFatigueInsight: Sendable {
    var headline: String
    var body: String
}

@available(iOS 26.0, *)
struct SuggestedDrill: Sendable {
    var drillTitle: String
    var preRunDrillId: String
    var drillPurpose: String
    var drillCues: String
}

@available(iOS 26.0, *)
struct RunInsight: Sendable {
    var headline: String
    var observation: String
    var drills: [SuggestedDrill]
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    private init() {}

    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {
        RunInsight(
            headline: String(localized: "Run Analyzed Successfully"),
            observation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
            drills: [SuggestedDrill(
                drillTitle: String(localized: "Strides"),
                preRunDrillId: "strides",
                drillPurpose: String(localized: "Builds turnover and neural recruitment."),
                drillCues: String(localized: "Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you.")
            )]
        )
    }

    func generateDashboardInsight(for timeFrame: String, runData: AggregateRunDataForAI) async throws -> DashboardFatigueInsight {
        DashboardFatigueInsight(
            headline: String(localized: "Keep It Up"),
            body: String(localized: "Keep up the consistent training rhythm.")
        )
    }
}
#endif

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

        var baseline: BaselineStats?
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

            let trainingGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let goalSuffix = " Runner goal: \(trainingGoal)."

            if run.workingAvgCadence < 150 {
                directiveContext = "The runner is overstriding (low cadence). Prescribe a drill focused on Form, specifically quickening cadence." + goalSuffix
            } else if paceDiff < 0 && hrDelta > 0 {
                // GUARDRAIL: fatigue detected — Swift overrides goal with recovery priority
                directiveContext = "The runner was slower and had a higher heart rate than baseline, indicating fatigue or aerobic strain. PRIORITY: prescribe Easy Aerobic Recovery and HR control. Safety overrides any race goal."
            } else if paceDiff > 0 && hrDelta < 0 {
                directiveContext = "The runner was faster with a lower heart rate, indicating strong fitness improvements. Praise performance and prescribe an optional Speed or Tempo drill." + goalSuffix
            } else {
                directiveContext = "The runner is steady. Provide positive reinforcement and prescribe a general maintenance Rhythm drill." + goalSuffix
            }
        } else {
            directiveContext = "Evaluate this isolated run and provide a basic introductory drill."
            let cadenceFloor = 150
            let cadenceStatus = Int(run.workingAvgCadence) < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(Int(run.workingAvgCadence)) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)) (No baseline available)."
            hrContext = "\(Int(run.workingAvgHeartRate)) BPM (No baseline available)."
        }

        // Enforce 30-day baselines in target calculation
        let thirtyDayCadence = Int(baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155))
        let thirtyDayPace = baseline?.avgPace ?? (run.workingAvgPace > 0 ? run.workingAvgPace : 380.0)

        let defaultTemplate = DrillTemplate.template(for: .cadencePyramids)
        let intervalTarget = defaultTemplate.calculateTargetCadence(thirtyDayCadence)
        let recoveryTarget = max(140, thirtyDayCadence)

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

            let isOlderThan7Days = (Calendar.current.dateComponents([.day], from: targetDate, to: Date()).day ?? 0) > 7

            var drillRecs: [DrillRecommendation] = []
            if !isOlderThan7Days {
                for (index, suggestedDrill) in payload.drills.enumerated() {
                    let preRunId = PreRunDrillId(rawValue: suggestedDrill.preRunDrillId) ?? .strides
                    let template = DrillTemplate.template(for: preRunId)
                    let computedTarget = template.calculateTargetCadence(thirtyDayCadence)
                    let preRunDrill = PreRunDrill(id: preRunId, previousCadence: thirtyDayCadence, targetCadence: computedTarget)

                    let targetCadenceStr = preRunDrill.computedCadence.map { "\($0) SPM" }

                    // Prescriptive somatic cue (form, breathing, posture) without conflicting workout plan stats
                    let templateCue = template.generateInstructionalCue(computedTarget)
                    let drillCueText: String
                    if !suggestedDrill.drillCues.isEmpty && !suggestedDrill.drillCues.localizedCaseInsensitiveContains("spm") {
                        drillCueText = suggestedDrill.drillCues
                    } else {
                        drillCueText = templateCue
                    }

                    let drill = DrillRecommendation(
                        drillTitle: suggestedDrill.drillTitle,
                        preRunDrillId: preRunId.rawValue,
                        drillPurpose: suggestedDrill.drillPurpose.isEmpty ? template.defaultPurpose : suggestedDrill.drillPurpose,
                        drillWork: preRunDrill.defaultWorkString,
                        drillCues: drillCueText,
                        drillEffort: preRunDrill.defaultEffortString,
                        drillRecovery: preRunDrill.defaultRecoveryString,
                        targetCadence: targetCadenceStr,
                        previousCadence: preRunDrill.previousCadence,
                        isCompleted: false,
                        orderIndex: index
                    )
                    drillRecs.append(drill)
                }
            }
            insight.drillRecommendations = drillRecs

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
