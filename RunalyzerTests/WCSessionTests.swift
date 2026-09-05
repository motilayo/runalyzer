import XCTest
import SwiftData
@testable import Runalyzer

@available(iOS 17.0, watchOS 10.0, *)
final class WCSessionTests: XCTestCase {

    func testWCSession_PayloadDecoding() throws {
        // Arrange
        let payload: [String: Any] = [
            "completedRun": try JSONEncoder().encode(RunRecordDTO(date: Date(), distance: 1000, duration: 600, avgPace: 6.0, avgHeartRate: 150, avgCadence: 160, verticalOscillation: 8.0, groundContactTime: 250, strideLength: 1.0))
        ]

        // Act
        guard let data = payload["completedRun"] as? Data else {
            XCTFail("Missing payload")
            return
        }
        let decoded = try JSONDecoder().decode(RunRecordDTO.self, from: data)

        // Assert
        XCTAssertEqual(decoded.distance, 1000)
    }

    @MainActor
    func testDTO_to_PersistentModel_Mapping() async throws {
        // Arrange
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunRecord.self, CoachingInsight.self, DrillRecommendation.self, configurations: config)
        let context = container.mainContext
        let manager = WatchConnectivityManager.shared

        let dto = RunRecordDTO(date: Date(), distance: 1000, duration: 600, avgPace: 6.0, avgHeartRate: 150, avgCadence: 160, verticalOscillation: 8.0, groundContactTime: 250, strideLength: 1.0)

        // Act
        let _ = try await manager.saveRunRecord(from: dto, context: context)

        // Assert
        let fetched = try context.fetch(FetchDescriptor<RunRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, dto.id)
    }
}
