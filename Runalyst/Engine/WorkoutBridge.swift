import Foundation
import SwiftUI
@preconcurrency import WorkoutKit
import HealthKit




/// A lightweight, Sendable Data Transfer Object used to pass AI recommendations
public enum DrillDuration: Int, CaseIterable, Sendable, Codable {
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    
    public var title: String {
        "\(rawValue) min"
    }
}

public enum HapticFeedbackMode: String, CaseIterable, Sendable, Codable {
    case off = "Off"
    case on = "On"
}

/// A lightweight, Sendable Data Transfer Object used to pass AI recommendations
/// into the deterministic WorkoutKit builder.
struct DrillPrescriptionDTO: Sendable, Codable {
    let title: String
    let preRunDrillId: String?
    let purpose: String
    let targetCadence: Int?
    let previousCadence: Int?
    var durationMinutes: Int? = 15
    var hapticMode: String? = "On"
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
        let duration = DrillDuration(rawValue: dto.durationMinutes ?? 15) ?? .fifteenMinutes
        let haptic = HapticFeedbackMode(rawValue: dto.hapticMode ?? "") ?? .on
        let drill = PreRunDrill(
            id: preRunId,
            previousCadence: dto.previousCadence,
            targetCadence: dto.targetCadence,
            duration: duration,
            hapticMode: haptic
        )
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
        case .neuromuscularPrimer: return "Form Primer"
        case .aerobicFlush: return "Aerobic Flush"
        case .fartlekPrimer: return "Fartlek Primer"
        case .hillBounds: return "Hill Bounds"
        case .recoveryJog: return "Recovery Jog"
        case .aerobicBaseBuilder: return "Aerobic Base Builder"
        }
    }

    var iconName: String {
        switch self {
        case .cadencePyramids:
            return "shoeprints.fill"
        case .rhythmIntervals:
            return "clock.fill"
        case .tempoSurges:
            return "bolt.fill"
        case .strides:
            return "figure.run"
        case .neuromuscularPrimer:
            return "brain.head.profile"
        case .aerobicFlush:
            return "lungs.fill"
        case .fartlekPrimer:
            return "waveform.path.ecg"
        case .hillBounds:
            return "mountain.2.fill"
        case .recoveryJog:
            return "figure.walk"
        case .aerobicBaseBuilder:
            return "heart.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .cadencePyramids:
            return .blue
        case .rhythmIntervals:
            return .purple
        case .tempoSurges:
            return .orange
        case .strides:
            return .green
        case .neuromuscularPrimer:
            return .indigo
        case .aerobicFlush:
            return .teal
        case .fartlekPrimer:
            return .pink
        case .hillBounds:
            return .brown
        case .recoveryJog:
            return .mint
        case .aerobicBaseBuilder:
            return .red
        }
    }
}

extension PreRunDrill {
    static func iconName(for drillId: String?, title: String? = nil) -> String {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconName
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return "shoeprints.fill"
        } else if lower.contains("interval") || lower.contains("rhythm") || lower.contains("clock") {
            return "clock.fill"
        } else if lower.contains("surge") || lower.contains("tempo") {
            return "bolt.fill"
        } else if lower.contains("stride") {
            return "figure.run"
        } else if lower.contains("hill") || lower.contains("bound") {
            return "mountain.2.fill"
        } else if lower.contains("flush") || lower.contains("aerobic") {
            return "lungs.fill"
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return "figure.walk"
        } else if lower.contains("fartlek") {
            return "waveform.path.ecg"
        } else if lower.contains("neuro") {
            return "brain.head.profile"
        }
        return "shoeprints.fill"
    }

    static func iconColor(for drillId: String?, title: String? = nil) -> Color {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconColor
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return .blue
        } else if lower.contains("interval") || lower.contains("rhythm") {
            return .purple
        } else if lower.contains("surge") || lower.contains("tempo") {
            return .orange
        } else if lower.contains("stride") {
            return .green
        } else if lower.contains("hill") || lower.contains("bound") {
            return .brown
        } else if lower.contains("flush") {
            return .teal
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return .mint
        } else if lower.contains("fartlek") {
            return .pink
        } else if lower.contains("neuro") {
            return .indigo
        }
        return .orange
    }
}

