import Foundation
import SwiftData

@Model
final class RunRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var distance: Double // in meters
    var duration: TimeInterval // in seconds
    var avgPace: Double // in minutes per kilometer or similar metric, depending on unit preference, but raw value Double
    var avgHeartRate: Int
    var avgCadence: Int

    // One-to-one cascade relationship to CoachingInsight
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
