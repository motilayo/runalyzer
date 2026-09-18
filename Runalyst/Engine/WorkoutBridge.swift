import Foundation
import SwiftUI
@preconcurrency import WorkoutKit
import HealthKit

#if canImport(WorkoutKit)
@available(iOS 17.0, macCatalyst 18.0, macOS 15.0, watchOS 10.0, *)
extension WorkoutScheduler.AuthorizationState: @retroactive @unchecked Sendable {}
#endif

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
    let targetCadence: String?
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

/// Represents an active or recent intent to execute a prescribed drill on Apple Watch.
public struct ScheduledDrillIntent: Codable, Sendable, Equatable {
    public let drillTitle: String
    public let preRunDrillId: String?
    public let scheduledDate: Date
    public let durationMinutes: Int
    public let targetCadence: String?
    public var matchedWorkoutID: UUID?

    public init(
        drillTitle: String,
        preRunDrillId: String? = nil,
        scheduledDate: Date = Date(),
        durationMinutes: Int = 15,
        targetCadence: String? = nil,
        matchedWorkoutID: UUID? = nil
    ) {
        let cleanTitle = PreRunDrillId.canonicalDrillTitle(for: drillTitle)
            ?? preRunDrillId.flatMap { PreRunDrillId(rawValue: $0)?.title }
            ?? drillTitle.replacingOccurrences(of: "_", with: " ").capitalized
        self.drillTitle = cleanTitle
        self.preRunDrillId = preRunDrillId
        self.scheduledDate = scheduledDate
        self.durationMinutes = durationMinutes
        self.targetCadence = targetCadence
        self.matchedWorkoutID = matchedWorkoutID
    }
}

/// The bridge between Runalyst's CoreML/AI outputs and Apple's WorkoutKit.
/// Translates `DrillPrescriptionDTO` into a native `WorkoutPlan`.
@available(iOS 17.0, *)
@MainActor
final class WorkoutBridge {

    nonisolated private static let drillIntentsKey = "recentDrillIntents"

    nonisolated public static func clearIntents() {
        UserDefaults.standard.removeObject(forKey: drillIntentsKey)
    }

    nonisolated public static func saveDrillIntent(_ intent: ScheduledDrillIntent) {
        var intents = recentIntents()
        // If updating an intent (like marking as matched), replace the old one
        if let index = intents.firstIndex(where: { $0.scheduledDate == intent.scheduledDate && $0.drillTitle == intent.drillTitle }) {
            intents[index] = intent
        } else {
            // Supersede any pending (unmatched) intents scheduled within the last 30 minutes.
            // A newly scheduled drill overrides any accidental previous drill taps.
            intents.removeAll { $0.matchedWorkoutID == nil && abs($0.scheduledDate.timeIntervalSince(intent.scheduledDate)) < 1800 }
            intents.append(intent)
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600) // Retain 30 days of intents
        intents = intents.filter { $0.scheduledDate >= cutoff }
        if let data = try? JSONEncoder().encode(intents) {
            UserDefaults.standard.set(data, forKey: drillIntentsKey)
        }
    }

    nonisolated public static func recentIntents() -> [ScheduledDrillIntent] {
        guard let data = UserDefaults.standard.data(forKey: drillIntentsKey),
              let intents = try? JSONDecoder().decode([ScheduledDrillIntent].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600) // Retain 30 days of intents
        return intents.filter { $0.scheduledDate >= cutoff }
    }

    nonisolated private static func extractAllStrings(from dict: [String: Any]?) -> [String] {
        guard let dict = dict else { return [] }
        var result: [String] = []
        for (k, val) in dict {
            result.append(k)
            if let s = val as? String {
                result.append(s)
            } else if let arr = val as? [String] {
                result.append(contentsOf: arr)
            } else if let arrOfDict = val as? [[String: Any]] {
                for d in arrOfDict {
                    result.append(contentsOf: extractAllStrings(from: d))
                }
            } else if let subDict = val as? [String: Any] {
                result.append(contentsOf: extractAllStrings(from: subDict))
            }
        }
        return result
    }

