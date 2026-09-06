import XCTest
import SwiftData
@testable import Runalyzer

final class FetchDescriptorTests: XCTestCase {

    var modelContainer: ModelContainer!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: RunRecord.self, CoachingInsight.self, configurations: config)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
    }

    @MainActor
    func testFetchDescriptor_ThirtyDaysActive() throws {
        // Arrange
        let context = modelContainer.mainContext
        let targetDate = Date()
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: targetDate)!
        let run = RunRecord(
            date: fortyDaysAgo,
            distance: 6000,
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run)
        try context.save()

        // Act
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate)!
        let minDistanceFloat = 5000.0 - 0.01

        // Simulating the predicate from activeDescriptor in DashboardView
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.distance >= minDistanceFloat && $0.date >= thirtyDaysAgo }
        )
        let fetchedRuns = try context.fetch(descriptor)

        // Assert
        XCTAssertTrue(fetchedRuns.isEmpty, "A 40-day old run should be excluded when filtering for 30 days.")
    }

    @MainActor
    func testFetchDescriptor_AllTimeActive() throws {
        // Arrange
        let context = modelContainer.mainContext
        let targetDate = Date()
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: targetDate)!
        let run = RunRecord(
            date: fortyDaysAgo,
            distance: 6000,
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run)
        try context.save()

        // Act
        let minDistanceFloat = 5000.0 - 0.01

        // Simulating the predicate from activeDescriptor in DashboardView for All Time
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.distance >= minDistanceFloat }
        )
        let fetchedRuns = try context.fetch(descriptor)

        // Assert
        XCTAssertEqual(fetchedRuns.count, 1, "A 40-day old run should be included when filtering for all time.")
        XCTAssertEqual(fetchedRuns.first?.distance, 6000)
    }
}
