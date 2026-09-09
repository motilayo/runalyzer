import Foundation
@preconcurrency import WorkoutKit
import HealthKit




/// A lightweight, Sendable Data Transfer Object used to pass AI recommendations
/// into the deterministic WorkoutKit builder.
struct DrillPrescriptionDTO: Sendable {
    let title: String
    let preRunDrillId: String?
    let purpose: String
    let targetCadence: Int?
    let previousCadence: Int?
}

/// A deterministic calculator that applies physiological guardrails to AI prescriptions.
/// Ensures the AI does not prescribe dangerous target thresholds.
enum SafeTargetCalculator {
    /// Caps the prescribed cadence alert range to a maximum of 185 SPM to prevent overstriding.
    static func safeCadenceTarget(requestedCadence: Int?, previousCadence: Int?) -> HKQuantity? {
        guard let requested = requestedCadence else { return nil }
        
        let safeMax = 185
        let floor = max(140, previousCadence ?? 150)
        let safeTarget = min(safeMax, max(floor, requested))
        
        return HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(safeTarget))
    }
}

/// The bridge between Runalyst's CoreML/AI outputs and Apple's WorkoutKit.
/// Translates `DrillPrescriptionDTO` into a native `WorkoutPlan`.
@available(iOS 17.0, *)
@MainActor
final class WorkoutBridge {
    
    /// Translates a DTO into a scheduled WorkoutKit plan for Apple Watch.
    func scheduleDrill(dto: DrillPrescriptionDTO) async throws {
        if await WorkoutScheduler.shared.authorizationState != .authorized {
            let status = await WorkoutScheduler.shared.requestAuthorization()
            guard status == .authorized else {
                throw NSError(domain: "WorkoutBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "WorkoutKit authorization denied."])
            }
        }
        
        let preRunId = PreRunDrillId(rawValue: dto.preRunDrillId ?? "") ?? .strides
        let drill = PreRunDrill(id: preRunId, previousCadence: dto.previousCadence, targetCadence: dto.targetCadence)
        let plan = drill.buildWorkoutPlan()
        
        let now = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: Date())
        await WorkoutScheduler.shared.schedule(plan, at: now)
    }
}




enum PreRunDrillId: String, CaseIterable, Codable, Sendable {
    case cadencePyramids = "cadence_pyramids"
    case rhythmIntervals = "rhythm_intervals"
    case tempoSurges = "tempo_surges"
    case strides = "strides"
    case neuromuscularPrimer = "neuromuscular_primer"
    case aerobicFlush = "aerobic_flush"
    case fartlekPrimer = "fartlek_primer"
    case hillBounds = "hill_bounds"
    case recoveryJog = "recovery_jog"
    case aerobicBaseBuilder = "aerobic_base_builder"
    
    var title: String {
        switch self {
        case .cadencePyramids: return "Cadence Pyramids"
        case .rhythmIntervals: return "Rhythm Intervals"
        case .tempoSurges: return "Tempo Surges"
        case .strides: return "Strides"
        case .neuromuscularPrimer: return "Neuromuscular Primer"
        case .aerobicFlush: return "Aerobic Flush"
        case .fartlekPrimer: return "Fartlek Primer"
        case .hillBounds: return "Hill Bounds"
        case .recoveryJog: return "Recovery Jog"
        case .aerobicBaseBuilder: return "Aerobic Base Builder"
        }
    }
}

struct PreRunDrill: Sendable {
    let id: PreRunDrillId
    let previousCadence: Int?
    let targetCadence: Int?
    
    init(id: PreRunDrillId, previousCadence: Int? = nil, targetCadence: Int? = nil) {
        self.id = id
        self.previousCadence = previousCadence
        self.targetCadence = targetCadence
    }
    
    // Mathematical variables for constraints
    private let safeMaxCadence = 185
    private let safeMinCadence = 140
    
    var effectiveTargetCadence: Int? {
        // Recovery / flush / base builder drills do not use cadence turnover alerts
        switch id {
        case .aerobicFlush, .recoveryJog, .aerobicBaseBuilder:
            return nil
        default:
            break
        }
        
        if let target = targetCadence, target > 0 {
            return min(safeMaxCadence, max(safeMinCadence, target))
        }
        if let prev = previousCadence, prev > 0 {
            let baseTarget = Int(Double(prev) * 1.05)
            return min(safeMaxCadence, max(prev, baseTarget))
        }
        return nil
    }
    
