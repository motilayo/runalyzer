import XCTest
import SwiftData
@testable import Runalyst

@MainActor
final class RunRecordModelAndSchemaTests: XCTestCase {
    func testRunRecordEffectiveWorkingMetricsFallback() {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 150,
            rawAvgCadence: 165,
            workingAvgPace: 295,
            workingAvgCadence: 168,
            workingAvgHeartRate: 152,
            workingDistanceMeters: nil,
            workingDurationSeconds: nil,
            paceCV: 0.05,
            paceSlope: 0.1,
            percentZone4: 0.2,
            detectedTypeRaw: "Tempo Run"
        )

        // Must fallback cleanly
        XCTAssertEqual(run.effectiveWorkingDistanceMeters, 5000)
        XCTAssertEqual(run.effectiveWorkingDurationSeconds, 1500)

        // When non-nil, use working values
        run.workingDistanceMeters = 4800
        run.workingDurationSeconds = 1420
        XCTAssertEqual(run.effectiveWorkingDistanceMeters, 4800)
        XCTAssertEqual(run.effectiveWorkingDurationSeconds, 1420)
    }

    func testCoachingInsightAndDrillRelationships() {
        let insight = CoachingInsight(
            headline: "Strong Cadence Consistency",
            longitudinalObservation: "Your cadence is trending positively compared to your 30-day average."
        )

        let drill1 = DrillRecommendation(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            drillPurpose: "Turnover improvement",
            drillWork: "4 x 30s accelerations",
            drillCues: "Quick light steps",
            targetCadence: "168 SPM",
            previousCadence: 160,
            orderIndex: 0
        )

        insight.drillRecommendations = [drill1]
        XCTAssertEqual(insight.drillRecommendations?.count, 1)
        XCTAssertEqual(insight.drillRecommendations?.first?.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(insight.drillRecommendations?.first?.targetCadence, "168 SPM")
    }

    func testRunalystSchemaV1Integrity() {
        XCTAssertEqual(RunalystSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        let modelTypes = RunalystSchemaV1.models
        XCTAssertEqual(modelTypes.count, 4)
        XCTAssertTrue(modelTypes.contains(where: { $0 == RunRecord.self }))
        XCTAssertTrue(modelTypes.contains(where: { $0 == CoachingInsight.self }))
        XCTAssertTrue(modelTypes.contains(where: { $0 == DrillRecommendation.self }))
        XCTAssertTrue(modelTypes.contains(where: { $0 == TrainingCorrection.self }))

        XCTAssertEqual(RunalystMigrationPlan.schemas.count, 1)
        XCTAssertTrue(RunalystMigrationPlan.stages.isEmpty)
    }

    @MainActor
    func testPersistentStoreReopenWithMigrationPlan() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("test.store")
        let schema = Schema(versionedSchema: RunalystSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)

        // Launch 1: Create store, insert run, save
        do {
            let container1 = try ModelContainer(
                for: schema,
                migrationPlan: RunalystMigrationPlan.self,
                configurations: [config]
            )
            let context1 = ModelContext(container1)
            let run = RunRecord(
                hkWorkoutID: UUID(),
                date: Date(),
                totalDistanceMeters: 5000,
                duration: 1500,
                rawAvgPace: 300,
                rawAvgHeartRate: 150,
                rawAvgCadence: 165,
                workingAvgPace: 295,
                workingAvgCadence: 168,
                workingAvgHeartRate: 152,
                paceCV: 0.05,
                paceSlope: 0.1,
                percentZone4: 0.2,
                detectedTypeRaw: "Steady Effort"
            )
            context1.insert(run)
            try context1.save()
        }

        // Launch 2: Reopen existing store with migration plan (simulating app relaunch)
        let container2 = try ModelContainer(
            for: schema,
            migrationPlan: RunalystMigrationPlan.self,
            configurations: [config]
        )
        let context2 = ModelContext(container2)
        let fetched = try context2.fetch(FetchDescriptor<RunRecord>())
        XCTAssertEqual(fetched.count, 1, "RunRecord should persist across app relaunches")
    }
}
