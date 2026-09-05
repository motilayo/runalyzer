import XCTest
import SwiftData
@testable import Runalyzer

@MainActor
final class MacroQueryTests: XCTestCase {

    var modelContainer: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: RunRecord.self, CoachingInsight.self, DrillRecommendation.self, configurations: config)
        context = modelContainer.mainContext
    }

    func testMacroQuery_SendableMapping() throws {
        let record = RunRecord(
            date: Date(),
            distance: 5000,
            duration: 1500,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(record)

        let descriptor = FetchDescriptor<RunRecord>()
        let records = try context.fetch(descriptor)

        // Assert sequentially mapped to Sendable DTO
        let dtos = records.map { RunMetricsDTO(from: $0) }

        XCTAssertEqual(dtos.count, 1)
        XCTAssertEqual(dtos.first?.distance, 5000)
    }

    func testFetchDescriptor_ThirtyDaysActive() throws {
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!

        let record = RunRecord(
            date: fortyDaysAgo,
            distance: 6000, // 6km
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(record)

        let minimumDistance = 5.0 // 5km
        let minDistanceInMeters = minimumDistance * 1000.0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { record in
                record.date >= thirtyDaysAgo && record.distance >= minDistanceInMeters
            }
        )

        let fetched = try context.fetch(descriptor)
        XCTAssertTrue(fetched.isEmpty, "Should exclude a 6km run logged 40 days ago when 30 days filter is active")
    }

    func testFetchDescriptor_AllTimeActive() throws {
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!

        let record = RunRecord(
            date: fortyDaysAgo,
            distance: 6000, // 6km
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(record)

        let minimumDistance = 5.0 // 5km
        let minDistanceInMeters = minimumDistance * 1000.0

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { record in
                record.distance >= minDistanceInMeters
            }
        )

        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "Should include a 6km run logged 40 days ago when All Time filter is active")
    }

    func testMacroQuery_RollingAverages() async throws {
        let today = Date()
        for i in 1...15 {
            let recordDate = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            let record = RunRecord(
                date: recordDate,
                distance: 5000,
                duration: 1500,
                avgPace: 5.0,
                avgHeartRate: 150,
                avgCadence: 160
            )
            context.insert(record)
        }

        try context.save()

        if #available(iOS 26.0, *) {
            let actor = RunAnalyzerActor(modelContainer: modelContainer)
            let (current, previous) = await actor.fetchWeeklyTrends()

            // Current week (last 7 days) should have 7 items with distance 5000 and cadence 160
            XCTAssertNotNil(current)
            XCTAssertEqual(current?.avgDistance, 5000)
            XCTAssertEqual(current?.avgCadence, 160)

            // Previous week (days 8-14) should have 7 items
            XCTAssertNotNil(previous)
            XCTAssertEqual(previous?.avgDistance, 5000)
            XCTAssertEqual(previous?.avgCadence, 160)
        }
    }
}