    var computedCadence: Int? {
        return effectiveTargetCadence
    }
    
    var defaultWorkString: String {
        switch id {
        case .cadencePyramids: return "4 x 1 min work"
        case .rhythmIntervals: return "5 x 45 sec work"
        case .tempoSurges: return "3 x 2 min work"
        case .strides: return "6 x 20 sec strides"
        case .neuromuscularPrimer: return "4 x 30 sec work"
        case .aerobicFlush: return "10 min steady"
        case .fartlekPrimer: return "5 x 1 min work"
        case .hillBounds: return "5 x 30 sec work"
        case .recoveryJog: return "15 min easy"
        case .aerobicBaseBuilder: return "35 min Zone 2 steady"
        }
    }
    
    var defaultRecoveryString: String {
        switch id {
        case .cadencePyramids: return "2 min walk recovery"
        case .rhythmIntervals: return "90 sec easy jog recovery"
        case .tempoSurges: return "4 min walk recovery"
        case .strides: return "60 sec walk recovery"
        case .neuromuscularPrimer: return "90 sec walk recovery"
        case .aerobicFlush: return "No intervals"
        case .fartlekPrimer: return "2 min walk recovery"
        case .hillBounds: return "90 sec walk recovery"
        case .recoveryJog: return "No intervals"
        case .aerobicBaseBuilder: return "No intervals"
        }
    }
    
    var defaultEffortString: String {
        switch id {
        case .recoveryJog, .aerobicFlush: return "Easy / Zone 1-2"
        case .aerobicBaseBuilder: return "Zone 2 Aerobic"
        case .cadencePyramids, .rhythmIntervals: return "Moderate / Zone 3"
        case .tempoSurges, .fartlekPrimer: return "Hard / Zone 4"
        case .strides, .neuromuscularPrimer, .hillBounds: return "Sprint / Zone 5"
        }
    }
    
    @available(iOS 17.0, *)
    func buildWorkoutPlan() -> WorkoutPlan {
        var workout = CustomWorkout(activity: .running, location: .outdoor, displayName: id.title)
        
        let warmUpDuration: Double = (id == .aerobicBaseBuilder) ? 5.0 : 3.0
        let coolDownDuration: Double = (id == .aerobicBaseBuilder) ? 5.0 : 2.0
        let warmUp = WorkoutStep(goal: .time(warmUpDuration, .minutes))
        let coolDown = WorkoutStep(goal: .time(coolDownDuration, .minutes))
        
        var alert: (any WorkoutAlert)? = nil
        if let target = effectiveTargetCadence {
            let cadenceValue = Double(target)
            let lower = max(120.0, cadenceValue - 5.0)
            let upper = min(200.0, cadenceValue + 5.0)
            alert = CadenceRangeAlert.cadence(lower...upper)
        } else if id == .aerobicBaseBuilder {
            alert = HeartRateZoneAlert(zone: 2)
        }
        
        var iterations = 1
        var workGoal = WorkoutGoal.open
        var recoveryGoal: WorkoutGoal? = nil
        
        switch id {
        case .cadencePyramids:
            iterations = 4; workGoal = .time(1, .minutes); recoveryGoal = .time(2, .minutes)
        case .rhythmIntervals:
            iterations = 5; workGoal = .time(45, .seconds); recoveryGoal = .time(90, .seconds)
        case .strides:
            iterations = 6; workGoal = .time(20, .seconds); recoveryGoal = .time(60, .seconds)
        case .tempoSurges:
            iterations = 3; workGoal = .time(2, .minutes); recoveryGoal = .time(4, .minutes)
        case .neuromuscularPrimer:
            iterations = 4; workGoal = .time(30, .seconds); recoveryGoal = .time(90, .seconds)
        case .aerobicFlush:
            iterations = 1; workGoal = .time(10, .minutes); recoveryGoal = nil
        case .fartlekPrimer:
            iterations = 5; workGoal = .time(1, .minutes); recoveryGoal = .time(2, .minutes)
        case .hillBounds:
            iterations = 5; workGoal = .time(30, .seconds); recoveryGoal = .time(90, .seconds)
        case .recoveryJog:
            iterations = 1; workGoal = .time(10, .minutes); recoveryGoal = nil
        case .aerobicBaseBuilder:
            iterations = 1; workGoal = .time(35, .minutes); recoveryGoal = nil
        }
        
        let workStep = WorkoutStep(goal: workGoal, alert: alert)
        
        if let rec = recoveryGoal {
            let recStep = WorkoutStep(goal: rec)
            workout.blocks = [IntervalBlock(steps: [IntervalStep(.work, step: workStep), IntervalStep(.recovery, step: recStep)], iterations: iterations)]
        } else {
            workout.blocks = [IntervalBlock(steps: [IntervalStep(.work, step: workStep)], iterations: iterations)]
        }
        
        workout.warmup = warmUp
        workout.cooldown = coolDown
        
        return WorkoutPlan(.custom(workout))
    }
}

