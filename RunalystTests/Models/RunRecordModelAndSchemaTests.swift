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

    func testRunRecordNormalizedClassification() {
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
            detectedTypeRaw: "steady"
        )

        // Legacy "steady" must normalize to canonical "Steady Effort"
        XCTAssertEqual(run.normalizedClassification, "Steady Effort")

        // Empty string must fallback to "Steady Effort"
        run.detectedTypeRaw = "   "
        XCTAssertEqual(run.normalizedClassification, "Steady Effort")

        // Standard classifications stay clean
        run.detectedTypeRaw = "Intervals"
        XCTAssertEqual(run.normalizedClassification, "Intervals")

        run.detectedTypeRaw = "Easy Run"
        XCTAssertEqual(run.normalizedClassification, "Easy Run")

        // Legacy drill names in detectedTypeRaw resolve to parent classification
        run.detectedTypeRaw = "Rhythm Intervals"
        XCTAssertEqual(run.normalizedClassification, "Intervals")

        run.detectedTypeRaw = "tempo_surges"
        XCTAssertEqual(run.normalizedClassification, "Tempo Run")
    }

    func testRunRecordPrescribedDrillNameAndExclusionOfTelemetry() {
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
            detectedTypeRaw: "Intervals",
            framboiseTags: ["drill:tempo_surges", "drillIntervals:1/1", "drillIntervals:3/3"]
        )

        // Resolves drill:tempo_surges to formatted title
        XCTAssertEqual(run.prescribedDrillName, "Tempo Surges")

        // Only internal diagnostic tags present -> must return nil
        run.framboiseTags = [
            "drillIntervals:1/1",
            "drillIntervals:3/3",
            "drillWorkCadence:163",
            "drillRecCadence:157",
            "deadStopsTrimmed:1",
            "prescribedDrill"
        ]
        XCTAssertNil(run.prescribedDrillName)

        // PreRunDrillId rawValue
        run.framboiseTags = ["cadence_pyramids"]
        XCTAssertEqual(run.prescribedDrillName, "Cadence Pyramids")

        // Completed drill recommendation
        run.framboiseTags = []
        let insight = CoachingInsight(headline: "Test", longitudinalObservation: "Test")
        let rec = DrillRecommendation(
            drillTitle: "Strides",
            drillPurpose: "Neuromuscular",
            drillWork: "4 x 20s",
            drillCues: "Fast",
            orderIndex: 0
        )
        rec.isCompleted = true
        insight.drillRecommendations = [rec]
        run.insight = insight
        XCTAssertEqual(run.prescribedDrillName, "Strides")
    }

    func testRunRecordMatchesFilter() {
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
            detectedTypeRaw: "Intervals",
            framboiseTags: ["drill:tempo_surges", "drillIntervals:1/1"]
        )

        // Matches canonical classification
        XCTAssertTrue(run.matchesFilter("Intervals"))
        XCTAssertTrue(run.matchesFilter("intervals"))

        // Matches drill name
        XCTAssertTrue(run.matchesFilter("Tempo Surges"))
        XCTAssertTrue(run.matchesFilter("tempo surges"))

        // Does NOT match non-matching classification or drill
        XCTAssertFalse(run.matchesFilter("Steady Effort"))
        XCTAssertFalse(run.matchesFilter("Cadence Pyramids"))

        // Does NOT match raw internal telemetry
        XCTAssertFalse(run.matchesFilter("drillIntervals:1/1"))
        XCTAssertFalse(run.matchesFilter("drill:tempo_surges"))
    }

    func testDashboardFiltersExcludeInternalTelemetryTags() {
        let run1 = RunRecord(
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
            detectedTypeRaw: "Intervals",
            framboiseTags: ["drill:tempo_surges", "drillIntervals:1/1", "drillIntervals:3/3"]
        )

        let run2 = RunRecord(
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
            detectedTypeRaw: "steady",
            framboiseTags: ["prescribedDrill", "deadStopsTrimmed:1"]
        )

        let run3 = RunRecord(
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
            detectedTypeRaw: "Easy Run",
            framboiseTags: []
        )

        let allRuns = [run1, run2, run3]

        // Replicate availableFilters computation
        var classifications = Set<String>()
        var drills = Set<String>()
        for run in allRuns {
            classifications.insert(run.normalizedClassification)
            if let drillName = run.prescribedDrillName {
                drills.insert(drillName)
            }
        }

        let canonicalOrder = [
            "Easy Run", "Steady Effort", "Tempo Run", "Intervals",
            "Long Run", "Progression Run", "Recovery Run", "Fartlek",
            "Hill Repeats", "Urban Traffic"
        ]

        let sortedClassifications = canonicalOrder.filter { classifications.contains($0) }
            + classifications.filter { !canonicalOrder.contains($0) }.sorted()
        let sortedDrills = drills.sorted()
        let availableFilters = sortedClassifications + sortedDrills

        // Expected clean filters in canonical order
        XCTAssertEqual(availableFilters, ["Easy Run", "Steady Effort", "Intervals", "Tempo Surges"])

        // Strict verification: No colons, slashes, or diagnostic tokens
        for filter in availableFilters {
            XCTAssertFalse(filter.contains(":"), "Filter should never contain colons: \(filter)")
            XCTAssertFalse(filter.contains("/"), "Filter should never contain slashes: \(filter)")
            XCTAssertFalse(filter.hasPrefix("drill"), "Filter should not be raw drill tag: \(filter)")
            XCTAssertFalse(filter == "prescribedDrill", "Filter should not be boolean tag")
            XCTAssertFalse(filter == "steady", "Filter should not be lowercase 'steady'")
        }
    }

    func testOnboardingViewInitializationAndCallbacks() {
        var syncTriggered = false
        var completedTriggered = false

        let view = OnboardingView(
            isReplay: false,
            isSyncing: true,
            syncProgress: (current: 5, total: 20),
            syncStatusMessage: "Calibrating History",
            onStartSync: {
                syncTriggered = true
            },
            onComplete: {
                completedTriggered = true
            }
        )

        XCTAssertFalse(view.isReplay)
        XCTAssertTrue(view.isSyncing)
        XCTAssertEqual(view.syncProgress?.current, 5)
        XCTAssertEqual(view.syncProgress?.total, 20)
        XCTAssertEqual(view.syncStatusMessage, "Calibrating History")

        view.onStartSync?()
        XCTAssertTrue(syncTriggered)

        view.onComplete?()
        XCTAssertTrue(completedTriggered)

        let embeddedAbout = AboutRunalystView(isEmbedded: true)
        XCTAssertTrue(embeddedAbout.isEmbedded)

        let standaloneAbout = AboutRunalystView(isEmbedded: false)
        XCTAssertFalse(standaloneAbout.isEmbedded)
    }
}
