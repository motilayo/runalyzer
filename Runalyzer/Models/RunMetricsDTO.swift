import Foundation

/// A lightweight, Sendable struct used to extract values from PersistentModel
/// records to safely calculate rolling averages across concurrency boundaries.
struct RunMetricsDTO: Sendable {
    let date: Date
    let distance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
}