/// Defines a standardized pre-run corrective drill template with target closures
/// that enforce thirty-day user baselines over transient local run metrics.
struct DrillTemplate: Sendable {
    let id: PreRunDrillId
    let title: String
    let defaultPurpose: String
    let defaultWork: String
    let defaultRecovery: String
    let defaultEffort: String
    
    /// Target calculation closures enforcing 30-day user baselines
    let calculateTargetCadence: @Sendable (_ thirtyDayCadence: Int) -> Int
    let calculateTargetPace: @Sendable (_ thirtyDayPace: Double) -> Double
    
    /// Instructional text interpolating the computed target output from the closure
    let generateInstructionalCue: @Sendable (_ computedTargetCadence: Int) -> String

    init(
        id: PreRunDrillId,
        title: String,
        defaultPurpose: String,
        defaultWork: String,
        defaultRecovery: String,
        defaultEffort: String,
        calculateTargetCadence: @escaping @Sendable (Int) -> Int,
        calculateTargetPace: @escaping @Sendable (Double) -> Double = { $0 },
        generateInstructionalCue: @escaping @Sendable (Int) -> String
    ) {
        self.id = id
        self.title = title
        self.defaultPurpose = defaultPurpose
        self.defaultWork = defaultWork
        self.defaultRecovery = defaultRecovery
        self.defaultEffort = defaultEffort
        self.calculateTargetCadence = calculateTargetCadence
        self.calculateTargetPace = calculateTargetPace
        self.generateInstructionalCue = generateInstructionalCue
    }
    
