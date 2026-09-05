import XCTest
import SwiftData
@testable import Runalyzer

@MainActor
final class MacroQueryTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var currentDate: Date!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: RunRecord.self, configurations: config)
        context = container.mainContext
        currentDate = Date()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testFetchDescriptor_ThirtyDaysActive() throws {
        let thirtyFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -35, to: currentDate)!
        let run = RunRecord(
            date: thirtyFiveDaysAgo,
            distance: 6000,
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run)

        let recentDate = Calendar.current.date(byAdding: .day, value: -10, to: currentDate)!
        let run2 = RunRecord(
            date: recentDate,
            distance: 6000,
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run2)
        try context.save()

        let descriptor = FetchDescriptorBuilder.build(showLast30Days: true, minimumDistance: 5.0, useMetricSystem: true, currentDate: currentDate)
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.date, recentDate)
    }

    func testFetchDescriptor_AllTimeActive() throws {
        let thirtyFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -35, to: currentDate)!
        let run = RunRecord(
            date: thirtyFiveDaysAgo,
            distance: 6000,
            duration: 1800,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )
        context.insert(run)
        try context.save()

        let descriptor = FetchDescriptorBuilder.build(showLast30Days: false, minimumDistance: 5.0, useMetricSystem: true, currentDate: currentDate)
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.date, thirtyFiveDaysAgo)
    }

    func testMacroQuery_RollingAverages() throws {
        var mockRecords: [RunRecord] = []
        for i in 1...15 {
            let recordDate = Calendar.current.date(byAdding: .day, value: -i, to: currentDate)!
            let run = RunRecord(
                date: recordDate,
                distance: 5000,
                duration: 1500,
                avgPace: 5.0,
                avgHeartRate: 150,
                avgCadence: 160
            )
            mockRecords.append(run)
        }

        // 7-day average
        let sevenDayAvg = MacroQuery.rollingAverages(from: mockRecords, days: 7, currentDate: currentDate)
        XCTAssertNotNil(sevenDayAvg)
        XCTAssertEqual(sevenDayAvg?.pace, 5.0, accuracy: 0.01)
        XCTAssertEqual(sevenDayAvg?.cadence, 160.0, accuracy: 0.01)
        XCTAssertEqual(sevenDayAvg?.heartRate, 150.0, accuracy: 0.01)

        // 30-day average
        let thirtyDayAvg = MacroQuery.rollingAverages(from: mockRecords, days: 30, currentDate: currentDate)
        XCTAssertNotNil(thirtyDayAvg)
        XCTAssertEqual(thirtyDayAvg?.pace, 5.0, accuracy: 0.01)
        XCTAssertEqual(thirtyDayAvg?.cadence, 160.0, accuracy: 0.01)
        XCTAssertEqual(thirtyDayAvg?.heartRate, 150.0, accuracy: 0.01)
    }
}
