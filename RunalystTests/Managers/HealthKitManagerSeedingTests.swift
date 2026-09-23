import XCTest
import SwiftData
@testable import Runalyst

@MainActor
final class HealthKitManagerSeedingTests: XCTestCase {
    func testSeedDirectToSwiftData() throws {
        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let seeder = HealthKitSeeder.shared
        seeder.seedDirectToSwiftData(context: context)

        let descriptor = FetchDescriptor<RunRecord>()
        let records = try context.fetch(descriptor)

        XCTAssertFalse(records.isEmpty, "Seeded runs should not be empty")
        XCTAssertEqual(records.count, HealthKitSeeder.totalProgressionRuns)

        for record in records {
            XCTAssertGreaterThan(record.totalDistanceMeters, 0)
            XCTAssertGreaterThan(record.duration, 0)
            XCTAssertFalse(record.detectedTypeRaw.isEmpty)

            let drill = try XCTUnwrap(record.insight?.drillRecommendation)
            let drillId = try XCTUnwrap(drill.preRunDrillId)
            XCTAssertNotNil(PreRunDrillId(rawValue: drillId), "Drill ID \(drillId) should be a valid PreRunDrillId")
            XCTAssertFalse(drill.drillTitle.isEmpty)
            XCTAssertNotNil(drill.drillWork)
            XCTAssertNotNil(drill.drillRecovery)
            XCTAssertNotNil(drill.targetCadence)
            XCTAssertNotNil(drill.previousCadence)
        }

        let sortedRecords = records.sorted { $0.date < $1.date }
        let oldestRun = try XCTUnwrap(sortedRecords.first)
        let newestRun = try XCTUnwrap(sortedRecords.last)

        let calendar = Calendar.current
        let daysDiff = calendar.dateComponents([.day], from: oldestRun.date, to: newestRun.date).day ?? 0
        XCTAssertGreaterThanOrEqual(daysDiff, 80, "Seeded runs should span roughly 3 months (~80-90 days)")

        // Verify beginner-to-intermediate progression
        XCTAssertLessThan(oldestRun.workingAvgCadence, newestRun.workingAvgCadence, "Cadence should trend upward over 3 months")
        if let oldestOsc = oldestRun.workingAvgVerticalOscillation, let newestOsc = newestRun.workingAvgVerticalOscillation {
            XCTAssertGreaterThan(oldestOsc, newestOsc, "Vertical oscillation should reduce over 3 months")
        }
    }

    func testHealthKitSeederPrescribedDrillDistribution() {
        var seededDrillIds = Set<PreRunDrillId>()
        for index in 0..<HealthKitSeeder.totalProgressionRuns {
            let profile = HealthKitSeeder.profile(forIndex: index)
            let progress = Double(index) / Double(max(1, HealthKitSeeder.totalProgressionRuns - 1))
            XCTAssertNotEqual(profile.rawValue, "Cadence Run", "Profile rawValue should never be Cadence Run")
            if let drill = HealthKitSeeder.prescribedDrill(forIndex: index, profile: profile, progress: progress) {
                seededDrillIds.insert(drill)
            }
        }

        // Verify that all core V2 drill archetypes are present in the seeder schedule
        XCTAssertTrue(seededDrillIds.contains(.zone2Run), "Should seed Zone 2 Run")
        XCTAssertTrue(seededDrillIds.contains(.recoveryJog), "Should seed Recovery Jog")
        XCTAssertTrue(seededDrillIds.contains(.cadencePyramids), "Should seed Cadence Pyramids")
        XCTAssertTrue(seededDrillIds.contains(.rhythmIntervals), "Should seed Rhythm Intervals")
        XCTAssertTrue(seededDrillIds.contains(.tempoSurges), "Should seed Tempo Surges")
        XCTAssertTrue(seededDrillIds.contains(.strides), "Should seed Strides")
    }
}