    nonisolated public static func matchDrill(
        workout: HKWorkout,
        durationSeconds: Double
    ) -> ScheduledDrillIntent? {
        let workoutDate = workout.startDate
        var allMetadataStrings: [String] = []

        // Extract metadata strings recursively from workout
        allMetadataStrings.append(contentsOf: extractAllStrings(from: workout.metadata))

        // Extract metadata strings from workout activities
        for activity in workout.workoutActivities {
            allMetadataStrings.append(contentsOf: extractAllStrings(from: activity.metadata))
        }

        // Extract metadata strings from workout events
        if let events = workout.workoutEvents {
            for event in events {
                allMetadataStrings.append(contentsOf: extractAllStrings(from: event.metadata))
            }
        }

        // 1. Direct Metadata Check (highest priority: authentic HealthKit/WorkoutKit workout title)
        for text in allMetadataStrings {
            for candidate in PreRunDrillId.allCases {
                if text.localizedCaseInsensitiveContains(candidate.title) ||
                   (!candidate.rawValue.isEmpty && text.localizedCaseInsensitiveContains(candidate.rawValue)) {
                    return ScheduledDrillIntent(
                        drillTitle: candidate.title,
                        preRunDrillId: candidate.rawValue,
                        scheduledDate: workoutDate,
                        durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                    )
                }
            }
        }

        // 2. Intent Heuristic Fallback (scheduled drill within 48h of workout)
        let intents = recentIntents()
        let matchingIntents = intents.filter { intent in
            if let matchedID = intent.matchedWorkoutID, matchedID != workout.uuid { return false }
            let timeDiff = workoutDate.timeIntervalSince(intent.scheduledDate)
            guard timeDiff >= -3600 && timeDiff <= 48 * 3600 else { return false }

            let expectedDuration = Double(intent.durationMinutes * 60)
            if durationSeconds > 0 {
                let tolerance = max(expectedDuration * 0.60, 600.0)
                let durationDiff = abs(durationSeconds - expectedDuration)
                guard durationDiff <= tolerance else { return false }
            }
            return true
        }

        // Prefer the most recently scheduled matching intent (user's latest intended drill)
        return matchingIntents.max(by: { $0.scheduledDate < $1.scheduledDate })
    }

    nonisolated public static func matchDrill(
        workoutDate: Date,
        durationSeconds: Double,
        metadata: [String: Any]? = nil
    ) -> ScheduledDrillIntent? {
        let allMetadataStrings: [String] = extractAllStrings(from: metadata)

        // 1. Direct Metadata Check
        for text in allMetadataStrings {
            for candidate in PreRunDrillId.allCases {
                if text.localizedCaseInsensitiveContains(candidate.title) ||
                   (!candidate.rawValue.isEmpty && text.localizedCaseInsensitiveContains(candidate.rawValue)) {
                    return ScheduledDrillIntent(
                        drillTitle: candidate.title,
                        preRunDrillId: candidate.rawValue,
                        scheduledDate: workoutDate,
                        durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                    )
                }
            }
        }

        // 2. Intent Heuristic Fallback
        let intents = recentIntents()
        let matchingIntents = intents.filter { intent in
            if intent.matchedWorkoutID != nil { return false }
            let timeDiff = workoutDate.timeIntervalSince(intent.scheduledDate)
            guard timeDiff >= -3600 && timeDiff <= 48 * 3600 else { return false }

            let expectedDuration = Double(intent.durationMinutes * 60)
            if durationSeconds > 0 {
                let tolerance = max(expectedDuration * 0.60, 600.0)
                let durationDiff = abs(durationSeconds - expectedDuration)
                guard durationDiff <= tolerance else { return false }
            }
            return true
        }

        return matchingIntents.min(by: {
            abs(workoutDate.timeIntervalSince($0.scheduledDate)) < abs(workoutDate.timeIntervalSince($1.scheduledDate))
        })
    }

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

