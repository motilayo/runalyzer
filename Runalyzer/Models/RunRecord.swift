import Foundation
import SwiftData

/// Represents a historical running workout extracted from Apple HealthKit.
/// Persisted locally via SwiftData.
@Model
final class RunRecord {
    @Attribute(.unique) var id: UUID
    var hkWorkoutID: UUID
    var date: Date
    var duration: TimeInterval
    var totalDistanceMeters: Double

    // Raw Totals
    var rawAvgPace: Double          // sec/km
    var rawAvgCadence: Double       // SPM
    var rawAvgHeartRate: Double     // BPM

    // Framboise Working Averages (Dead stops trimmed)
    var workingAvgPace: Double      // sec/km
    var workingAvgCadence: Double   // SPM
    var workingAvgHeartRate: Double // BPM

    // Mathematical Features
    var paceCV: Double              // Coefficient of Variation (σ / μ)
    var paceSlope: Double           // Linear regression slope
    var percentZone4: Double        // Time in Zone 4 (0.0 - 1.0)

    // Classification & Coaching
    var detectedTypeRaw: String     // Enum rawValue: "steady", "tempo", "intervals", "urbanTraffic", "unknown"
    var framboiseTags: [String]     // E.g., ["Cadence dropped at peak effort", "Maintained stable heart rate"]
    var aiCoachingAnalysis: String? // Cached narrative string

    // Biomechanical & Fitness Metrics
    var verticalOscillation: Double = 0.0
    var vo2Max: Double = 0.0
    var groundContactTime: Double = 0.0
    var strideLength: Double = 0.0

    // Legacy / Relationship properties
    @Relationship(deleteRule: .cascade, inverse: \CoachingInsight.runRecord)
    var insight: CoachingInsight?

    var isAnalyzing: Bool? = false

    // MARK: - Compatibility & Convenience Properties

    var distance: Double {
        get { totalDistanceMeters }
        set { totalDistanceMeters = newValue }
    }

    /// Average pace in decimal minutes per kilometer (e.g. 5.5 = 5:30/km)
    var avgPace: Double {
        get { rawAvgPace > 0 ? (rawAvgPace / 60.0) : 0.0 }
        set { rawAvgPace = newValue * 60.0 }
    }

    var avgHeartRate: Int {
        get { Int(rawAvgHeartRate.rounded()) }
        set { rawAvgHeartRate = Double(newValue) }
    }

    var avgCadence: Int {
        get { Int(rawAvgCadence.rounded()) }
        set { rawAvgCadence = Double(newValue) }
    }

    var workingAvgPaceMinKm: Double? {
        workingAvgPace > 0 ? (workingAvgPace / 60.0) : nil
    }

    var workingAvgHeartRateInt: Int? {
        workingAvgHeartRate > 0 ? Int(workingAvgHeartRate.rounded()) : nil
    }

    var workingAvgCadenceInt: Int? {
        workingAvgCadence > 0 ? Int(workingAvgCadence.rounded()) : nil
    }

    var runType: RunType {
        get {
            switch detectedTypeRaw {
            case "steady": return .steady
            case "tempo": return .tempo
            case "progressive": return .progressive
            case "intervals": return .intervals
            case "urbanTraffic", "urban_traffic", "urban traffic": return .urbanTraffic
            default: return .unknown
            }
        }
        set {
            switch newValue {
            case .steady: detectedTypeRaw = "steady"
            case .tempo: detectedTypeRaw = "tempo"
            case .progressive: detectedTypeRaw = "progressive"
            case .intervals: detectedTypeRaw = "intervals"
            case .urbanTraffic: detectedTypeRaw = "urbanTraffic"
            case .unknown: detectedTypeRaw = "unknown"
            }
        }
    }

    var runTypeRaw: String {
        get { detectedTypeRaw }
        set { detectedTypeRaw = newValue }
    }

    /// The Framboise/CoreML classification formatted for run-list presentation.
    var detectedType: String {
        let raw = detectedTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Unknown" }

        switch raw.lowercased() {
        case "steady": return "Steady"
        case "tempo": return "Tempo"
        case "progressive": return "Progressive"
        case "intervals", "interval": return "Intervals"
        case "urban traffic", "urbantraffic", "urban_traffic": return "Steady"
        case "unknown": return "Steady"
        default: return raw.capitalized
        }
    }

    var formattedPace: String {
        formatDisplayPace(secondsPerKilometer: rawAvgPace)
    }

    var workingFormattedPace: String? {
        workingAvgPace > 0 ? formatDisplayPace(secondsPerKilometer: workingAvgPace) : nil
    }