struct PreRunDrill: Sendable {
    let id: PreRunDrillId
    let previousCadence: Int?
    let targetCadence: Int?
    let duration: DrillDuration
    let hapticMode: HapticFeedbackMode
    
    init(
        id: PreRunDrillId,
        previousCadence: Int? = nil,
        targetCadence: Int? = nil,
        duration: DrillDuration = .fifteenMinutes,
        hapticMode: HapticFeedbackMode = .on
    ) {
        self.id = id
        self.previousCadence = previousCadence
        self.targetCadence = targetCadence
        self.duration = duration
        self.hapticMode = hapticMode
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
    
    func workString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "4 x 1 min work"
            case .thirtyMinutes: return "6 x 90 sec work"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "5 x 45 sec work"
            case .thirtyMinutes: return "6 x 90 sec work"
            }
        case .tempoSurges:
            switch customDuration {
            case .tenMinutes: return "3 x 1 min work"
            case .fifteenMinutes: return "3 x 2 min work"
            case .thirtyMinutes: return "4 x 3 min work"
            }
        case .strides:
            switch customDuration {
            case .tenMinutes: return "4 x 15 sec strides"
            case .fifteenMinutes: return "6 x 20 sec strides"
            case .thirtyMinutes: return "8 x 30 sec strides"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes: return "6 x 45 sec work"
            }
        case .aerobicFlush:
            return "\(customDuration.rawValue) min steady"
        case .fartlekPrimer:
            switch customDuration {
            case .tenMinutes: return "4 x 45 sec work"
            case .fifteenMinutes: return "5 x 1 min work"
            case .thirtyMinutes: return "6 x 2 min work"
            }
        case .hillBounds:
            switch customDuration {
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes: return "6 x 45 sec work"
            }
        case .recoveryJog:
            return "\(customDuration.rawValue) min easy"
        case .aerobicBaseBuilder:
            return "\(customDuration.rawValue) min Zone 2 steady"
        }
    }

    func recoveryString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "90 sec walk recovery"
            case .thirtyMinutes: return "2 min walk recovery"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .tenMinutes: return "45 sec easy jog recovery"
            case .fifteenMinutes: return "75 sec easy jog recovery"
            case .thirtyMinutes: return "2 min easy jog recovery"
            }
        case .tempoSurges:
            switch customDuration {
            case .tenMinutes: return "90 sec walk recovery"
            case .fifteenMinutes: return "2 min walk recovery"
            case .thirtyMinutes: return "3 min walk recovery"
            }
        case .strides:
            switch customDuration {
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .aerobicFlush:
            return "No intervals"
        case .fartlekPrimer:
            switch customDuration {
            case .tenMinutes: return "45 sec easy recovery"
            case .fifteenMinutes: return "1 min easy recovery"
            case .thirtyMinutes: return "2 min easy recovery"
            }
        case .hillBounds:
            switch customDuration {
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .recoveryJog:
            return "No intervals"
        case .aerobicBaseBuilder:
            return "No intervals"
        }
    }

    var defaultWorkString: String {
        workString(for: duration)
    }
    
    var defaultRecoveryString: String {
        recoveryString(for: duration)
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
        
        let warmUpDuration: Double
        let coolDownDuration: Double
        
        if id == .aerobicBaseBuilder {
            warmUpDuration = duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 3.0)
            coolDownDuration = duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 2.0)
        } else if id == .aerobicFlush || id == .recoveryJog {
            warmUpDuration = 0.0
            coolDownDuration = 0.0
        } else {
            warmUpDuration = duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 4.0 : 3.0)
            coolDownDuration = duration == .tenMinutes ? 1.0 : (duration == .thirtyMinutes ? 3.0 : 2.0)
        }
        
        let warmUp = warmUpDuration > 0 ? WorkoutStep(goal: .time(warmUpDuration, .minutes)) : nil
        let coolDown = coolDownDuration > 0 ? WorkoutStep(goal: .time(coolDownDuration, .minutes)) : nil
        
        var alert: (any WorkoutAlert)? = nil
        if let target = effectiveTargetCadence {
            let cadenceValue = Double(target)
            alert = CadenceThresholdAlert.cadence(cadenceValue)
        } else if id == .aerobicBaseBuilder {
            alert = HeartRateZoneAlert(zone: 2)
        }
        
        var iterations = 1
        var workGoal = WorkoutGoal.open
        var recoveryGoal: WorkoutGoal? = nil
        
        switch id {
        case .cadencePyramids:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 4
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(90, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(2, .minutes)
            }
        case .rhythmIntervals:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(75, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(2, .minutes)
            }
        case .tempoSurges:
            switch duration {
            case .tenMinutes:
                iterations = 3
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(90, .seconds)
            case .fifteenMinutes:
                iterations = 3
                workGoal = .time(2, .minutes)
                recoveryGoal = .time(2, .minutes)
            case .thirtyMinutes:
                iterations = 4
                workGoal = .time(3, .minutes)
                recoveryGoal = .time(3, .minutes)
            }
        case .strides:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(15, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 6
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 8
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .neuromuscularPrimer:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(40, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .aerobicFlush:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
        case .fartlekPrimer:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(1, .minutes)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(2, .minutes)
                recoveryGoal = .time(2, .minutes)
            }
        case .hillBounds:
            switch duration {
            case .tenMinutes:
                iterations = 4
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(40, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .recoveryJog:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
        case .aerobicBaseBuilder:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
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

    func workString(for duration: DrillDuration) -> String {
        PreRunDrill(id: id).workString(for: duration)
    }

    func recoveryString(for duration: DrillDuration) -> String {
        PreRunDrill(id: id).recoveryString(for: duration)
    }

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
                defaultPurpose: "Practice light, quick steps to take pressure off your knees.",
                defaultWork: "4 x 1 min work",
                defaultRecovery: "2 min walk recovery",
                defaultEffort: "Moderate / Zone 3",
                calculateTargetCadence: { baseline in
                    min(185, max(150, Int(Double(baseline) * 1.05)))
                },
                generateInstructionalCue: { _ in
                    "Toes wide, light footfalls, and quick ground contact. Let your feet kiss the ground and lift quickly."
                }
            )
        case .rhythmIntervals:
            return DrillTemplate(
                id: .rhythmIntervals,
                title: "Rhythm Intervals",
                defaultPurpose: "Lock in a steady rhythm and smooth, even pace.",
                defaultWork: "5 x 45 sec work",
                defaultRecovery: "90 sec easy jog recovery",
                defaultEffort: "Moderate / Zone 3",
                calculateTargetCadence: { baseline in
                    min(185, max(152, Int(Double(baseline) * 1.06)))
                },
                generateInstructionalCue: { _ in
                    "Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel your rhythm."
                }
            )
        case .tempoSurges:
            return DrillTemplate(
                id: .tempoSurges,
                title: "Tempo Surges",
                defaultPurpose: "Get used to picking up the pace while staying relaxed.",
                defaultWork: "3 x 2 min work",
                defaultRecovery: "4 min walk recovery",
                defaultEffort: "Hard / Zone 4",
                calculateTargetCadence: { baseline in
                    min(185, max(155, Int(Double(baseline) * 1.08)))
                },
                generateInstructionalCue: { _ in
                    "Stay tall with a slight lean from your ankles. Keep hands relaxed and drive smoothly from your hips."
                }
            )
        case .strides:
            return DrillTemplate(
                id: .strides,
                title: "Strides",
                defaultPurpose: "Wake up your legs and feel fast and springy before your run.",
                defaultWork: "6 x 20 sec strides",
                defaultRecovery: "60 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    min(190, max(170, Int(Double(baseline) * 1.10)))
                },
                generateInstructionalCue: { _ in
                    "Stand tall, gaze on the horizon, drive your elbows backward, and keep your hands relaxed."
                }
            )
        case .neuromuscularPrimer:
            return DrillTemplate(
                id: .neuromuscularPrimer,
                title: "Form Primer",
                defaultPurpose: "Get your legs firing with quick, light foot strikes.",
                defaultWork: "4 x 30 sec work",
                defaultRecovery: "90 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    min(185, max(160, Int(Double(baseline) * 1.07)))
                },
                generateInstructionalCue: { _ in
                    "Land softly underneath your hips rather than reaching forward. Focus on springy, quiet steps."
                }
            )
        case .aerobicFlush:
            return DrillTemplate(
                id: .aerobicFlush,
                title: "Aerobic Flush",
                defaultPurpose: "An easy, gentle shakeout to loosen up tired legs.",
                defaultWork: "10 min steady",
                defaultRecovery: "No intervals",
                defaultEffort: "Easy / Zone 1-2",
                calculateTargetCadence: { baseline in
                    max(140, baseline)
                },
                generateInstructionalCue: { _ in
                    "Focus on your breathing—deep belly inhales and smooth exhales to let your muscles release tension."
                }
            )
        case .fartlekPrimer:
            return DrillTemplate(
                id: .fartlekPrimer,
                title: "Fartlek Primer",
                defaultPurpose: "Have fun changing gears and shifting speeds smoothly.",
                defaultWork: "5 x 1 min work",
                defaultRecovery: "2 min walk recovery",
                defaultEffort: "Hard / Zone 4",
                calculateTargetCadence: { baseline in
                    min(185, max(155, Int(Double(baseline) * 1.06)))
                },
                generateInstructionalCue: { _ in
                    "Shift your speed with your stride rhythm while keeping your upper body quiet and shoulders low."
                }
            )
        case .hillBounds:
            return DrillTemplate(
                id: .hillBounds,
                title: "Hill Bounds",
                defaultPurpose: "Build stronger push-off power and leg drive on an incline.",
                defaultWork: "5 x 30 sec work",
                defaultRecovery: "90 sec walk recovery",
                defaultEffort: "Sprint / Zone 5",
                calculateTargetCadence: { baseline in
                    max(145, baseline)
                },
                generateInstructionalCue: { _ in
                    "Pump your arms forward and up, driving through your knees and glutes with tall, powerful posture."
                }
            )
        case .recoveryJog:
            return DrillTemplate(
                id: .recoveryJog,
                title: "Recovery Jog",
                defaultPurpose: "A very easy jog to get blood moving and help your legs bounce back.",
                defaultWork: "15 min easy",
                defaultRecovery: "No intervals",
                defaultEffort: "Easy / Zone 1-2",
                calculateTargetCadence: { baseline in
                    max(140, baseline)
                },
                generateInstructionalCue: { _ in
                    "Focus on your breathing and shake out your hands. Keep your steps small, soft, and effortless."
                }
            )
        case .aerobicBaseBuilder:
            return DrillTemplate(
                id: .aerobicBaseBuilder,
                title: "Aerobic Base Builder",
                defaultPurpose: "Build your stamina engine with comfortable, conversational running.",
                defaultWork: "35 min Zone 2 steady",
                defaultRecovery: "No intervals",
                defaultEffort: "Zone 2 Aerobic",
                calculateTargetCadence: { baseline in
                    max(150, baseline)
                },
                generateInstructionalCue: { _ in
                    "Focus on calm, steady breathing so you could easily speak in full sentences throughout the run."
                }
            )
        }
    }
}