        let intent = ScheduledDrillIntent(
            drillTitle: drill.id.title,
            preRunDrillId: drill.id.rawValue,
            scheduledDate: Date(),
            durationMinutes: duration.rawValue,
            targetCadence: dto.targetCadence,
            matchedWorkoutID: nil
        )
        Self.saveDrillIntent(intent)
    }

    /// Links a drill to a run record without overriding its native classification
    @MainActor public static func linkDrill(to runRecord: RunRecord, drillId: PreRunDrillId) {
        let allIds = PreRunDrillId.allCases.map(\.rawValue)
        let allTitles = PreRunDrillId.allCases.map(\.title)
        runRecord.framboiseTags.removeAll {
            $0.hasPrefix("drill:") || $0 == "prescribedDrill" || allIds.contains($0) || allTitles.contains($0) || $0.isEmpty
        }
        runRecord.framboiseTags.append("prescribedDrill")
        runRecord.framboiseTags.append(drillId.rawValue)
        runRecord.framboiseTags.append("drill:\(drillId.rawValue)")
        runRecord.framboiseTags.append("drill:\(drillId.title)")
        if let rec = runRecord.insight?.drillRecommendations?.first(where: { $0.drillTitle == drillId.title || $0.preRunDrillId == drillId.rawValue }) {
            rec.isCompleted = true
        }
        runRecord.detectedTypeRaw = runRecord.detectedTypeRaw
        try? runRecord.modelContext?.save()
    }

    /// Unlinks a drill from a run record, restoring standard classification properties
    @MainActor public static func unlinkDrill(from runRecord: RunRecord) {
        let allIds = PreRunDrillId.allCases.map(\.rawValue)
        let allTitles = PreRunDrillId.allCases.map(\.title)
        runRecord.framboiseTags.removeAll {
            $0.hasPrefix("drill:") || $0 == "prescribedDrill" || allIds.contains($0) || allTitles.contains($0) || $0.isEmpty
        }
        if let recs = runRecord.insight?.drillRecommendations {
            for rec in recs {
                rec.isCompleted = false
            }
        }
        runRecord.detectedTypeRaw = runRecord.detectedTypeRaw
        try? runRecord.modelContext?.save()
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
    case zone2Run = "zone_2_run"

    init?(rawValue: String) {
        switch rawValue {
        case "cadence_pyramids": self = .cadencePyramids
        case "rhythm_intervals": self = .rhythmIntervals
        case "tempo_surges": self = .tempoSurges
        case "strides": self = .strides
        case "neuromuscular_primer": self = .neuromuscularPrimer
        case "aerobic_flush": self = .aerobicFlush
        case "fartlek_primer": self = .fartlekPrimer
        case "hill_bounds": self = .hillBounds
        case "recovery_jog": self = .recoveryJog
        case "zone_2_run", "aerobic_base_builder": self = .zone2Run
        default: return nil
        }
    }

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
        case .zone2Run: return "Zone 2 Run"
        }
    }

    /// The standard run classification this drill belongs to.
    var correspondingClassification: String {
        switch self {
        case .rhythmIntervals, .cadencePyramids, .strides:
            return "Intervals"
        case .tempoSurges:
            return "Tempo Run"
        case .recoveryJog, .aerobicFlush:
            return "Recovery Run"
        case .fartlekPrimer:
            return "Fartlek"
        case .hillBounds:
            return "Hill Repeats"
        case .zone2Run:
            return "Easy Run"
        case .neuromuscularPrimer:
            return "Intervals"
        }
    }

    /// Whether this drill's primary coaching target is heart rate zone rather than cadence
    var isHeartRateTargeted: Bool {
        self == .zone2Run || self == .aerobicFlush || self == .recoveryJog
    }

    /// Whether this drill is a continuous single-block aerobic run (not intermittent intervals)
    var isAerobicContinuous: Bool {
        self == .zone2Run || self == .aerobicFlush || self == .recoveryJog
    }

    /// The target heart rate zone (e.g. Zone 1 or Zone 2)
    var targetHeartRateZone: Int? {
        switch self {
        case .zone2Run:
            return 2
        case .aerobicFlush, .recoveryJog:
            return 1
        default:
            return nil
        }
    }

    /// User-facing name for the target heart rate zone
    var targetHeartRateZoneName: String? {
        switch self {
        case .zone2Run:
            return "Zone 2 (Aerobic)"
        case .aerobicFlush, .recoveryJog:
            return "Zone 1 (Recovery)"
        default:
            return nil
        }
    }

    /// Resolves a specific drill name or raw identifier into an existing standard run classification.
    /// Standard run classifications (e.g. "Intervals", "Tempo Run") return nil because they are classifications, not drills.
    static func correspondingClassification(for drillNameOrId: String) -> String? {
        let clean = drillNameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardClassifications: Set<String> = [
            "Intervals", "Pyramids", "Tempo Run", "Progression Run", "Recovery Run",
            "Steady Effort", "Easy Run", "Long Run", "Fartlek", "Hill Repeats",
            "Urban Traffic"
        ]
        if standardClassifications.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            return nil
        }

        for drill in PreRunDrillId.allCases {
            if drill.rawValue.localizedCaseInsensitiveCompare(clean) == .orderedSame ||
               drill.title.localizedCaseInsensitiveCompare(clean) == .orderedSame {
                return drill.correspondingClassification
            }
        }
        if clean.localizedCaseInsensitiveCompare("aerobic_base_builder") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Aerobic Base Builder") == .orderedSame {
            return PreRunDrillId.zone2Run.correspondingClassification
        }
        return nil
    }

    /// Normalizes a specific drill identifier or title into its canonical user-facing drill title (e.g. "rhythm_intervals" -> "Rhythm Intervals").
    /// Standard run classifications return nil.
    static func canonicalDrillTitle(for drillNameOrId: String) -> String? {
        let clean = drillNameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardClassifications: Set<String> = [
            "Intervals", "Pyramids", "Tempo Run", "Progression Run", "Recovery Run",
            "Steady Effort", "Easy Run", "Long Run", "Fartlek", "Hill Repeats",
            "Urban Traffic"
        ]
        if standardClassifications.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            return nil
        }

        for drill in PreRunDrillId.allCases {
            if drill.rawValue.localizedCaseInsensitiveCompare(clean) == .orderedSame ||
               drill.title.localizedCaseInsensitiveCompare(clean) == .orderedSame {
                return drill.title
            }
        }
        if clean.localizedCaseInsensitiveCompare("aerobic_base_builder") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Aerobic Base Builder") == .orderedSame {
            return PreRunDrillId.zone2Run.title
        }
        return nil
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
        case .aerobicFlush, .recoveryJog:
            return "lungs.fill"
        case .fartlekPrimer:
            return "waveform.path.ecg"
        case .hillBounds:
            return "mountain.2.fill"
        case .zone2Run:
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
        case .zone2Run:
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
            if parts.count == 2, let lower = Int(parts[0].trimmingCharacters(in: .whitespaces)), let upper = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let safeLower = min(safeMaxCadence, max(safeMinCadence, lower))
                let safeUpper = min(safeMaxCadence, max(safeMinCadence, upper))
                return min(safeLower, safeUpper)...max(safeLower, safeUpper)
            }
        } else if let target = targetCadence, let targetInt = Int(target.replacingOccurrences(of: " SPM", with: "").trimmingCharacters(in: .whitespaces)) {
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
                defaultRecovery: "4 min walk recovery",
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
