import Foundation
import SwiftUI
import HealthKit
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

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
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return "heart.fill"
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
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return .red
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

/// Represents an instantiated pre-run drill with user-specific cadence targets,
/// duration, and native WorkoutKit plan compilation capabilities.
struct PreRunDrill: Sendable {
    let id: PreRunDrillId
    let previousCadence: Int?
    let targetCadence: String?
    let duration: DrillDuration
    let hapticMode: HapticFeedbackMode

    init(
        id: PreRunDrillId,
        previousCadence: Int? = nil,
        targetCadence: String? = nil,
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

    var effectiveTargetCadence: ClosedRange<Int>? {
        // Recovery / flush / base builder drills do not use cadence turnover alerts
        switch id {
        case .aerobicFlush, .recoveryJog, .zone2Run:
            return nil
        default:
            break
        }

        if let target = targetCadence, target.contains("-") {
            let parts = target.components(separatedBy: "-")
            if parts.count == 2,
               let lower = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               let upper = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let safeLower = min(safeMaxCadence, max(safeMinCadence, lower))
                let safeUpper = min(safeMaxCadence, max(safeMinCadence, upper))
                return min(safeLower, safeUpper)...max(safeLower, safeUpper)
            }
        } else if let target = targetCadence,
                  let targetInt = Int(target.replacingOccurrences(of: " SPM", with: "").trimmingCharacters(in: .whitespaces)) {
            let safeTarget = min(safeMaxCadence, max(safeMinCadence, targetInt))
            return max(safeMinCadence, safeTarget - 3)...min(safeMaxCadence, safeTarget + 3)
        }

        if let prev = previousCadence, prev > 0 {
            let baseTarget = Int(Double(prev) * 1.05)
            let safeTarget = min(safeMaxCadence, max(prev, baseTarget))
            return max(safeMinCadence, safeTarget - 3)...min(safeMaxCadence, safeTarget + 3)
        }
        return nil
    }

    var computedCadence: String? {
        guard let range = effectiveTargetCadence else { return nil }
        return "\(range.lowerBound)-\(range.upperBound)"
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
        case .zone2Run:
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
        case .zone2Run:
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
        case .recoveryJog, .aerobicFlush: return "Zone 1 Active Recovery"
        case .zone2Run: return "Zone 2 Aerobic"
        case .cadencePyramids, .rhythmIntervals: return "Moderate / Zone 3"
        case .tempoSurges, .fartlekPrimer: return "Hard / Zone 4"
        case .strides, .neuromuscularPrimer, .hillBounds: return "Sprint / Zone 5"
        }
    }

    #if canImport(WorkoutKit)
    @available(iOS 17.0, *)
    func buildWorkoutPlan() -> WorkoutPlan {
        var workout = CustomWorkout(activity: .running, location: .outdoor, displayName: id.title)

        let warmUpDuration: Double
        let coolDownDuration: Double

        if id == .zone2Run {
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

        var alert: (any WorkoutAlert)?
        if let target = effectiveTargetCadence {
            alert = CadenceRangeAlert.cadence(Double(target.lowerBound)...Double(target.upperBound))
        } else if id == .aerobicFlush || id == .recoveryJog {
            alert = HeartRateZoneAlert(zone: 1)
        } else if id == .zone2Run {
            alert = HeartRateZoneAlert(zone: 2)
        }

        var iterations = 1
        var workGoal = WorkoutGoal.open
        var recoveryGoal: WorkoutGoal?

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
        case .zone2Run:
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
    #endif
}
