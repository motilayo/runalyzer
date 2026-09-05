import Foundation

public struct RunMetricsDTO: Sendable {
    public let id: UUID
    public let date: Date
    public let distance: Double
    public let duration: TimeInterval
    public let avgPace: Double
    public let avgHeartRate: Int
    public let avgCadence: Int

    public init(id: UUID, date: Date, distance: Double, duration: TimeInterval, avgPace: Double, avgHeartRate: Int, avgCadence: Int) {
        self.id = id
        self.date = date
        self.distance = distance
        self.duration = duration
        self.avgPace = avgPace
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
    }
}
