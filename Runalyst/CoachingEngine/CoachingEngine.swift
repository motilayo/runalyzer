import Foundation
import SwiftData
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "CoachingEngine")

struct BaselineStats: Sendable {
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double
    let avgOscillation: Double
}

struct RunDataForAI: Sendable {
    let workoutType: String
    let runnerGoal: String
    let directiveContext: String
    let paceContext: String
    let hrContext: String
    let cadenceContext: String
    let zone4Context: String
    let cvContext: String
    let slopeContext: String
    let intervalCadence: String
    let recoveryCadence: String

    init(
        workoutType: String = "Steady Effort",
        runnerGoal: String = "Base Building",
        directiveContext: String,
        paceContext: String,
        hrContext: String,
        cadenceContext: String,
        zone4Context: String,
        cvContext: String,
        slopeContext: String,
        intervalCadence: String,
        recoveryCadence: String
    ) {
        self.workoutType = workoutType
        self.runnerGoal = runnerGoal
        self.directiveContext = directiveContext
        self.paceContext = paceContext
        self.hrContext = hrContext
        self.cadenceContext = cadenceContext
        self.zone4Context = zone4Context
        self.cvContext = cvContext
        self.slopeContext = slopeContext
        self.intervalCadence = intervalCadence
        self.recoveryCadence = recoveryCadence
    }
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
    @Guide(description: "Constrain strictly to a 2–4 word title. Use a positive or descriptive tone.")
    var headline: String

    @Guide(description: "Write exactly 1 to 2 short sentences translating physiological data into relatable, everyday language. Frame feedback positively. Zero numbers.")
    var body: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestedDrill {
    @Guide(description: "A clear and concise drill name.")
    var drillTitle: String

    @Guide(description: "Must be exactly one of: cadence_pyramids, rhythm_intervals, tempo_surges, strides, neuromuscular_primer, aerobic_flush, fartlek_primer, hill_bounds, recovery_jog")
    var preRunDrillId: String

    @Guide(description: "1 concise sentence explaining why this drill addresses the runner's specific focus area based on the coaching directive.")
    var drillPurpose: String

    @Guide(description: "A single somatic form or breathing cue to focus on during the drill (e.g. 'Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you', 'Quick, light foot turnover underneath your hips'). Never include SPM numbers, reps, or workout intervals.")
    var drillCues: String
}

@available(iOS 26.0, *)
@Generable
struct RunInsight {
    @Guide(description: "A concise 2–4 word title capturing the run's theme (e.g. 'Strong Cadence Rhythm', 'Aerobic Efficiency Win'). Forbid full sentences, punctuation-heavy titles, numbers, and digits.")
    var headline: String

    @Guide(description: "A warm, cohesive 2–3 sentence coaching analysis. Commend improvements or consistency, highlight where form or efficiency has room to grow, and introduce the drill. Do not recite numbers, digits, or somatic drill cues.")
    var observation: String

    @Guide(description: "One targeted short pre-run technique drill by default, with an optional second drill only when it directly reinforces the primary Swift directive. The drills together must take about 5 to 10 minutes. Do not prescribe stretches, warm-ups, cooldowns, or a full running workout. MAX 2 DRILLS.")
    var drills: [SuggestedDrill]
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    var inFlightTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private init() {}

    func requestAnalysis(for runRecord: RunRecord, force: Bool = false) async {
        let runId = runRecord.persistentModelID
        guard let container = runRecord.modelContext?.container else { return }

        if let existingTask = inFlightTasks[runId] {
            _ = await existingTask.value
            return
        }

        if force, let oldInsight = runRecord.insight {
            runRecord.modelContext?.delete(oldInsight)
            runRecord.insight = nil
            try? runRecord.modelContext?.save()
        }

        let task = Task.detached {
            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId, force: force)
        }

        inFlightTasks[runId] = task
        _ = await task.value
        inFlightTasks[runId] = nil
    }

    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"