    static func template(for id: PreRunDrillId) -> DrillTemplate {
        switch id {
        case .cadencePyramids:
            return DrillTemplate(
                id: .cadencePyramids,
                title: "Cadence Pyramids",
                defaultPurpose: "Improve running economy and quicken turnover to reduce braking forces.",
                defaultWork: "4 x 1 min work",
                defaultRecovery: "2 min walk recovery",
                defaultEffort: "Moderate / Zone 3",
                calculateTargetCadence: { baseline in
                    min(185, max(150, Int(Double(baseline) * 1.05)))
                },
                generateInstructionalCue: { target in
                    "Maintain a steady \(target) SPM with a slight forward lean and relaxed shoulders."
                }
            )
        case .rhythmIntervals:
            return DrillTemplate(
                id: .rhythmIntervals,
                title: "Rhythm Intervals",
                defaultPurpose: "Develop metronomic rhythm and aerobic pacing stability.",
                defaultWork: "5 x 45 sec work",
                defaultRecovery: "90 sec easy jog recovery",
                defaultEffort: "Moderate / Zone 3",
                calculateTargetCadence: { baseline in
                    min(185, max(152, Int(Double(baseline) * 1.06)))
                },
                generateInstructionalCue: { target in
                    "Lock into a consistent \(target) SPM rhythm, focusing on quick ground turnover."
                }
            )
        case .tempoSurges:
            return DrillTemplate(
                id: .tempoSurges,
                title: "Tempo Surges",
                defaultPurpose: "Prime lactate clearance and dynamic turnover under higher effort.",
                defaultWork: "3 x 2 min work",
                defaultRecovery: "4 min walk recovery",
                defaultEffort: "Hard / Zone 4",
                calculateTargetCadence: { baseline in
                    min(185, max(155, Int(Double(baseline) * 1.08)))
                },
                generateInstructionalCue: { target in
                    "Accelerate smoothly to reach \(target) SPM while staying relaxed through your upper body."
                }
            )
        case .strides:
            return DrillTemplate(
                id: .strides,
                title: "Strides",
                defaultPurpose: "Neuromuscular priming and rapid motor unit recruitment.",
                defaultWork: "6 x 20 sec strides",
                defaultRecovery: "60 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    min(190, max(170, Int(Double(baseline) * 1.10)))
                },
                generateInstructionalCue: { target in
                    "Build turnover up to \(target) SPM over 20 seconds with tall posture and powerful arm drive."
                }
            )
        case .neuromuscularPrimer:
            return DrillTemplate(
                id: .neuromuscularPrimer,
                title: "Neuromuscular Primer",
                defaultPurpose: "Wake up running mechanics and shorten ground contact time.",
                defaultWork: "4 x 30 sec work",
                defaultRecovery: "90 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    min(185, max(160, Int(Double(baseline) * 1.07)))
                },
                generateInstructionalCue: { target in
                    "Focus on rapid foot strike turnover targeting \(target) SPM with minimal vertical bounce."
                }
            )
        case .aerobicFlush:
            return DrillTemplate(
                id: .aerobicFlush,
                title: "Aerobic Flush",
                defaultPurpose: "Gentle low-impact movement to promote blood flow and recovery.",
                defaultWork: "10 min steady",
                defaultRecovery: "No intervals",
                defaultEffort: "Easy / Zone 1-2",
                calculateTargetCadence: { baseline in
                    max(140, baseline)
                },
                generateInstructionalCue: { _ in
                    "Keep the effort conversational in Zone 1-2, letting your legs flush fatigue."
                }
            )
        case .fartlekPrimer:
            return DrillTemplate(
                id: .fartlekPrimer,
                title: "Fartlek Primer",
                defaultPurpose: "Play with rhythm transitions without high cardiovascular strain.",
                defaultWork: "5 x 1 min work",
                defaultRecovery: "2 min walk recovery",
                defaultEffort: "Hard / Zone 4",
                calculateTargetCadence: { baseline in
                    min(185, max(155, Int(Double(baseline) * 1.06)))
                },
                generateInstructionalCue: { target in
                    "Alternate between easy rhythm and surging to \(target) SPM."
                }
            )
        case .hillBounds:
            return DrillTemplate(
                id: .hillBounds,
                title: "Hill Bounds",
                defaultPurpose: "Develop propulsive leg drive and posterior chain strength.",
                defaultWork: "5 x 30 sec work",
                defaultRecovery: "90 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    max(145, baseline)
                },
                generateInstructionalCue: { target in
                    "Drive through your hips on each stride, sustaining \(target) SPM up the gradient."
                }
            )
        case .recoveryJog:
            return DrillTemplate(
                id: .recoveryJog,
                title: "Recovery Jog",
                defaultPurpose: "Active recovery to stimulate circulation without muscular stress.",
                defaultWork: "15 min easy",
                defaultRecovery: "No intervals",
                defaultEffort: "Easy / Zone 1-2",
                calculateTargetCadence: { baseline in
                    max(140, baseline)
                },
                generateInstructionalCue: { _ in
                    "Maintain an effortless, relaxed jog prioritizing low heart rate."
                }
            )
        case .aerobicBaseBuilder:
            return DrillTemplate(
                id: .aerobicBaseBuilder,
                title: "Aerobic Base Builder",
                defaultPurpose: "Zone 2 aerobic conditioning to build mitochondrial density.",
                defaultWork: "35 min Zone 2 steady",
                defaultRecovery: "No intervals",
                defaultEffort: "Zone 2 Aerobic",
                calculateTargetCadence: { baseline in
                    max(150, baseline)
                },
                generateInstructionalCue: { target in
                    "Sustain a rhythmic \(target) SPM turnover while keeping heart rate strictly within Zone 2."
                }
            )
        }
    }
}
