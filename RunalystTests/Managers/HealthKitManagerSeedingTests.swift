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

    func testHealthKitSeederChunkMetricsPhysics() {
        let testProgressLevels = [0.0, 0.5, 1.0]

        for profile in MockRunProfile.allCases {
            for progress in testProgressLevels {
                for minute in 0..<min(profile.durationMinutes, 10) {
                    for chunkInMinute in 0..<4 {
                        let chunkIndex = minute * 4 + chunkInMinute
                        let metrics = HealthKitSeeder.generate15SecondMetrics(
                            for: profile,
                            workoutIndex: 0,
                            chunkIndex: chunkIndex,
                            progress: progress
                        )

                        if metrics.distanceMeters > 0 && metrics.cadence > 0 {
                            XCTAssertGreaterThanOrEqual(metrics.stride, 0.6, "Stride should be >= 0.6m for active running in \(profile)")
                            XCTAssertLessThanOrEqual(metrics.stride, 1.8, "Stride should be <= 1.8m for active running in \(profile)")
                            XCTAssertGreaterThanOrEqual(metrics.oscillation, 6.5, "Oscillation should be >= 6.5cm in \(profile)")
                            XCTAssertLessThanOrEqual(metrics.oscillation, 12.0, "Oscillation should be <= 12.0cm in \(profile)")
                            XCTAssertGreaterThanOrEqual(metrics.gct, 200.0, "GCT should be >= 200ms in \(profile)")
                            XCTAssertLessThanOrEqual(metrics.gct, 350.0, "GCT should be <= 350ms in \(profile)")
                            XCTAssertGreaterThanOrEqual(metrics.heartRate, 100.0, "Heart rate should be >= 100bpm in \(profile)")
                        } else {
                            XCTAssertEqual(metrics.stride, 0.0, "Stride should be 0 during pause/rest chunk in \(profile)")
                        }
                    }
                }
            }
        }
    }

    func testHealthKitSeederIntervalWorkRestAlternation() {
        let workChunk = HealthKitSeeder.generate15SecondMetrics(
            for: .intervals,
            workoutIndex: 20,
            chunkIndex: 0, // Minute 0: work
            progress: 0.5
        )
        let recoveryChunk = HealthKitSeeder.generate15SecondMetrics(
            for: .intervals,
            workoutIndex: 20,
            chunkIndex: 12, // Minute 3: recovery jog
            progress: 0.5
        )
        let pauseChunk = HealthKitSeeder.generate15SecondMetrics(
            for: .intervals,
            workoutIndex: 20,
            chunkIndex: 56, // Minute 14: rest stop
            progress: 0.5
        )

        // Work interval should have faster pace (more distance in 15s) and higher cadence
        XCTAssertGreaterThan(workChunk.distanceMeters, recoveryChunk.distanceMeters, "Work interval distance must exceed recovery distance")
        XCTAssertGreaterThan(workChunk.cadence, recoveryChunk.cadence, "Work interval cadence must exceed recovery cadence")
        XCTAssertGreaterThan(workChunk.heartRate, recoveryChunk.heartRate, "Work interval heart rate must exceed recovery heart rate")

        // Pause chunk must be zeroed out
        XCTAssertEqual(pauseChunk.distanceMeters, 0.0, "Pause chunk distance should be 0")
        XCTAssertEqual(pauseChunk.cadence, 0.0, "Pause chunk cadence should be 0")
        XCTAssertEqual(pauseChunk.stride, 0.0, "Pause chunk stride should be 0")
    }

    func testHealthKitSeederProgressionRunAcceleration() {
        let earlyChunk = HealthKitSeeder.generate15SecondMetrics(
            for: .progression,
            workoutIndex: 20,
            chunkIndex: 0, // Minute 0
            progress: 0.5
        )
        let lateChunk = HealthKitSeeder.generate15SecondMetrics(
            for: .progression,
            workoutIndex: 20,
            chunkIndex: 160, // Minute 40
            progress: 0.5
        )

        XCTAssertGreaterThan(lateChunk.distanceMeters, earlyChunk.distanceMeters, "Progression run must get faster over time")
        XCTAssertGreaterThan(lateChunk.cadence, earlyChunk.cadence, "Progression run cadence must increase over time")
        XCTAssertGreaterThan(lateChunk.heartRate, earlyChunk.heartRate, "Progression run heart rate should rise over time")
    }
}
