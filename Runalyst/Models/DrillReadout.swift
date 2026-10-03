import Foundation
import SwiftUI
import WorkoutKit

/// Structured, human-readable readout bridging the gap between the static dashboard
/// and the active WorkoutKit session on Apple Watch.
///
/// Provides mental preparation for the runner before the Apple Watch takes over their wrist
/// with haptic taps and timers, translating complex WorkoutKit phase data into plain English
/// and visual geometry across three conversational pillars:
/// 1. The Overview
/// 2. The Breakdown (accompanied by the visual geometry timeline)
/// 3. The Coaching Tip
struct DrillReadout: Sendable, Identifiable {
    var id: String { "\(drillId.rawValue)-\(durationMinutes)" }
    let drillId: PreRunDrillId
    let title: String
    let subtitle: String
    let overview: String
    let breakdown: String
    let coachingTip: String
    let phases: [WorkoutPhase]
    let durationMinutes: Int
    let targetCadence: String?
    let targetZone: String?

    /// Generates a standardized, conversational readout for any pre-run drill.
    static func readout(
        for drillId: PreRunDrillId,
        customTitle: String? = nil,
        targetCadence: String? = nil,
        previousCadence: Int? = nil,
        customDuration: DrillDuration? = nil
    ) -> DrillReadout {
        switch drillId {
        case .tempoSurges:
            let resolvedTitle = customTitle ?? (drillId == .tempoSurges ? "Posture Check" : drillId.title)
            let duration = customDuration ?? .tenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "160 SPM"

            let drill = PreRunDrill(
                id: .tempoSurges,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .tempoSurges,
                title: resolvedTitle,
                subtitle: "Tempo Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute mechanical reset before your main run.",
                breakdown: "You’ll start with a 2.5-minute easy warm-up jog. This is followed by 5 sets of intervals where you will run at a high, brisk cadence for 30 seconds, followed by a strict 60-second walk to catch your breath.",
                coachingTip: "A taller posture reduces vertical bounce and saves energy. Drop your shoulders, keep your eyes up, and focus on quick, light steps to hit your \(targetStr) target without sprinting.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .strides:
            let resolvedTitle = customTitle ?? "Strides"
            let duration = customDuration ?? .fifteenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" }

            let drill = PreRunDrill(
                id: .strides,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .strides,
                title: resolvedTitle,
                subtitle: "Interval Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 15-minute neuromuscular wake-up to prime your fast-twitch fibers.",
                breakdown: "You’ll start with a 5-minute easy jog to warm up the joints, followed by 6 short interval sets. In each interval, you’ll accelerate into a 20-second sprint, followed immediately by a 60-second walk to let your heart rate drop completely.",
                coachingTip: "Don't fight through fatigue. Use the full 60-second walk to recover so you can focus 100% on your form during the sprints. Drive your elbows backward and keep your hands relaxed.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .zone2Run:
            let resolvedTitle = customTitle ?? "Dynamic Activation"
            let duration = customDuration ?? .fiveMinutes

            let drill = PreRunDrill(
                id: .zone2Run,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .zone2Run,
                title: resolvedTitle,
                subtitle: "Long Run / Zone 2 Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 5-minute continuous warm-up to lubricate your joints without burning vital glycogen.",
                breakdown: "You’ll execute a single, continuous 5-minute block of low-intensity movement. There are no sprints or intervals—just a steady, progressive effort to elevate your core temperature before your long miles.",
                coachingTip: "Keep your breathing entirely through your nose. If you feel the need to open your mouth to breathe, you are pushing too hard and leaving Zone 2.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 2 (Aerobic)"
            )

        case .cadencePyramids:
            let resolvedTitle = customTitle ?? "Cadence Pyramids"
            let duration = customDuration ?? .tenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .cadencePyramids,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .cadencePyramids,
                title: resolvedTitle,
                subtitle: "Cadence & Form Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute cadence progression to eliminate overstriding and protect your knees.",
                breakdown: "You’ll start with a 2-minute easy jog warm-up. This is followed by 4 sets of intervals where you run at high cadence for 30 seconds, followed by 45 seconds of walk recovery to reset.",
                coachingTip: "Focus on landing lightly underneath your hips. Let your feet kiss the ground and lift quickly rather than reaching forward.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .rhythmIntervals:
            let resolvedTitle = customTitle ?? "Rhythm Intervals"
            let duration = customDuration ?? .tenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "162 SPM"

            let drill = PreRunDrill(
                id: .rhythmIntervals,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .rhythmIntervals,
                title: resolvedTitle,
                subtitle: "Cadence & Rhythm Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute rhythmic tempo tune-up to establish a consistent, economical cadence.",
                breakdown: "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of rhythm intervals for 30 seconds, paired with 45 seconds of relaxed recovery jog.",
                coachingTip: "Relax your shoulders and bend your elbows at 90 degrees. Let the cadence of your arms dictate the turnover of your feet.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .neuromuscularPrimer:
            let resolvedTitle = customTitle ?? "Form Primer"
            let duration = customDuration ?? .tenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "170 SPM"

            let drill = PreRunDrill(
                id: .neuromuscularPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .neuromuscularPrimer,
                title: resolvedTitle,
                subtitle: "Neuromuscular Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute quick-step activation to sharpen muscle reaction time and prime your nervous system.",
                breakdown: "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of 20-second fast-feet bursts, paired with 40 seconds of walk recovery.",
                coachingTip: "Shorten your stride and aim for high turnover. Focus on springy, quiet steps landed directly under your center of mass.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .hillBounds:
            let resolvedTitle = customTitle ?? "Hill Bounds"
            let duration = customDuration ?? .tenMinutes

            let drill = PreRunDrill(
                id: .hillBounds,
                previousCadence: previousCadence,
                targetCadence: targetCadence,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .hillBounds,
                title: resolvedTitle,
                subtitle: "Power & Stride Length Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute explosive uphill prep to build push-off power and glute drive.",
                breakdown: "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 20-second uphill bounds, followed by 40 seconds of walk recovery.",
                coachingTip: "Pump your arms forward and drive through your hips. Maintain tall posture without collapsing your chest into the incline.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetCadence,
                targetZone: nil
            )

        case .recoveryJog:
            let resolvedTitle = customTitle ?? "Recovery Jog"
            let duration = customDuration ?? .fifteenMinutes

            let drill = PreRunDrill(
                id: .recoveryJog,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .recoveryJog,
                title: resolvedTitle,
                subtitle: "Zone 1 Recovery Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 15-minute gentle flush to stimulate blood flow and release muscular tension.",
                breakdown: "You’ll execute a continuous 15-minute easy shakeout in Zone 1. No intervals or surges—just effortless, smooth steps to release stiffness.",
                coachingTip: "Keep the effort completely conversational. If you cannot speak in full sentences comfortably, slow down.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .aerobicFlush:
            let resolvedTitle = customTitle ?? "Aerobic Flush"
            let duration = customDuration ?? .tenMinutes

            let drill = PreRunDrill(
                id: .aerobicFlush,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .aerobicFlush,
                title: resolvedTitle,
                subtitle: "Active Recovery Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute recovery flush to clear metabolic fatigue.",
                breakdown: "You’ll execute a continuous 10-minute low-intensity aerobic block. There are no high-intensity spikes—just a steady, relaxed shakeout.",
                coachingTip: "Focus on deep diaphragmatic belly breathing and relaxing your neck, jaw, and shoulders.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .fartlekPrimer:
            let resolvedTitle = customTitle ?? "Fartlek Primer"
            let duration = customDuration ?? .tenMinutes
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .fartlekPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            return DrillReadout(
                drillId: .fartlekPrimer,
                title: resolvedTitle,
                subtitle: "Gear-Shifting Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a 10-minute speed-play activation to wake up gear-shifting neuromuscular patterns.",
                breakdown: "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 45-second pick-ups, alternating with 45 seconds of relaxed recovery.",
                coachingTip: "Shift your cadence smoothly between gears without tensing your upper body.",
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )
        }
    }
}

/// An item wrapper for presenting a DrillReadout in a sheet modal.
struct ActiveDrillReadoutItem: Identifiable, Sendable {
    var id: String { readout.id }
    let readout: DrillReadout
    let plan: WorkoutPlan
    let dto: DrillPrescriptionDTO
}
