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
        customDuration: DrillDuration? = nil,
        customCoachingTip: String? = nil
    ) -> DrillReadout {
        switch drillId {
        case .tempoSurges:
            let duration = customDuration ?? drillId.defaultDuration
            let resolvedTitle = customTitle ?? (drillId == .tempoSurges && duration == .tenMinutes ? "Posture Check" : drillId.title)
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "160 SPM"

            let drill = PreRunDrill(
                id: .tempoSurges,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            let breakdownText: String

            switch duration {
            case .fiveMinutes:
                overviewText = "In this drill, you will complete a 5-minute mechanical reset before your main run."
                breakdownText = "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of brisk intervals for 30 seconds, followed by 45 seconds of walk recovery."
            case .tenMinutes:
                overviewText = "In this drill, you will complete a 10-minute mechanical reset before your main run."
                breakdownText = "You’ll start with a 2.5-minute easy warm-up jog. This is followed by 5 sets of intervals where you will run at a high, brisk cadence for 30 seconds, followed by a strict 60-second walk to catch your breath."
            case .fifteenMinutes:
                overviewText = "In this drill, you will complete a 15-minute tempo surge workout to build speed endurance."
                breakdownText = "You’ll start with a 3-minute easy warm-up jog. This is followed by 3 sets of 2-minute tempo surges, paired with 2 minutes of walk recovery."
            case .thirtyMinutes:
                overviewText = "In this drill, you will complete a 30-minute tempo surge workout to build sustained speed and aerobic power."
                breakdownText = "You’ll start with a 4-minute easy warm-up jog. This is followed by 4 sets of 3-minute tempo surges, paired with 3 minutes of walk recovery, finishing with a 2-minute cool-down."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .tempoSurges).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .tempoSurges,
                title: resolvedTitle,
                subtitle: "Tempo Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .strides:
            let resolvedTitle = customTitle ?? "Strides"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" }

            let drill = PreRunDrill(
                id: .strides,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            let breakdownText: String

            switch duration {
            case .fiveMinutes:
                overviewText = "In this drill, you will complete a 5-minute neuromuscular wake-up to prime your fast-twitch fibers."
                breakdownText = "You’ll start with a 1-minute easy jog, followed by 4 short interval sets of 15-second strides and 45-second walks."
            case .tenMinutes:
                overviewText = "In this drill, you will complete a 10-minute neuromuscular wake-up to prime your fast-twitch fibers."
                breakdownText = "You’ll start with a 2-minute easy jog, followed by 4 short interval sets of 15-second strides and 45-second walks."
            case .fifteenMinutes:
                overviewText = "In this drill, you will complete a 15-minute neuromuscular wake-up to prime your fast-twitch fibers."
                breakdownText = "You’ll start with a 5-minute easy jog to warm up the joints, followed by 6 short interval sets. In each interval, you’ll accelerate into a 20-second sprint, followed immediately by a 60-second walk to let your heart rate drop completely."
            case .thirtyMinutes:
                overviewText = "In this drill, you will complete a 30-minute extended stride and neuromuscular activation workout."
                breakdownText = "You’ll start with a 5-minute easy jog, followed by 8 sets of 30-second strides and 90-second walks, finishing with a 5-minute cool-down."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .strides).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .strides,
                title: resolvedTitle,
                subtitle: "Interval Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
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

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .zone2Run).generateInstructionalCue(nil)

            return DrillReadout(
                drillId: .zone2Run,
                title: resolvedTitle,
                subtitle: "Long Run / Zone 2 Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute continuous warm-up to lubricate your joints without burning vital glycogen.",
                breakdown: "You’ll execute a single, continuous \(duration.rawValue)-minute block of low-intensity movement. There are no sprints or intervals—just a steady, progressive effort to elevate your core temperature before your long miles.",
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 2 (Aerobic)"
            )

        case .cadencePyramids:
            let resolvedTitle = customTitle ?? "Cadence Pyramids"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .cadencePyramids,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let breakdownText: String
            switch duration {
            case .fiveMinutes:
                breakdownText = "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of 20-second high cadence intervals, paired with 30 seconds of walk recovery."
            case .tenMinutes:
                breakdownText = "You’ll start with a 2-minute easy jog warm-up. This is followed by 4 sets of intervals where you run at high cadence for 30 seconds, followed by 45 seconds of walk recovery to reset."
            case .fifteenMinutes:
                breakdownText = "You’ll start with a 3-minute easy jog warm-up. This is followed by 4 sets of 1-minute high cadence intervals, paired with 90 seconds of walk recovery."
            case .thirtyMinutes:
                breakdownText = "You’ll start with a 4-minute easy jog warm-up. This is followed by 6 sets of 90-second high cadence intervals, paired with 2 minutes of walk recovery."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .cadencePyramids).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .cadencePyramids,
                title: resolvedTitle,
                subtitle: "Cadence & Form Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute cadence progression to eliminate overstriding and protect your knees.",
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .rhythmIntervals:
            let resolvedTitle = customTitle ?? "Rhythm Intervals"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "162 SPM"

            let drill = PreRunDrill(
                id: .rhythmIntervals,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            let breakdownText: String

            switch duration {
            case .fiveMinutes:
                overviewText = "In this drill, you will complete a 5-minute rhythmic tempo tune-up to establish a consistent, economical cadence."
                breakdownText = "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of rhythm intervals for 20 seconds, paired with 30 seconds of relaxed recovery jog."
            case .tenMinutes:
                overviewText = "In this drill, you will complete a 10-minute rhythmic tempo tune-up to establish a consistent, economical cadence."
                breakdownText = "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of rhythm intervals for 30 seconds, paired with 45 seconds of relaxed recovery jog."
            case .fifteenMinutes:
                overviewText = "In this drill, you will complete a 15-minute rhythmic tempo tune-up to establish a consistent, economical cadence."
                breakdownText = "You’ll start with a 3-minute easy warm-up jog. This is followed by 5 sets of rhythm intervals for 45 seconds, paired with 75 seconds of relaxed recovery jog."
            case .thirtyMinutes:
                overviewText = "In this drill, you will complete a 30-minute rhythmic tempo tune-up to establish a consistent, economical cadence."
                breakdownText = "You’ll start with a 4-minute easy warm-up jog. This is followed by 6 sets of rhythm intervals for 90 seconds, paired with 2 minutes of relaxed recovery jog."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .rhythmIntervals).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .rhythmIntervals,
                title: resolvedTitle,
                subtitle: "Cadence & Rhythm Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .neuromuscularPrimer:
            let resolvedTitle = customTitle ?? "Form Primer"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "170 SPM"

            let drill = PreRunDrill(
                id: .neuromuscularPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            let breakdownText: String

            switch duration {
            case .fiveMinutes:
                overviewText = "In this drill, you will complete a 5-minute quick-step activation to sharpen muscle reaction time and prime your nervous system."
                breakdownText = "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of 15-second fast-feet bursts, paired with 30 seconds of walk recovery."
            case .tenMinutes:
                overviewText = "In this drill, you will complete a 10-minute quick-step activation to sharpen muscle reaction time and prime your nervous system."
                breakdownText = "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of 20-second fast-feet bursts, paired with 40 seconds of walk recovery."
            case .fifteenMinutes:
                overviewText = "In this drill, you will complete a 15-minute quick-step activation to sharpen muscle reaction time and prime your nervous system."
                breakdownText = "You’ll start with a 3-minute easy warm-up jog. This is followed by 5 sets of 30-second fast-feet bursts, paired with 60 seconds of walk recovery."
            case .thirtyMinutes:
                overviewText = "In this drill, you will complete a 30-minute quick-step activation to sharpen muscle reaction time and prime your nervous system."
                breakdownText = "You’ll start with a 4-minute easy warm-up jog. This is followed by 6 sets of 45-second fast-feet bursts, paired with 90 seconds of walk recovery."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .neuromuscularPrimer).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .neuromuscularPrimer,
                title: resolvedTitle,
                subtitle: "Neuromuscular Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .hillBounds:
            let resolvedTitle = customTitle ?? "Hill Bounds"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .hillBounds,
                previousCadence: previousCadence,
                targetCadence: targetCadence,
                duration: duration
            )
            let phases = drill.generatePhases()

            let breakdownText: String
            switch duration {
            case .fiveMinutes:
                breakdownText = "You’ll start with a 1-minute warm-up jog. This is followed by 3 sets of 15-second uphill bounds, followed by 30 seconds of walk recovery."
            case .tenMinutes:
                breakdownText = "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 20-second uphill bounds, followed by 40 seconds of walk recovery."
            case .fifteenMinutes:
                breakdownText = "You’ll start with a 3-minute warm-up jog. This is followed by 5 sets of 30-second uphill bounds, followed by 60 seconds of walk recovery."
            case .thirtyMinutes:
                breakdownText = "You’ll start with a 4-minute warm-up jog. This is followed by 6 sets of 45-second uphill bounds, followed by 90 seconds of walk recovery."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .hillBounds).generateInstructionalCue(targetCadence)

            return DrillReadout(
                drillId: .hillBounds,
                title: resolvedTitle,
                subtitle: "Power & Stride Length Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute explosive uphill prep to build push-off power and glute drive.",
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetCadence,
                targetZone: nil
            )

        case .recoveryJog:
            let resolvedTitle = customTitle ?? "Recovery Jog"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .recoveryJog,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .recoveryJog).generateInstructionalCue(nil)

            return DrillReadout(
                drillId: .recoveryJog,
                title: resolvedTitle,
                subtitle: "Zone 1 Recovery Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute gentle flush to stimulate blood flow and release muscular tension.",
                breakdown: "You’ll execute a continuous \(duration.rawValue)-minute easy shakeout in Zone 1. No intervals or surges—just effortless, smooth steps to release stiffness.",
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .aerobicFlush:
            let resolvedTitle = customTitle ?? "Aerobic Flush"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .aerobicFlush,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .aerobicFlush).generateInstructionalCue(nil)

            return DrillReadout(
                drillId: .aerobicFlush,
                title: resolvedTitle,
                subtitle: "Active Recovery Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute recovery flush to clear metabolic fatigue.",
                breakdown: "You’ll execute a continuous \(duration.rawValue)-minute low-intensity aerobic block. There are no high-intensity spikes—just a steady, relaxed shakeout.",
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .fartlekPrimer:
            let resolvedTitle = customTitle ?? "Fartlek Primer"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .fartlekPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let breakdownText: String
            switch duration {
            case .fiveMinutes:
                breakdownText = "You’ll start with a 1-minute warm-up jog. This is followed by 3 sets of 30-second pick-ups, alternating with 30 seconds of relaxed recovery."
            case .tenMinutes:
                breakdownText = "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 45-second pick-ups, alternating with 45 seconds of relaxed recovery."
            case .fifteenMinutes:
                breakdownText = "You’ll start with a 3-minute warm-up jog. This is followed by 5 sets of 1-minute pick-ups, alternating with 1 minute of relaxed recovery."
            case .thirtyMinutes:
                breakdownText = "You’ll start with a 4-minute warm-up jog. This is followed by 6 sets of 2-minute pick-ups, alternating with 2 minutes of relaxed recovery."
            }

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .fartlekPrimer).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .fartlekPrimer,
                title: resolvedTitle,
                subtitle: "Gear-Shifting Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a \(duration.rawValue)-minute speed-play activation to wake up gear-shifting neuromuscular patterns.",
                breakdown: breakdownText,
                coachingTip: coachingTip,
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