    init(
        id: UUID = UUID(),
        hkWorkoutID: UUID? = nil,
        date: Date,
        duration: TimeInterval,
        totalDistanceMeters: Double,
        rawAvgPace: Double = 0.0,
        rawAvgCadence: Double = 0.0,
        rawAvgHeartRate: Double = 0.0,
        workingAvgPace: Double = 0.0,
        workingAvgCadence: Double = 0.0,
        workingAvgHeartRate: Double = 0.0,
        paceCV: Double = 0.0,
        paceSlope: Double = 0.0,
        percentZone4: Double = 0.0,
        detectedTypeRaw: String = "unknown",
        framboiseTags: [String] = [],
        aiCoachingAnalysis: String? = nil,
        verticalOscillation: Double = 0.0,
        vo2Max: Double = 0.0,
        groundContactTime: Double = 0.0,
        strideLength: Double = 0.0,
        insight: CoachingInsight? = nil
    ) {
        self.id = id
        self.hkWorkoutID = hkWorkoutID ?? id
        self.date = date
        self.duration = duration
        self.totalDistanceMeters = totalDistanceMeters
        self.rawAvgPace = rawAvgPace
        self.rawAvgCadence = rawAvgCadence
        self.rawAvgHeartRate = rawAvgHeartRate
        self.workingAvgPace = workingAvgPace
        self.workingAvgCadence = workingAvgCadence
        self.workingAvgHeartRate = workingAvgHeartRate
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.detectedTypeRaw = detectedTypeRaw
        self.framboiseTags = framboiseTags
        self.aiCoachingAnalysis = aiCoachingAnalysis
        self.verticalOscillation = verticalOscillation
        self.vo2Max = vo2Max
        self.groundContactTime = groundContactTime
        self.strideLength = strideLength
        self.insight = insight
        self.isAnalyzing = false
    }

    // Convenience initializer for legacy callers
    convenience init(
        id: UUID = UUID(),
        date: Date,
        distance: Double,
        duration: TimeInterval,
        avgPace: Double,
        avgHeartRate: Int,
        avgCadence: Int,
        verticalOscillation: Double = 0.0,
        vo2Max: Double = 0.0,
        groundContactTime: Double = 0.0,
        strideLength: Double = 0.0,
        insight: CoachingInsight? = nil
    ) {
        self.init(
            id: id,
            hkWorkoutID: id,
            date: date,
            duration: duration,
            totalDistanceMeters: distance,
            rawAvgPace: avgPace * 60.0,
            rawAvgCadence: Double(avgCadence),
            rawAvgHeartRate: Double(avgHeartRate),
            workingAvgPace: avgPace * 60.0,
            workingAvgCadence: Double(avgCadence),
            workingAvgHeartRate: Double(avgHeartRate),
            verticalOscillation: verticalOscillation,
            vo2Max: vo2Max,
            groundContactTime: groundContactTime,
            strideLength: strideLength,
            insight: insight
        )
    }
}

// MARK: - Centralized Global Pace Formatter

/// Formats total seconds per kilometer into MM:SS format.
/// Guaranteed not to render a minutes column greater than 59 unless totalSeconds exceeds an hour.
public func formatPace(secondsPerKilometer totalSeconds: Double) -> String {
    guard totalSeconds.isFinite && !totalSeconds.isNaN && totalSeconds > 0 else {
        return "--:--"
    }
    let totalSecInt = Int(totalSeconds.rounded())
    let minutes = min(totalSecInt / 60, 59)
    let seconds = min(max(totalSecInt % 60, 0), 59)
    return String(format: "%d:%02d", minutes, seconds)
}

/// Formats total seconds per kilometer with respect to the user's measurement system (metric / imperial).
public func formatDisplayPace(secondsPerKilometer totalSeconds: Double, useMetric: Bool? = nil) -> String {
    guard totalSeconds.isFinite && !totalSeconds.isNaN && totalSeconds > 0 else {
        return "--:--"
    }
    let isMetric = useMetric ?? (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric))
    let effectiveSeconds = isMetric ? totalSeconds : (totalSeconds * 1.609344)
    let formatted = formatPace(secondsPerKilometer: effectiveSeconds)
    let unit = isMetric ? "km" : "mi"
    return "\(formatted)/\(unit)"
}

extension Double {
    /// Formats decimal pace (minutes per kilometer) into standard m:ss/km format
    var formattedPaceString: String {
        formatDisplayPace(secondsPerKilometer: self * 60.0)
    }
}