        let instructions = """
        You are an encouraging, insightful running coach speaking directly to the athlete using "you" and "your".

        Your goal is to translate their workout metrics and baseline trends into conversational coaching:
        1. Commend where they showed improvement or consistency (e.g. cadence rhythm, aerobic efficiency, or pacing control).
        2. Highlight where there is room for improvement (e.g. cadence drop under fatigue, cardiac strain, or pacing decay).
        3. Recommend a targeted pre-run drill to help them progress toward their goal.

        Speak naturally and warmly like an experienced human coach. Keep the observation to a fluid, cohesive 2–3 sentences.
        Respond entirely in \(language).
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let useMetric = UserDefaults.standard.bool(forKey: "useMetricSystem")
        let unitContext = useMetric ? "Pace is in min/km." : "Pace is in min/mi."

        var promptTemplate = """
        How was my run coach?
        Speak directly using "you" and "your"
        [RUN_DATA_START]
        WORKOUT_TYPE: {{WORKOUT_TYPE}}
        RUNNER_GOAL: {{RUNNER_GOAL}}
        DIRECTIVE: {{DIRECTIVE_CONTEXT}}
        TARGET_DRILL_CADENCES:
        - INTERVAL_CADENCE: {{INTERVAL_CADENCE}}
        - RECOVERY_CADENCE: {{RECOVERY_CADENCE}}

        --- CARDIOVASCULAR EFFICIENCY ---
        HEART_RATE_BPM: {{HR_CONTEXT}}
        ZONE4_PERCENT: {{ZONE4_CONTEXT}}

        --- RUNNING ECONOMY & FORM ---
        CADENCE_SPM: {{CADENCE_CONTEXT}}
        PACE: {{PACE_CONTEXT}}
        \(unitContext)

        --- PACING DYNAMICS ---
        PACE_VARIABILITY: {{CV_CONTEXT}}
        PACE_SLOPE: {{SLOPE_CONTEXT}}
        \(unitContext)

