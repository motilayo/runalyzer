import Foundation
import SwiftData

/// Lightweight Sendable struct to safely transfer `RunRecord` data across actors/threads for macro calculations.
struct RunMetricsDTO: Sendable {
    let id: UUID
    let date: Date
    let distance: Double
    let duration: TimeInterval
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
    let verticalOscillation: Double
    let vo2Max: Double
    let groundContactTime: Double
    let strideLength: Double

    init(from record: RunRecord) {
        self.id = record.id
        self.date = record.date
        self.distance = record.distance
        self.duration = record.duration
        self.avgPace = record.avgPace
        self.avgHeartRate = record.avgHeartRate
        self.avgCadence = record.avgCadence
        self.verticalOscillation = record.verticalOscillation
        self.vo2Max = record.vo2Max
        self.groundContactTime = record.groundContactTime
        self.strideLength = record.strideLength
    }
}
