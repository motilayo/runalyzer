import Foundation
import SwiftData

/// Represents a historical running workout extracted from Apple HealthKit.
/// Persisted locally via SwiftData.
@Model
final class RunRecord {
    /// A unique identifier for the run record, often mirroring the HKWorkout UUID.
    @Attribute(.unique) var id: UUID

    /// The start date and time of the run.
    var date: Date

    /// The total distance covered during the run, stored in meters.
    var distance: Double

    /// The total duration of the run, stored in seconds.
    var duration: TimeInterval

    /// The average pace of the run, stored in minutes per kilometer.
    var avgPace: Double

    /// The average heart rate during the run, stored in beats per minute (BPM).
    var avgHeartRate: Int

    /// The average cadence during the run, stored in steps per minute (SPM).
    var avgCadence: Int

    /// A one-to-one relationship to the AI-generated coaching insight.
    /// If this run record is deleted, the insight is cascaded and deleted as well.
    @Relationship(deleteRule: .cascade, inverse: \CoachingInsight.runRecord)
    var insight: CoachingInsight?

    /// A computed property to format `avgPace` as MM:SS (e.g., 7.50 Double -> "7:30/km")
    var formattedPace: String {
        return avgPace.formattedPaceString
    }

    init(
        id: UUID = UUID(),
        date: Date,
        distance: Double,
        duration: TimeInterval,
        avgPace: Double,
        avgHeartRate: Int,
        avgCadence: Int,
        insight: CoachingInsight? = nil
    ) {
        self.id = id
        self.date = date
        self.distance = distance
        self.duration = duration
        self.avgPace = avgPace
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
        self.insight = insight
    }
}
import Foundation

extension Double {
    /// Formats decimal pace (e.g., 8.33) into standard m:ss/km format (e.g., 8:20/km)
    var formattedPaceString: String {
        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        if useMetricSystem {
            let minutes = Int(self)
            let seconds = Int((self - Double(minutes)) * 60)
            return String(format: "%d:%02d/km", minutes, seconds)
        } else {
            // Convert min/km to min/mi
            let paceInMiles = self * 1.609344
            let minutes = Int(paceInMiles)
            let seconds = Int((paceInMiles - Double(minutes)) * 60)
            return String(format: "%d:%02d/mi", minutes, seconds)
        }
    }
}

extension Array where Element == RunRecord {
    /// Calculates the 30-day baseline stats
    func thirtyDayBaseline(from targetDate: Date = Date()) -> (avgDistance: Double, avgPace: Double, avgHeartRate: Int, avgCadence: Int)? {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else { return nil }

        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        let minDistanceRaw = UserDefaults.standard.object(forKey: "minimumRunDistance") as? Double ?? 1.0
        let minDistanceInMeters = useMetricSystem ? (minDistanceRaw * 1000.0) : (minDistanceRaw * 1609.344)

        let validRuns = self.filter { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.distance >= (minDistanceInMeters - 0.01) }

        guard validRuns.count >= 3 else {
            return nil
        }

        let avgDistance = validRuns.map { $0.distance }.reduce(0, +) / Double(validRuns.count)
        let avgPace = validRuns.map { $0.avgPace }.reduce(0, +) / Double(validRuns.count)
        let avgHeartRate = validRuns.map { $0.avgHeartRate }.reduce(0, +) / validRuns.count
        let avgCadence = validRuns.map { $0.avgCadence }.reduce(0, +) / validRuns.count

        return (avgDistance, avgPace, avgHeartRate, avgCadence)
    }
}
