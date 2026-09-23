import Foundation

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
    let calculateTargetCadence: @Sendable (_ thirtyDayCadence: Int) -> String
    let calculateTargetPace: @Sendable (_ thirtyDayPace: Double) -> Double

    /// Instructional text interpolating the computed target output from the closure
    let generateInstructionalCue: @Sendable (_ computedTargetCadence: String?) -> String

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
        calculateTargetCadence: @escaping @Sendable (Int) -> String,
        calculateTargetPace: @escaping @Sendable (Double) -> Double = { $0 },
        generateInstructionalCue: @escaping @Sendable (String?) -> String
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
                    let target = min(185, max(150, Int(Double(baseline) * 1.05)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                    let target = min(185, max(152, Int(Double(baseline) * 1.06)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                defaultRecovery: "4 min tempo base",
                defaultEffort: "Hard / Zone 4",
                calculateTargetCadence: { baseline in
                    let target = min(185, max(155, Int(Double(baseline) * 1.08)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                    let target = min(190, max(170, Int(Double(baseline) * 1.10)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                    let target = min(185, max(160, Int(Double(baseline) * 1.07)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                defaultEffort: "Zone 1 Active Recovery",
                calculateTargetCadence: { baseline in
                    let target = max(140, baseline)
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                    let target = min(185, max(155, Int(Double(baseline) * 1.06)))
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                    let target = max(145, baseline)
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
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
                defaultEffort: "Zone 1 Active Recovery",
                calculateTargetCadence: { baseline in
                    let target = max(140, baseline)
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
                },
                generateInstructionalCue: { _ in
                    "Focus on your breathing and shake out your hands. Keep your steps small, soft, and effortless."
                }
            )
        case .zone2Run:
            return DrillTemplate(
                id: id,
                title: "Zone 2 Run",
                defaultPurpose: "Build your stamina and aerobic engine with comfortable, conversational Zone 2 effort.",
                defaultWork: "Steady Zone 2 pace",
                defaultRecovery: "No intervals",
                defaultEffort: "Zone 2 Aerobic",
                calculateTargetCadence: { baseline in
                    let target = max(150, baseline)
                    return "\(max(140, target - 3))-\(min(190, target + 3))"
                },
                generateInstructionalCue: { _ in
                    "Focus on calm nasal breathing and a conversational pace, keeping your heart rate steadily locked in Zone 2."
                }
            )
        }
    }
}
