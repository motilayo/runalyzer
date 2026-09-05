import Foundation

/// DTO for syncing a completed run from watchOS to iOS
public struct RunRecordDTO: Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let distance: Double
    public let duration: TimeInterval
    public let avgPace: Double
    public let avgHeartRate: Int
    public let avgCadence: Int
    public let verticalOscillation: Double
    public let groundContactTime: Double
    public let strideLength: Double

    public init(id: UUID = UUID(), date: Date, distance: Double, duration: TimeInterval, avgPace: Double, avgHeartRate: Int, avgCadence: Int, verticalOscillation: Double, groundContactTime: Double, strideLength: Double) {
        self.id = id
        self.date = date
        self.distance = distance
        self.duration = duration
        self.avgPace = avgPace
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
        self.verticalOscillation = verticalOscillation
        self.groundContactTime = groundContactTime
        self.strideLength = strideLength
    }
}

/// DTO for sending AI-prescribed drill down to the watch
public struct DrillRecommendationDTO: Codable, Sendable {
    public let drillTitle: String
    public let drillPurpose: String?
    public let drillWork: String?
    public let drillCues: String?
    public let drillEffort: String?
    public let drillRecovery: String?
    public let targetCadence: String?

    public init(drillTitle: String, drillPurpose: String?, drillWork: String?, drillCues: String?, drillEffort: String?, drillRecovery: String?, targetCadence: String?) {
        self.drillTitle = drillTitle
        self.drillPurpose = drillPurpose
        self.drillWork = drillWork
        self.drillCues = drillCues
        self.drillEffort = drillEffort
        self.drillRecovery = drillRecovery
        self.targetCadence = targetCadence
    }
}
