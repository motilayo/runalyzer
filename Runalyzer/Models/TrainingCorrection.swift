import Foundation
import SwiftData

/// Represents a user ground-truth correction for a run classification,
/// queued for on-device CoreML model retraining.
@Model
final class TrainingCorrection {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var averagePace: Double
    var paceCV: Double
    var paceSlope: Double
    var percentZone4: Double
    var durationMinutes: Double
    var correctedLabel: String      // Ground-truth override chosen by the user

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        averagePace: Double,
        paceCV: Double,
        paceSlope: Double,
        percentZone4: Double,
        durationMinutes: Double,
        correctedLabel: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.averagePace = averagePace
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.durationMinutes = durationMinutes
        self.correctedLabel = correctedLabel
    }
}
