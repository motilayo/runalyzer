import XCTest
@testable import Runalyst

final class TrainingCorrectionModelTests: XCTestCase {
    func testTrainingCorrectionInitialization() {
        let correction = TrainingCorrection(
            runRecordID: UUID(),
            originalLabel: "Tempo Run",
            correctedLabel: "Intervals",
            featureVector: [0.18, -0.05, 0.45],
            createdAt: Date(),
            isProcessed: false
        )
        XCTAssertEqual(correction.originalLabel, "Tempo Run")
        XCTAssertEqual(correction.correctedLabel, "Intervals")
        XCTAssertEqual(correction.featureVector.count, 3)
        XCTAssertFalse(correction.isProcessed)
    }
}
