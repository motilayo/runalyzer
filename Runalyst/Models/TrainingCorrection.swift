import Foundation
import SwiftData

/// Represents a user correction to the AI's run classification.
/// Used to train the CoreML PersonalizedRunClassifier.
@Model
final class TrainingCorrection {
    @Attribute(.unique) var id: UUID
    var runRecordID: UUID
    var originalLabel: String
    var correctedLabel: String
    var featureVector: [Double]
    var createdAt: Date
    var isProcessed: Bool

    init(
        id: UUID = UUID(),
        runRecordID: UUID,
        originalLabel: String,
        correctedLabel: String,
        featureVector: [Double],
        createdAt: Date = Date(),
        isProcessed: Bool = false
    ) {
        self.id = id
        self.runRecordID = runRecordID
        self.originalLabel = originalLabel
        self.correctedLabel = correctedLabel
        self.featureVector = featureVector
        self.createdAt = createdAt
        self.isProcessed = isProcessed
    }
}
