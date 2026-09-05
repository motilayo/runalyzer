import XCTest
@testable import Runalyzer

final class MacroQueryTests: XCTestCase {

    func testMacroQuery_SendableMapping() {
        // Assert that fetched PersistentModel records are correctly mapped to DTOs
        let date = Date()
        let id = UUID()
        let record = RunRecord(
            id: id,
            date: date,
            distance: 5000,
            duration: 1500,
            avgPace: 5.0,
            avgHeartRate: 150,
            avgCadence: 160
        )

        let dto = RunMetricsDTO(
            id: record.id,
            date: record.date,
            distance: record.distance,
            duration: record.duration,
            avgPace: record.avgPace,
            avgHeartRate: record.avgHeartRate,
            avgCadence: record.avgCadence
        )

        XCTAssertEqual(dto.id, id)
        XCTAssertEqual(dto.avgPace, 5.0)
        XCTAssertEqual(dto.avgHeartRate, 150)
        XCTAssertEqual(dto.avgCadence, 160)
    }

    func testMacroQuery_RollingAverages() async {
        let calendar = Calendar.current
        let today = Date()
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today)!
        let twentyDaysAgo = calendar.date(byAdding: .day, value: -20, to: today)!
        let fortyDaysAgo = calendar.date(byAdding: .day, value: -40, to: today)!

        let records: [RunMetricsDTO] = [
            RunMetricsDTO(id: UUID(), date: today, distance: 5000, duration: 1500, avgPace: 5.0, avgHeartRate: 140, avgCadence: 160),
            RunMetricsDTO(id: UUID(), date: fiveDaysAgo, distance: 5000, duration: 1500, avgPace: 5.2, avgHeartRate: 142, avgCadence: 158),
            RunMetricsDTO(id: UUID(), date: twentyDaysAgo, distance: 5000, duration: 1500, avgPace: 5.4, avgHeartRate: 144, avgCadence: 156),
            RunMetricsDTO(id: UUID(), date: fortyDaysAgo, distance: 5000, duration: 1500, avgPace: 6.0, avgHeartRate: 150, avgCadence: 150)
        ]

        let sevenDayAvg = await MacroQueryEngine.calculateRollingAverages(for: records, within: 7)
        XCTAssertEqual(sevenDayAvg.avgPace, 5.1, accuracy: 0.01)
        XCTAssertEqual(sevenDayAvg.avgHeartRate, 141)
        XCTAssertEqual(sevenDayAvg.avgCadence, 159)

        let thirtyDayAvg = await MacroQueryEngine.calculateRollingAverages(for: records, within: 30)
        XCTAssertEqual(thirtyDayAvg.avgPace, 5.2, accuracy: 0.01)
        XCTAssertEqual(thirtyDayAvg.avgHeartRate, 142)
        XCTAssertEqual(thirtyDayAvg.avgCadence, 158)
    }

    func testFetchDescriptor_ThirtyDaysActive() {
        let calendar = Calendar.current
        let today = Date()
        let fortyDaysAgo = calendar.date(byAdding: .day, value: -40, to: today)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!

        let showLast30Days = true
        let minDistanceInMeters = 5000.0

        let predicate = #Predicate<RunRecord> { record in
            record.distance >= (minDistanceInMeters - 0.01) && record.date >= thirtyDaysAgo
        }

        let validRecord = RunRecord(date: today, distance: 5000, duration: 1500, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)
        let oldRecord = RunRecord(date: fortyDaysAgo, distance: 6000, duration: 1800, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)
        let shortRecord = RunRecord(date: today, distance: 4000, duration: 1500, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)

        do {
            XCTAssertTrue(try predicate.evaluate(validRecord))
            XCTAssertFalse(try predicate.evaluate(oldRecord))
            XCTAssertFalse(try predicate.evaluate(shortRecord))
        } catch {
            XCTFail("Predicate evaluation failed")
        }
    }

    func testFetchDescriptor_AllTimeActive() {
        let calendar = Calendar.current
        let today = Date()
        let fortyDaysAgo = calendar.date(byAdding: .day, value: -40, to: today)!

        let showLast30Days = false
        let minDistanceInMeters = 5000.0

        let predicate = #Predicate<RunRecord> { record in
            record.distance >= (minDistanceInMeters - 0.01)
        }

        let validRecord = RunRecord(date: today, distance: 5000, duration: 1500, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)
        let oldRecord = RunRecord(date: fortyDaysAgo, distance: 6000, duration: 1800, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)
        let shortRecord = RunRecord(date: today, distance: 4000, duration: 1500, avgPace: 5.0, avgHeartRate: 150, avgCadence: 160)

        do {
            XCTAssertTrue(try predicate.evaluate(validRecord))
            XCTAssertTrue(try predicate.evaluate(oldRecord))
            XCTAssertFalse(try predicate.evaluate(shortRecord))
        } catch {
            XCTFail("Predicate evaluation failed")
        }
    }
}