        [RUN_DATA_END]
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{WORKOUT_TYPE}}", with: runData.workoutType)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{RUNNER_GOAL}}", with: runData.runnerGoal)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{INTERVAL_CADENCE}}", with: runData.intervalCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{RECOVERY_CADENCE}}", with: runData.recoveryCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{DIRECTIVE_CONTEXT}}", with: runData.directiveContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{ZONE4_CONTEXT}}", with: runData.zone4Context)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CV_CONTEXT}}", with: runData.cvContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{SLOPE_CONTEXT}}", with: runData.slopeContext)

        let prompt = promptTemplate

        do {
            let insightContent = try await ModelInferenceSerializer.shared.run {
                let response = try await session.respond(to: prompt, generating: RunInsight.self)
                return response.content
            }
            return insightContent
        } catch {
            logger.error("FoundationModels Generation Error: \(error.localizedDescription)")
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
        rules:
        - Empathetic running coach; warm, encouraging, conversational tone speaking directly to runner ("you").
        - Translate physiological data into relatable language; frame feedback positively.
        - Strict Length: maximum of 3 short sentences.
        - Tailor feedback to GOAL.
        - Zero Numbers: no specific metrics, target paces, or times.
        - \(focusDirective)
        - respond_entirely_in_\(language), plain and simple.
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let trainingGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"

        var promptTemplate = """
        This runner's goes is \(trainingGoal). Give them feedback.
        [AGGREGATE_DATA_START]
        GOAL: \(trainingGoal)
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

        let dashboardPrompt = promptTemplate

        do {
            let insightContent = try await ModelInferenceSerializer.shared.run {
                let response = try await session.respond(to: dashboardPrompt, generating: DashboardFatigueInsight.self)
                return response.content
            }
            return insightContent
        } catch {
            logger.error("FoundationModels Generation Error: \(error.localizedDescription)")
            return DashboardFatigueInsight(
                headline: String(localized: "Keep It Up"),
                body: String(localized: "Keep up the consistent training rhythm.")
            )
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private actor ModelInferenceSerializer {
    static let shared = ModelInferenceSerializer()
    private var queue: [(CheckedContinuation<Void, Never>)] = []
    private var isExecuting = false

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if isExecuting {
            await withCheckedContinuation { continuation in
                queue.append(continuation)
            }
        }
        isExecuting = true
        defer {
            isExecuting = false
            if !queue.isEmpty {
                let next = queue.removeFirst()
                next.resume()
            }
        }
        return try await work()
    }
}
#endif
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

    var inFlightTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private init() {}

    func requestAnalysis(for runRecord: RunRecord, force: Bool = false) async {
        let runId = runRecord.persistentModelID
        guard let container = runRecord.modelContext?.container else { return }

        if let existingTask = inFlightTasks[runId] {
            _ = await existingTask.value
            return
        }

        if force, let oldInsight = runRecord.insight {
            runRecord.modelContext?.delete(oldInsight)
            runRecord.insight = nil
            try? runRecord.modelContext?.save()
        }

        let task = Task.detached {
            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId, force: force)
        }

        inFlightTasks[runId] = task
        _ = await task.value
        inFlightTasks[runId] = nil
    }

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
    func generateAnalysis(for runID: PersistentIdentifier, force: Bool = false) async {
        guard let run = modelContext.model(for: runID) as? RunRecord else { return }

        if !force && run.insight != nil { return } // Already analyzed

        // GUARDRAIL: A run must have at least cadence or heart rate sensor data.
        // Runs recorded without an Apple Watch have zero biomechanical metrics.
        // Generating form coaching on zero sensor data results in model hallucinations.
        guard run.workingAvgCadence > 0 || run.workingAvgHeartRate > 0 else {
            logger.info("Skipping AI insight for run \(run.date): insufficient biometric data (no cadence or HR).")
            if let oldInsight = run.insight {
                modelContext.delete(oldInsight)
                run.insight = nil
                try? modelContext.save()
            }
            return
        }

        let targetDate = run.date
        let targetID = run.id
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else {
            return
        }

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetID }
        )
        let priorRuns = (try? modelContext.fetch(descriptor)) ?? []

        // Every run counts with classification-aware weighting
        // Steady, Easy, and Long runs provide primary aerobic anchor (1.0x).
        // Tempo, Progression, and Recovery runs provide secondary aerobic context (0.8x).
        // High-intensity interval drills contribute (0.3x) without distorting aerobic endurance baselines.
        let validRuns = priorRuns.filter { $0.workingAvgPace > 0 && $0.duration > 0 }

        func aerobicWeight(for r: RunRecord) -> Double {
            switch r.detectedTypeRaw {
            case "Steady Effort", "Easy Run", "Long Run":
                return 1.0 * r.duration
            case "Tempo Run", "Progression Run", "Recovery Run":
                return 0.8 * r.duration
            case "Intervals", "Pyramids", "Fartlek":
                return 0.3 * r.duration
            default:
                return 0.7 * r.duration
            }
        }

        var baseline: BaselineStats?
        if validRuns.count >= 3 {
            let totalWeight = validRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
            if totalWeight > 0 {
                let weightedPace = validRuns.map { $0.workingAvgPace * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedHR = validRuns.map { $0.workingAvgHeartRate * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedCadence = validRuns.map { $0.workingAvgCadence * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedOsc = validRuns.map { ($0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation ?? 9.5) * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                baseline = BaselineStats(avgPace: weightedPace, avgCadence: weightedCadence, avgHR: weightedHR, avgOscillation: weightedOsc)
            }
        }

        var directiveContext: String
        let paceContext: String
        let hrContext: String
        let cadenceContext: String
        let zone4Context = "\(Int(run.percentZone4 * 100))% of run spent in high aerobic/anaerobic zone."
        let cvContext = "Pace Variability (CV): \(String(format: "%.3f", run.paceCV))"
        let slopeContext = "Pace Slope: \(String(format: "%.3f", run.paceSlope))"

        if let base = baseline {
            let cadenceDelta = run.workingAvgCadence - base.avgCadence
            let isCadenceImproved = cadenceDelta >= 0 || run.workingAvgCadence >= 170
            let cadenceSummary: String
            if isCadenceImproved {
                if run.workingAvgCadence >= 170 && cadenceDelta < 0 {
                    cadenceSummary = "Cadence averaged an optimal \(Int(run.workingAvgCadence)) SPM, maintaining strong turnover above the 170 SPM efficiency zone despite a slight drop."
                } else if cadenceDelta > 0 {
                    cadenceSummary = "Cadence increased by \(Int(cadenceDelta)) SPM, showing lighter foot turnover and reduced impact."
                } else {
                    cadenceSummary = "Cadence held steady at \(Int(run.workingAvgCadence)) SPM, matching baseline."
                }
            } else {
                cadenceSummary = "Cadence dropped by \(Int(abs(cadenceDelta))) SPM, indicating slower turnover or longer ground contact."
            }
            cadenceContext = "Current: \(Int(run.workingAvgCadence)) SPM, Baseline: \(Int(base.avgCadence)) SPM, Deltas: \(Int(cadenceDelta)). \(cadenceSummary)"

            let runPace = PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)
            let basePace = PaceFormatter.formatPace(secondsPerKilometer: base.avgPace)
            let paceDiff = base.avgPace - run.workingAvgPace // positive diff means faster
            let paceSummary: String
            if paceDiff > 0 {
                paceSummary = "Pace was \(Int(abs(paceDiff))) sec faster than baseline, showing strong aerobic power."
            } else if paceDiff < 0 {
                paceSummary = "Pace was \(Int(abs(paceDiff))) sec slower than baseline, reflecting a controlled or fatiguing effort."
            } else {
                paceSummary = "Pace held consistent with baseline."
            }
            paceContext = "Current: \(runPace), Baseline: \(basePace), Deltas: \(Int(abs(paceDiff))) sec diff. \(paceSummary)"

            let hrDelta = run.workingAvgHeartRate - base.avgHR
            let hrSummary: String
            if hrDelta < 0 {
                hrSummary = "Heart rate was \(Int(abs(hrDelta))) BPM lower than baseline, indicating improved cardiovascular efficiency."
            } else if hrDelta > 0 {
                hrSummary = "Heart rate was \(Int(hrDelta)) BPM higher than baseline, reflecting cardiovascular strain or higher effort."
            } else {
                hrSummary = "Heart rate remained stable, matching baseline."
            }
            hrContext = "Current: \(Int(run.workingAvgHeartRate)) BPM, Baseline: \(Int(base.avgHR)) BPM, Deltas: \(Int(hrDelta)). \(hrSummary)"

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
            let isolatedType = !run.detectedTypeRaw.isEmpty ? run.detectedTypeRaw : "Steady Effort"
            directiveContext = "Evaluate this isolated \(isolatedType) and provide a basic introductory drill."
            let cadenceFloor = 150
            let cadenceStatus = Int(run.workingAvgCadence) < cadenceFloor ? "BELOW the \(cadenceFloor) SPM floor" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(Int(run.workingAvgCadence)) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)) (No baseline available)."
            hrContext = "\(Int(run.workingAvgHeartRate)) BPM (No baseline available)."
        }

        // Check for recognized drill or previously prescribed drill execution
        let isCurrentRunDrill = run.framboiseTags.contains("prescribedDrill")
        if isCurrentRunDrill {
            // Find drill ID from tags
            let tags = run.framboiseTags.split(separator: ",").map(String.init).map { $0.trimmingCharacters(in: .whitespaces) }
            let drillIdStr = tags.first(where: { $0.hasPrefix("drill:") })?.replacingOccurrences(of: "drill:", with: "")
            let drillTitle = PreRunDrillId(rawValue: drillIdStr ?? "")?.title ?? run.detectedTypeRaw

            let thirtyDayCadence = Int(baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155))
            let actualCadence = Int(run.workingAvgCadence)

            var targetCadenceStr = "Steady"
            var inTargetStr = "OFF_TARGET"
            if let drillId = PreRunDrillId(rawValue: drillIdStr ?? "") {
                let template = DrillTemplate.template(for: drillId)
                let targetCadence = template.calculateTargetCadence(thirtyDayCadence)
                let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
                if let computed = drillObj.computedCadence {
                    targetCadenceStr = computed
                    if let range = drillObj.effectiveTargetCadence {
                        if range.contains(actualCadence) {
                            inTargetStr = "IN_TARGET"
                        } else if actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2 {
                            inTargetStr = "IN_TARGET (Close)"
                        }
                    }
                }
            }

            let currentOsc = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation ?? 9.5
            let baseOsc = baseline?.avgOscillation ?? 9.5
            let oscDelta = currentOsc - baseOsc
            let oscDeltaStr = String(format: "%+.1f", oscDelta)

            directiveContext = """
            DRILL_EVALUATION: The runner completed their prescribed \(drillTitle) drill.
            TARGET: \(targetCadenceStr) | ACTUAL: \(actualCadence) SPM (\(inTargetStr)).
            VERTICAL_FORM: \(oscDeltaStr) cm change.
            DIRECTIVE: Commend turnover discipline and form adherence. Speak directly to drill technique and rhythm stability.
            """
        } else if let lastRun = priorRuns.sorted(by: { $0.date > $1.date }).first,
           let lastInsight = lastRun.insight,
           let prescribedDrill = lastInsight.drillRecommendations?.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }).first {
            if prescribedDrill.isCompleted {
                directiveContext += " Prior drill completed: \(prescribedDrill.drillTitle) (target: \(prescribedDrill.targetCadence ?? "steady"), actual: \(Int(run.workingAvgCadence)) SPM)."
            } else {
                directiveContext += " Prior drill prescribed: \(prescribedDrill.drillTitle) (pending execution)."
            }
        }

        // Target-specific weighting:
        // When determining interval drill targets, weight prior interval runs highest (1.0x), then tempo (0.6x), then steady (0.2x).
        let intervalCandidateRuns = priorRuns.filter { $0.workingAvgCadence > 0 }
        func intervalTargetWeight(for r: RunRecord) -> Double {
            switch r.detectedTypeRaw {
            case "Intervals", "Pyramids":
                return 1.0 * r.duration
            case "Tempo Run", "Progression Run":
                return 0.6 * r.duration
            case "Fartlek":
                return 0.5 * r.duration
            default:
                return 0.2 * r.duration
            }
        }

        let totalIntervalWeight = intervalCandidateRuns.map { intervalTargetWeight(for: $0) }.reduce(0, +)
        let intervalCadenceBase: Double
        if totalIntervalWeight > 0 {
            intervalCadenceBase = intervalCandidateRuns.map { $0.workingAvgCadence * intervalTargetWeight(for: $0) }.reduce(0, +) / totalIntervalWeight
        } else {
            intervalCadenceBase = baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155)
        }

        let thirtyDayCadence = Int(baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155))
        let defaultTemplate = DrillTemplate.template(for: .cadencePyramids)
        let intervalTarget = defaultTemplate.calculateTargetCadence(Int(intervalCadenceBase))
        let recoveryTarget = max(140, thirtyDayCadence)

        let workoutType = !run.detectedTypeRaw.isEmpty ? run.detectedTypeRaw : "Steady Effort"
        let currentGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"

        do {
            let runData = RunDataForAI(
                workoutType: workoutType,
                runnerGoal: currentGoal,
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
            modelContext.insert(insight)

            let isOlderThan7Days = (Calendar.current.dateComponents([.day], from: targetDate, to: Date()).day ?? 0) > 7

            var drillRecs: [DrillRecommendation] = []
            if !isOlderThan7Days {
                for (index, suggestedDrill) in payload.drills.enumerated() {
                    let preRunId = PreRunDrillId(rawValue: suggestedDrill.preRunDrillId) ?? .strides
                    let template = DrillTemplate.template(for: preRunId)
                    let effectiveCadence = max(thirtyDayCadence, Int(run.workingAvgCadence))
                    let computedTarget = template.calculateTargetCadence(effectiveCadence)
                    let preRunDrill = PreRunDrill(id: preRunId, previousCadence: effectiveCadence, targetCadence: computedTarget)

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
                    modelContext.insert(drill)
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
