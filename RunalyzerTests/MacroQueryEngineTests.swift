import XCTest
import SwiftData
@testable import Runalyzer

@available(iOS 26.0, *)
final class MacroQueryEngineTests: XCTestCase {

    var modelContainer: ModelContainer!
    var engine: MacroQueryEngine!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: RunRecord.self, CoachingInsight.self, configurations: config)
        engine = MacroQueryEngine(modelContainer: modelContainer)
    }

    override func tearDownWithError() throws {
        engine = nil
        modelContainer = nil
    }

    @MainActor
    func testMacroQuery_SendableMapping() async throws {
        // Arrange
        let context = modelContainer.mainContext
        let targetDate = Date()
        let run = RunRecord(
            date: targetDate,
            distance: 5000,
            duration: 1500,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run)
        try context.save()

        // Act
        let baseline = try await engine.calculateRollingAverages(days: 7, minimumDistance: 0, to: targetDate)

        // Assert
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.avgDistance, 5000.0)
        XCTAssertEqual(baseline?.avgPace, 300.0)
        XCTAssertEqual(baseline?.avgHeartRate, 150)
        XCTAssertEqual(baseline?.avgCadence, 160)
    }

    func testMacroQuery_RollingAverages() async throws {
        // Arrange
        let dtos: [RunMetricsDTO] = [
            RunMetricsDTO(date: Date(), distance: 4000, avgPace: 6.0, avgHeartRate: 140, avgCadence: 155),
            RunMetricsDTO(date: Date(), distance: 6000, avgPace: 5.0, avgHeartRate: 160, avgCadence: 165)
        ]

        // Act
        let baseline = try await engine.calculateAverages(from: dtos)

        // Assert
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.avgDistance, 5000.0)
        XCTAssertEqual(baseline?.avgPace, 5.5)
        XCTAssertEqual(baseline?.avgHeartRate, 150)
        XCTAssertEqual(baseline?.avgCadence, 160)
    }
}
