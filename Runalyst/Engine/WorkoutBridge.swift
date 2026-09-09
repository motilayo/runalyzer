import Foundation
import WorkoutKit
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
actor WorkoutBridge {
    
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
