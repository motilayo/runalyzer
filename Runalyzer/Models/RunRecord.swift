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
