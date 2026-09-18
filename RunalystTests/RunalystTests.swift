import XCTest
import HealthKit
import SwiftData
@testable import Runalyst
import WorkoutKit

final class RunalystTests: XCTestCase {
    func testDrillWorkoutPlans() {
        for id in PreRunDrillId.allCases {
            let drill = PreRunDrill(id: id, previousCadence: 160)
            _ = drill.buildWorkoutPlan()
            print("Successfully built plan for \(id.rawValue)")
        }

        let alertThreshold = CadenceThresholdAlert.cadence(160.0)
        XCTAssertTrue(CustomWorkout.supportsAlert(alertThreshold, activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(3, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(2, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(1, .minutes), activity: .running, location: .outdoor))
        let hrZoneAlert = HeartRateZoneAlert(zone: 2)
        print("HR ZONE 2 SUPPORTS: \(CustomWorkout.supportsAlert(hrZoneAlert, activity: .running, location: .outdoor))")
    }

    func testZone2RunWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .zone2Run, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .zone2Run)
        XCTAssertEqual(template.title, "Zone 2 Run")
        XCTAssertEqual(template.defaultEffort, "Zone 2 Aerobic")
    }

    func testAerobicFlushWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .aerobicFlush, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .aerobicFlush)
        XCTAssertEqual(template.title, "Aerobic Flush")
        XCTAssertEqual(template.defaultEffort, "Zone 1 Active Recovery")
    }
}

@MainActor
final class HealthKitManagerTests: XCTestCase {

    var mockStore: MockHealthStore!
    var sut: HealthKitManager!

    override func setUp() async throws {
        mockStore = MockHealthStore()
    }

    override func tearDown() async throws {
        mockStore = nil
        sut = nil
    }

    func testRequestAuthorization_WhenHealthDataNotAvailable_ThrowsError() async {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { false })

        // Act & Assert
        do {
            try await sut.requestAuthorization()
            XCTFail("Expected error to be thrown")
        } catch {
            let hkError = error as? HKError
            XCTAssertEqual(hkError?.code, .errorHealthDataUnavailable)
        }

        XCTAssertFalse(mockStore.requestAuthorizationCalled)
    }

    func testRequestAuthorization_WhenAvailable_RequestsTypesAndUpdatesStatus() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        mockStore.authorizationStatusToReturn = .sharingAuthorized

        // Act
        try await sut.requestAuthorization()

        // Assert
        XCTAssertTrue(mockStore.requestAuthorizationCalled)
        XCTAssertEqual(mockStore.requestedTypesToShare?.isEmpty, true)

        let readTypes = try XCTUnwrap(mockStore.requestedTypesToRead)
        XCTAssertTrue(readTypes.contains(HKObjectType.workoutType()))
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            XCTAssertTrue(readTypes.contains(hrType))
        }

        XCTAssertTrue(mockStore.authorizationStatusCalled)
        XCTAssertTrue(mockStore.enableBackgroundDeliveryCalled)
        XCTAssertEqual(mockStore.enabledBackgroundDeliveryType, HKObjectType.workoutType())

        XCTAssertTrue(sut.isAuthorized)
    }

    func testRequestAuthorization_WhenAuthorizationFails_ThrowsError() async {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        let expectedError = NSError(domain: "Test", code: 1, userInfo: nil)
        mockStore.requestAuthorizationError = expectedError

        // Act & Assert
        do {
            try await sut.requestAuthorization()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }

        XCTAssertFalse(mockStore.authorizationStatusCalled)
        XCTAssertFalse(mockStore.enableBackgroundDeliveryCalled)
    }
}

final class MockHealthStore: @unchecked Sendable, HKHealthStoreProtocol {
    var requestAuthorizationCalled = false
    var requestedTypesToShare: Set<HKSampleType>?
    var requestedTypesToRead: Set<HKObjectType>?
    var requestAuthorizationError: Error?

    var authorizationStatusCalled = false
    var authorizationStatusToReturn: HKAuthorizationStatus = .notDetermined

    var enableBackgroundDeliveryCalled = false
    var enabledBackgroundDeliveryType: HKObjectType?
    var enableBackgroundDeliveryError: Error?

    var executeQueryCalled = false

    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        requestAuthorizationCalled = true
        requestedTypesToShare = typesToShare
        requestedTypesToRead = typesToRead

        if let error = requestAuthorizationError {
            throw error
        }
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusCalled = true
        return authorizationStatusToReturn
    }

    func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        return .shouldRequest
    }

    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws {
        enableBackgroundDeliveryCalled = true
        enabledBackgroundDeliveryType = type

        if let error = enableBackgroundDeliveryError {
            throw error
        }
    }

    func execute(_ query: HKQuery) {
        executeQueryCalled = true
    }
}

final class FramboiseEngineTests: XCTestCase {
    var engine: FramboiseEngine!

    override func setUp() async throws {
        engine = FramboiseEngine()
    }

    func testTrimDeadStops() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 100),
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 0.1, meanPaceSecPerKm: 0, meanCadence: 20, meanHR: 120)
        ]

        let trimmed = await engine.trimDeadStops(buckets: buckets)
        XCTAssertEqual(trimmed.count, 1)
        XCTAssertEqual(trimmed[0].distanceMeters, 100)
    }

    func testCalculateWorkingAverages() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingCadence, 162)
        XCTAssertEqual(averages.workingHR, 142)
        XCTAssertEqual(averages.workingDistance, 400, accuracy: 0.01)
        XCTAssertEqual(averages.workingDuration, 120, accuracy: 0.01)
        // 400 meters in 120 seconds -> 120 / 0.4 = 300 sec/km
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01)
    }

    func testCalculateWorkingAverages_VerticalOscillationExcludesZeroBuckets() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140, meanVerticalOscillation: 8.8),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144, meanVerticalOscillation: 0.0), // no sample this minute
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 162, meanHR: 142, meanVerticalOscillation: 9.2)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        // Only the two non-zero buckets (8.8 and 9.2) should be averaged -> 9.0, not (8.8 + 0 + 9.2) / 3 = 6.0
        XCTAssertEqual(averages.workingOscillation, 9.0, accuracy: 0.01)
    }

    func testFilterRunningSamples_DropsStationaryAndWalking() async {
        let buckets = [
            // Stationary: 0 m/s, 0 SPM -> Drop
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 90),
            // Walking break: 60m in 60s = 1.0 m/s (< 1.5), cadence 105 (< 130) -> Drop
            BucketData(startTime: Date(), distanceMeters: 60, meanPaceSecPerKm: 1000, meanCadence: 105, meanHR: 110),
            // Running by speed: 120m in 60s = 2.0 m/s (> 1.5), cadence 125 -> Keep
            BucketData(startTime: Date(), distanceMeters: 120, meanPaceSecPerKm: 500, meanCadence: 125, meanHR: 145),
            // Running by cadence: 80m in 60s = 1.33 m/s, cadence 150 (> 130) -> Keep
            BucketData(startTime: Date(), distanceMeters: 80, meanPaceSecPerKm: 750, meanCadence: 150, meanHR: 140)
        ]

        let filtered = await engine.filterRunningSamples(buckets: buckets)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].distanceMeters, 120)
        XCTAssertEqual(filtered[1].distanceMeters, 80)
    }

    func testCalculateWorkingAverages_EnforcesDurationSafetyConstraint() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140)
        ]
        // 2 buckets = 120 seconds, but raw workout duration was 100 seconds
        let averages = await engine.calculateWorkingAverages(trimmed: buckets, rawWorkoutDuration: 100)
        XCTAssertEqual(averages.workingDuration, 100, "workingDuration must be <= rawWorkoutDuration")
    }

    func testCalculateWorkingAverages_PureAggregateRatioPace() async {
        // Harmonic distortion check:
        // Bucket 1: 100m in 60s (pace = 600 s/km)
        // Bucket 2: 300m in 60s (pace = 200 s/km)
        // Arithmetic mean of paces = (600 + 200) / 2 = 400 s/km (WRONG)
        // Aggregate ratio = 120s / 0.4km = 300 s/km (CORRECT)
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 600, meanCadence: 150, meanHR: 130),
            BucketData(startTime: Date(), distanceMeters: 300, meanPaceSecPerKm: 200, meanCadence: 170, meanHR: 160)
        ]
        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01, "workingPace must use pure aggregate ratio (duration / distanceKm)")
    }

    func testCalculatePaceCV() async {
        let paces = [300.0, 300.0, 300.0, 300.0]
        let calculatedCV = await engine.calculatePaceCV(bucketPaces: paces)
        XCTAssertEqual(calculatedCV, 0, accuracy: 0.001)

        let variablePaces = [200.0, 400.0]
        let calculatedCV2 = await engine.calculatePaceCV(bucketPaces: variablePaces)
        // mean = 300. variance = sum((x-300)^2) / 1 = 10000 + 10000 = 20000. sigma = sqrt(20000) ~ 141.42
        // CV = 141.42 / 300 = 0.471
        XCTAssertEqual(calculatedCV2, 0.471, accuracy: 0.01)
    }

    func testCalculatePaceSlope() async {
        let paces = [300.0, 310.0, 320.0, 330.0]
        let slope = await engine.calculatePaceSlope(bucketPaces: paces)
        // Increasing by 10 per bucket -> slope = +10
        XCTAssertEqual(slope, 10, accuracy: 0.01)

        let paces2 = [300.0, 290.0, 280.0, 270.0]
        let slope2 = await engine.calculatePaceSlope(bucketPaces: paces2)
        // Decreasing by 10 per bucket -> slope = -10
        XCTAssertEqual(slope2, -10, accuracy: 0.01)
    }
}

final class SafeTargetCalculatorTests: XCTestCase {
    func testSafeCadenceTarget() {
        let unit = HKUnit.count().unitDivided(by: .minute())

        // Requested normal cadence
        let target1 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 165, previousCadence: 160)
        XCTAssertEqual(target1?.doubleValue(for: unit), 165)

        // Requested extremely high cadence (should be clamped to 185)
        let target2 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 200, previousCadence: 160)
        XCTAssertEqual(target2?.doubleValue(for: unit), 185)

        // Requested lower than previous cadence (should be clamped to floor of previous)
        let target3 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 140, previousCadence: 160)
        XCTAssertEqual(target3?.doubleValue(for: unit), 160)

        // No requested cadence
        let target4 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: nil, previousCadence: 160)
        XCTAssertNil(target4)
    }
}

final class PaceFormatterTests: XCTestCase {
    func testFormatPaceMetric() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")

        let pace1 = PaceFormatter.formatPace(secondsPerKilometer: 300) // 5:00/km
        XCTAssertEqual(pace1, "5:00/km")

        let pace2 = PaceFormatter.formatPace(secondsPerKilometer: 315) // 5:15/km
        XCTAssertEqual(pace2, "5:15/km")
    }

    func testFormatPaceImperial() {
        UserDefaults.standard.set(false, forKey: "useMetricSystem")

        // 300 sec/km * 1.609344 = 482.8032 sec/mi -> 8 min 3 sec -> 8:03/mi
        let pace1 = PaceFormatter.formatPace(secondsPerKilometer: 300)
        XCTAssertEqual(pace1, "8:03/mi")
    }
}

final class DrillTemplateTests: XCTestCase {
    func testDrillTemplateBaselinesAndCueInterpolation() {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let thirtyDayCadence = 151
        let computedTarget = template.calculateTargetCadence(thirtyDayCadence)

        // Target should be calculated strictly from the 30-day baseline (151 * 1.05 = 158), returning a range 155-161
        XCTAssertEqual(computedTarget, "155-161")

        // Instructional cues provide prescriptive biomechanical focus
        let cue = template.generateInstructionalCue(computedTarget)
        XCTAssertFalse(cue.isEmpty, "Instructional cue should be present")
        XCTAssertFalse(cue.contains("151 SPM"), "Instructional cue must not repeat the raw baseline")
    }
}

final class CardiacGuardrailTests: XCTestCase {
    func testCardiacGuardrailHighHR() async {
        let framboise = FramboiseEngine()

        // High HR run (175 BPM, zone 4 = 0.5) must never be classified as Easy Run or Recovery Run
        let highHRClass = await framboise.classifyRun(cv: 0.04, slope: -0.1, zone4: 0.5, durationMinutes: 30, averageHR: 175)
        XCTAssertNotEqual(highHRClass, "Easy Run")
        XCTAssertNotEqual(highHRClass, "Recovery Run")
        XCTAssertTrue(highHRClass == "Tempo Run" || highHRClass == "Intervals" || highHRClass == "Progression Run" || highHRClass == "Steady Effort")

        // Low HR run (125 BPM, zone 4 = 0.04, duration 45 min) is Easy Run
        let lowHRClass = await framboise.classifyRun(cv: 0.04, slope: -0.1, zone4: 0.04, durationMinutes: 45, averageHR: 125)
        XCTAssertEqual(lowHRClass, "Easy Run")
    }
}

@MainActor
final class LiveCoachEngineTests: XCTestCase {
    var engine: LiveCoachEngine!

    override func setUp() async throws {
        engine = LiveCoachEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    func testTranslatePrescription_ValidPattern() {
        let workout = engine.translate(prescription: "4x400m intervals", targetSPM: 165)
        XCTAssertNotNil(workout)
        XCTAssertEqual(workout?.displayName, "AI Prescribed Workout")
        XCTAssertEqual(workout?.activity, .running)
        XCTAssertEqual(workout?.location, .outdoor)
        XCTAssertEqual(workout?.blocks.count, 1)
        XCTAssertEqual(workout?.blocks.first?.iterations, 4)
        XCTAssertEqual(workout?.blocks.first?.steps.count, 2)
    }

    func testTranslatePrescription_InvalidPattern_ReturnsNil() {
        let workout = engine.translate(prescription: "steady recovery jog", targetSPM: 150)
        XCTAssertNil(workout)
    }

    func testMetronome_StateAndSilentMode() {
        engine.silentModeEnabled = true
        engine.startMetronome(targetSPM: 160)
        engine.stopMetronome()
        XCTAssertTrue(engine.silentModeEnabled)

        engine.silentModeEnabled = false
        engine.startMetronome(targetSPM: 0)
        engine.stopMetronome()
    }
}

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

@MainActor
final class CoachingEngineDataTests: XCTestCase {
    func testRunDataForAIInitialization() {
        let runData = RunDataForAI(
            workoutType: "Tempo Run",
            runnerGoal: "Sub-20 5K",
            directiveContext: "The runner is overstriding (low cadence).",
            paceContext: "Current: 5:00/km, Baseline: 5:15/km",
            hrContext: "Current: 155 BPM, Baseline: 150 BPM",
            cadenceContext: "Current: 148 SPM, Baseline: 156 SPM",
            zone4Context: "20% in Zone 4",
            cvContext: "0.045",
            slopeContext: "0.012",
            intervalCadence: "162",
            recoveryCadence: "150"
        )

        XCTAssertEqual(runData.workoutType, "Tempo Run")
        XCTAssertEqual(runData.runnerGoal, "Sub-20 5K")
        XCTAssertEqual(runData.intervalCadence, "162")
        XCTAssertEqual(runData.recoveryCadence, "150")
        XCTAssertTrue(runData.directiveContext.contains("overstriding"))
        XCTAssertTrue(runData.paceContext.contains("5:00/km"))
        XCTAssertTrue(runData.hrContext.contains("155 BPM"))
        XCTAssertTrue(runData.cadenceContext.contains("148 SPM"))
        XCTAssertTrue(runData.zone4Context.contains("20%"))
        XCTAssertTrue(runData.cvContext.contains("0.045"))
        XCTAssertTrue(runData.slopeContext.contains("0.012"))
    }

    func testAggregateRunDataForAIInitialization() {
        let aggData = AggregateRunDataForAI(
            paceContext: "5:10/km",
            hrContext: "148 BPM",
            cadenceContext: "162 SPM",
            zone4Context: "15%",
            cvContext: "0.035",
            slopeContext: "-0.010",
            stageContext: "Stage 2: Aerobic Expansion"
        )

        XCTAssertEqual(aggData.stageContext, "Stage 2: Aerobic Expansion")
    }

    func testBaselineStatsInitialization() {
        let stats = BaselineStats(avgPace: 300, avgCadence: 165, avgHR: 145, avgOscillation: 9.5)
        XCTAssertEqual(stats.avgPace, 300)
        XCTAssertEqual(stats.avgCadence, 165)
        XCTAssertEqual(stats.avgHR, 145)
        XCTAssertEqual(stats.avgOscillation, 9.5)
    }

    func testSparseRunBiometricGuardrail() async throws {
        if #available(iOS 26.0, *) {
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            let runId: PersistentIdentifier = {
                let context = container.mainContext
                let sparseRun = RunRecord(
                    hkWorkoutID: UUID(),
                    date: Date(),
                    totalDistanceMeters: 5000,
                    duration: 2700,
                    rawAvgPace: 540,
                    rawAvgHeartRate: 0,
                    rawAvgCadence: 0,
                    workingAvgPace: 540,
                    workingAvgCadence: 0,
                    workingAvgHeartRate: 0,
                    workingAvgVerticalOscillation: nil,
                    rawAvgVerticalOscillation: nil,
                    workingDistanceMeters: 5000,
                    workingDurationSeconds: 2700,
                    paceCV: 0.04,
                    paceSlope: 0.0,
                    percentZone4: 0.0,
                    detectedTypeRaw: "Easy Run",
                    framboiseTags: []
                )
                context.insert(sparseRun)
                try? context.save()
                return sparseRun.persistentModelID
            }()

            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId)

            let fetched = container.mainContext.model(for: runId) as? RunRecord
            XCTAssertNil(fetched?.insight, "Runs lacking cadence and heart rate should not generate an AI insight")
        }
    }
}

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

final class TrainingCorrectionModelTests: XCTestCase {
    func testTrainingCorrectionInitialization() {
        let correction = TrainingCorrection(
            runRecordID: UUID(),
            originalLabel: "Tempo Run",
            correctedLabel: "Intervals",
            featureVector: [0.18, -0.05, 0.45],
            createdAt: Date(),
            isProcessed: false
        )
        XCTAssertEqual(correction.originalLabel, "Tempo Run")
        XCTAssertEqual(correction.correctedLabel, "Intervals")
        XCTAssertEqual(correction.featureVector.count, 3)
        XCTAssertFalse(correction.isProcessed)
    }
}

final class LiveCoachDTOCodableTests: XCTestCase {
    func testWatchRunRecordDTOEncodingDecoding() throws {
        let original = WatchRunRecordDTO(
            id: UUID(),
            date: Date(),
            distance: 5200.0,
            duration: 1600.0,
            avgPace: 307.7,
            avgHeartRate: 154,
            avgCadence: 168,
            verticalOscillation: 8.4,
            groundContactTime: 235.0,
            strideLength: 1.15
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchRunRecordDTO.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.distance, 5200.0)
        XCTAssertEqual(decoded.avgHeartRate, 154)
        XCTAssertEqual(decoded.avgCadence, 168)
        XCTAssertEqual(decoded.verticalOscillation, 8.4)
    }

    func testDrillRecommendationDTOEncodingDecoding() throws {
        let original = DrillRecommendationDTO(
            drillTitle: "Cadence Pyramids",
            drillPurpose: "Turnover improvement",
            drillWork: "4 x 30s accelerations",
            drillCues: "Quick steps",
            drillEffort: "Controlled surge",
            drillRecovery: "60s easy jog",
            targetCadence: "168 SPM"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrillRecommendationDTO.self, from: data)

        XCTAssertEqual(decoded.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(decoded.drillPurpose, "Turnover improvement")
        XCTAssertEqual(decoded.drillRecovery, "60s easy jog")
        XCTAssertEqual(decoded.targetCadence, "168 SPM")
    }

    func testDrillPrescriptionDTOEncodingDecodingWithDurationAndHaptics() throws {
        let original = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            purpose: "Turnover improvement",
            targetCadence: "172-176",
            previousCadence: 160,
            durationMinutes: 30,
            hapticMode: "On"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrillPrescriptionDTO.self, from: data)

        XCTAssertEqual(decoded.title, "Cadence Pyramids")
        XCTAssertEqual(decoded.targetCadence, "172-176")
        XCTAssertEqual(decoded.durationMinutes, 30)
        XCTAssertEqual(decoded.hapticMode, "On")
    }

    func testDrillDurationScaling() {
        let drill = PreRunDrill(id: .cadencePyramids, previousCadence: 160)

        let work10 = drill.workString(for: .tenMinutes)
        let work15 = drill.workString(for: .fifteenMinutes)
        let work30 = drill.workString(for: .thirtyMinutes)

        XCTAssertTrue(work10.contains("4 x 30 sec work"), "Expected 4 x 30 sec work in 10-min version, got: \(work10)")
        XCTAssertTrue(work15.contains("4 x 1 min work"), "Expected 4 x 1 min work in 15-min version, got: \(work15)")
        XCTAssertTrue(work30.contains("6 x 90 sec work"), "Expected 6 x 90 sec work in 30-min version, got: \(work30)")

        let rec10 = drill.recoveryString(for: .tenMinutes)
        let rec15 = drill.recoveryString(for: .fifteenMinutes)
        let rec30 = drill.recoveryString(for: .thirtyMinutes)

        XCTAssertTrue(rec10.contains("45 sec walk recovery"), "Expected 45 sec walk recovery, got: \(rec10)")
        XCTAssertTrue(rec15.contains("90 sec walk recovery"), "Expected 90 sec walk recovery, got: \(rec15)")
        XCTAssertTrue(rec30.contains("2 min walk recovery"), "Expected 2 min walk recovery, got: \(rec30)")

        let drill10 = PreRunDrill(id: .cadencePyramids, previousCadence: 160, duration: .tenMinutes)
        let drill30 = PreRunDrill(id: .cadencePyramids, previousCadence: 160, duration: .thirtyMinutes)
        let plan10 = drill10.buildWorkoutPlan()
        let plan30 = drill30.buildWorkoutPlan()
        XCTAssertNotNil(plan10)
        XCTAssertNotNil(plan30)

        // Verify DrillTemplate duration scaling
        let template = DrillTemplate.template(for: .cadencePyramids)
        XCTAssertTrue(template.workString(for: .tenMinutes).contains("4 x 30 sec work"))
        XCTAssertTrue(template.workString(for: .fifteenMinutes).contains("4 x 1 min work"))
        XCTAssertTrue(template.workString(for: .thirtyMinutes).contains("6 x 90 sec work"))
        XCTAssertTrue(template.recoveryString(for: .tenMinutes).contains("45 sec walk recovery"))
        XCTAssertTrue(template.recoveryString(for: .thirtyMinutes).contains("2 min walk recovery"))
    }

    func testLiveCoachHapticFeedbackModes() {
        // Off
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .off, currentSPM: 160, targetSPM: 170, intervalElapsedSeconds: 5))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .off, currentSPM: 150, targetSPM: 170, intervalElapsedSeconds: 30))

        // On: rhythm pulse during first 20s of interval
        XCTAssertTrue(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 170, targetSPM: 170, intervalElapsedSeconds: 10))

        // On: corrective nudge when cadence drops below target - 2 SPM after lead-in
        XCTAssertTrue(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 167, targetSPM: 170, intervalElapsedSeconds: 30))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 170, targetSPM: 170, intervalElapsedSeconds: 30))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 175, targetSPM: 170, intervalElapsedSeconds: 30))
    }

    func testPreloadFilter_Past7DaysOrPast5Runs() {
        let calendar = Calendar.current
        let today = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        // Create 10 dummy run dates (newest first, indices 0 to 9)
        // 0: today (within 7d, index < 5) -> preload
        // 1: 2d ago (within 7d, index < 5) -> preload
        // 2: 5d ago (within 7d, index < 5) -> preload
        // 3: 8d ago (> 7d, index < 5) -> preload (because index < 5)
        // 4: 9d ago (> 7d, index < 5) -> preload (because index < 5)
        // 5: 10d ago (> 7d, index >= 5) -> skip
        // 6: 12d ago (> 7d, index >= 5) -> skip
        // 7: 15d ago (> 7d, index >= 5) -> skip
        let daysAgoList = [0, 2, 5, 8, 9, 10, 12, 15]
        let dummyRuns = daysAgoList.map { days in
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }

        let preloadedIndices = dummyRuns.enumerated().compactMap { index, date -> Int? in
            if date >= sevenDaysAgo || index < 5 {
                return index
            }
            return nil
        }

        XCTAssertEqual(preloadedIndices, [0, 1, 2, 3, 4])
    }

    func testDrillRecommendationEligibility_OlderThan7Days() {
        let calendar = Calendar.current
        let now = Date()

        let recentDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let oldDate = calendar.date(byAdding: .day, value: -10, to: now) ?? now

        let recentDays = calendar.dateComponents([.day], from: recentDate, to: now).day ?? 0
        let oldDays = calendar.dateComponents([.day], from: oldDate, to: now).day ?? 0

        XCTAssertFalse(recentDays > 7, "Recent run should be <= 7 days")
        XCTAssertTrue(oldDays > 7, "Old run should be > 7 days")
    }
}

@MainActor
final class PrescribedDrillRecognitionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WorkoutBridge.clearIntents()
    }

    override func tearDown() {
        WorkoutBridge.clearIntents()
        super.tearDown()
    }

    func testScheduledDrillIntentPersistence() {
        let intent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: Date(),
            durationMinutes: 15,
            targetCadence: "170-174"
        )
        WorkoutBridge.saveDrillIntent(intent)

        let recent = WorkoutBridge.recentIntents()
        XCTAssertTrue(recent.contains(where: { $0.drillTitle == "Cadence Pyramids" && $0.durationMinutes == 15 }))
    }

    func testWorkoutBridgeMatchDrillDirectMetadata() {
        let workoutDate = Date()
        let metadata: [String: Any] = [
            "HKWorkoutPlanDisplayName": "Cadence Pyramids"
        ]

        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 900,
            metadata: metadata
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(matched?.preRunDrillId, "cadence_pyramids")
    }

    func testWorkoutBridgeMatchDrillIntentWindow() {
        let scheduledDate = Date().addingTimeInterval(-600) // 10 mins ago
        let intent = ScheduledDrillIntent(
            drillTitle: "Rhythm Intervals",
            preRunDrillId: "rhythm_intervals",
            scheduledDate: scheduledDate,
            durationMinutes: 15,
            targetCadence: "165"
        )
        WorkoutBridge.saveDrillIntent(intent)

        // Incoming workout completed 2 minutes ago with matching duration (~15 mins = 920 sec)
        let workoutDate = Date().addingTimeInterval(-120)
        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 920,
            metadata: nil
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Rhythm Intervals")
    }

    func testWorkoutBridgeMatchDrillHistoricalIntentWindow() {
        // Scheduled 7 days ago (like the user's run from Sept 10)
        let scheduledDate = Date().addingTimeInterval(-7 * 24 * 3600)
        let intent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: scheduledDate,
            durationMinutes: 15,
            targetCadence: "160"
        )
        WorkoutBridge.saveDrillIntent(intent)

        // Workout completed 5 minutes after scheduled time
        let workoutDate = scheduledDate.addingTimeInterval(300)
        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 904, // 15:04
            metadata: nil
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(matched?.preRunDrillId, "cadence_pyramids")
    }

    func testWorkoutBridgeMatchNestedMetadata() {
        let workoutDate = Date()
        let metadata: [String: Any] = [
            "customData": [
                "subKey": "Outdoor Run - Cadence Pyramids"
            ]
        ]

        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 900,
            metadata: metadata
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
    }

    func testWorkoutBridgeMatchesDistinctDrillTitlesWithoutCollidingToCadencePyramids() {
        let date = Date()

        // 1. Rhythm Intervals metadata
        let rhythmMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Rhythm Intervals"]
        )
        XCTAssertEqual(rhythmMatched?.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(rhythmMatched?.preRunDrillId, "rhythm_intervals")

        // 2. Strides metadata
        let stridesMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Strides"]
        )
        XCTAssertEqual(stridesMatched?.drillTitle, "Strides")
        XCTAssertEqual(stridesMatched?.preRunDrillId, "strides")

        // 3. Tempo Surges metadata
        let surgesMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Tempo Surges"]
        )
        XCTAssertEqual(surgesMatched?.drillTitle, "Tempo Surges")
        XCTAssertEqual(surgesMatched?.preRunDrillId, "tempo_surges")

        // 4. Form Primer metadata
        let primerMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 600,
            metadata: ["HKWorkoutPlanDisplayName": "Form Primer"]
        )
        XCTAssertEqual(primerMatched?.drillTitle, "Form Primer")
        XCTAssertEqual(primerMatched?.preRunDrillId, "neuromuscular_primer")

        // 5. Unscheduled workout with no drill metadata must NOT match any drill (even if 900 seconds)
        let unprescribed = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKMetadataKeyWorkoutBrandName": "Apple Workout"]
        )
        XCTAssertNil(unprescribed, "Unscheduled runs with no drill metadata must not match as a drill")
    }

    func testRunBaselineDataIncludesAllRunsWeighted() {
        let now = Date()
        let allRuns = [
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 2), pace: 300, hr: 150, cadence: 165, duration: 2400, isPrescribedDrill: false),
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 4), pace: 310, hr: 152, cadence: 164, duration: 2700, isPrescribedDrill: false),
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 6), pace: 295, hr: 148, cadence: 166, duration: 2500, isPrescribedDrill: false),
            // Short 15-min drill with sprint pace/cadence
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 1), pace: 220, hr: 175, cadence: 185, duration: 900, isPrescribedDrill: true)
        ]

        // All runs are included (every run counts)
        XCTAssertEqual(allRuns.count, 4)

        // Duration-weighted baseline calculation
        let totalDuration = allRuns.map(\.duration).reduce(0, +)
        let weightedCadence = allRuns.map { $0.cadence * $0.duration }.reduce(0, +) / totalDuration

        // With duration weighting: (165*2400 + 164*2700 + 166*2500 + 185*900) / 8500 = ~167.1
        // The 15-min drill contributes proportionally (only 900s out of 8500s) without being discarded
        XCTAssertEqual(weightedCadence, 167.1, accuracy: 0.2)
    }

    func testDrillAutoCompletionAndTrainingCorrection() throws {
        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let drill = DrillRecommendation(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            drillPurpose: "Turnover improvement",
            isCompleted: false
        )
        context.insert(drill)
        try context.save()

        XCTAssertFalse(drill.isCompleted)

        // Simulate incoming recognized drill
        let newRunID = UUID()
        let drillTitle = "Cadence Pyramids"
        let framboiseTags = ["prescribedDrill", "cadence_pyramids"]

        let openDrillsDescriptor = FetchDescriptor<DrillRecommendation>(
            predicate: #Predicate<DrillRecommendation> { item in
                !item.isCompleted
            }
        )
        if let openDrills = try? context.fetch(openDrillsDescriptor) {
            for item in openDrills {
                let matchesId = item.preRunDrillId.map { framboiseTags.contains($0) } ?? false
                let matchesTitle = item.drillTitle.localizedCaseInsensitiveCompare(drillTitle) == .orderedSame
                if matchesTitle || matchesId {
                    item.isCompleted = true
                }
            }
        }

        // Insert ground-truth TrainingCorrection
        let correction = TrainingCorrection(
            runRecordID: newRunID,
            originalLabel: "Prescribed Drill",
            correctedLabel: drillTitle,
            featureVector: [280.0, 0.12, -0.02, 0.25, 15.0],
            createdAt: Date(),
            isProcessed: false
        )
        context.insert(correction)
        try context.save()

        XCTAssertTrue(drill.isCompleted, "Matching drill recommendation should be marked as completed")

        let fetchedCorrections = try context.fetch(FetchDescriptor<TrainingCorrection>())
        XCTAssertEqual(fetchedCorrections.count, 1)
        XCTAssertEqual(fetchedCorrections.first?.correctedLabel, "Cadence Pyramids")
        XCTAssertEqual(fetchedCorrections.first?.featureVector.count, 5)
    }

    func testDrillToRunClassificationMapping() {
        // Explicit user requirement cases
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Rhythm Intervals"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "rhythm_intervals"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Recovery Jog"), "Recovery Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "recovery_jog"), "Recovery Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Cadence Pyramids"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Tempo Surges"), "Tempo Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Strides"), "Intervals")

        // Canonical drill titles
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "rhythm_intervals"), "Rhythm Intervals")
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "recovery_jog"), "Recovery Jog")

        // Standard run classifications must NEVER be treated as drills or map to drills
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Intervals"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Tempo Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Recovery Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Steady Effort"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Long Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "intervals"))

        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Intervals"))
        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Tempo Run"))
        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Recovery Run"))
    }

    func testDrillAdherenceTierProperties() {
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeText, "Exceeded")
        XCTAssertEqual(DrillAdherenceTier.met.badgeText, "Met")
        XCTAssertEqual(DrillAdherenceTier.partiallyMet.badgeText, "Partially Met")
        XCTAssertEqual(DrillAdherenceTier.notMet.badgeText, "Not Met")

        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeIcon, "star.fill")
        XCTAssertEqual(DrillAdherenceTier.met.badgeIcon, "checkmark")
        XCTAssertEqual(DrillAdherenceTier.partiallyMet.badgeIcon, "minus")
        XCTAssertEqual(DrillAdherenceTier.notMet.badgeIcon, "xmark")
    }

    func testDrillTitlesAreUniqueAndZone2RunAppearsOnce() {
        let titles = PreRunDrillId.allCases.map(\.title)
        let uniqueTitles = Set(titles)
        XCTAssertEqual(titles.count, uniqueTitles.count, "All drill titles in PreRunDrillId.allCases must be unique without duplicates")

        let zone2Occurrences = titles.filter { $0 == "Zone 2 Run" }
        XCTAssertEqual(zone2Occurrences.count, 1, "Zone 2 Run must only appear once in allCases")

        // Verify legacy mapping
        XCTAssertEqual(PreRunDrillId(rawValue: "aerobic_base_builder"), .zone2Run)
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "aerobic_base_builder"), "Zone 2 Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "aerobic_base_builder"), "Easy Run")
    }

    func testCadenceStabilitySteadyEffortClassification() async {
        let modelManager = ModelManager()
        let framboise = FramboiseEngine()

        // Reproduces the exact user's run:
        // High HR (170 BPM), high Zone 4 (0.85), pace CV = 0.09, duration = 27 min
        // BUT cadenceCV = 0.012 (rock-solid turnover at 161-162 SPM)
        let classification = await modelManager.predictRunType(
            paceDelta: 0.0,
            hrDelta: 20.0,
            percentZone4: 0.85,
            cadenceDelta: 1.0,
            verticalOscillation: 9.9,
            runnerStage: 1,
            cv: 0.09,
            slope: -0.05,
            durationMinutes: 27.0,
            cadenceCV: 0.012,
            rawAverageHR: 170.0
        )

        // Must classify as Steady Effort (or Tempo Run), NEVER Fartlek or Intervals!
        XCTAssertNotEqual(classification, "Fartlek", "Rock-solid cadence (cadenceCV < 0.025) must never be classified as Fartlek")
        XCTAssertNotEqual(classification, "Intervals", "Rock-solid cadence (cadenceCV < 0.025) must never be classified as Intervals")
        XCTAssertTrue(classification == "Steady Effort" || classification == "Tempo Run")

        // Direct test on FramboiseEngine weighted scoring
        let directClass = await framboise.classifyRun(
            cv: 0.09,
            slope: -0.05,
            zone4: 0.85,
            durationMinutes: 27.0,
            cadenceCV: 0.012,
            averageHR: 170.0,
            paceDelta: 0.0,
            hrDelta: 20.0
        )
        XCTAssertEqual(directClass, "Steady Effort")
    }

    func testIntermittentIntervalClassification() async {
        let framboise = FramboiseEngine()

        // Intermittent workout: high cadence volatility (cadenceCV = 0.042) and high pace CV (0.14)
        let intervalClass = await framboise.classifyRun(
            cv: 0.14,
            slope: 0.0,
            zone4: 0.50,
            durationMinutes: 25.0,
            cadenceCV: 0.042,
            averageHR: 165.0
        )
        XCTAssertEqual(intervalClass, "Intervals")
    }

    func testDrillIntervalEvaluatorRepScoring() {
        // Construct synthetic 15-second buckets for a 15-minute Cadence Pyramids drill
        // 180s warmup, 4 reps of (60s work, 90s recovery), 120s cooldown
        // Target: 166-172 SPM for 160 baseline
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now

        // Warmup: 12 buckets (180s) at 150 SPM
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 40, durationSeconds: 15, meanPaceSecPerKm: 375, meanCadence: 150, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 1: 4 buckets (60s) at 170 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 170, meanHR: 160))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 1: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 2: 4 buckets (60s) at 168 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 168, meanHR: 162))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 2: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 3: 4 buckets (60s) at 155 SPM (MISSED - too low)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 40, durationSeconds: 15, meanPaceSecPerKm: 375, meanCadence: 155, meanHR: 158))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 3: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 4: 4 buckets (60s) at 171 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 171, meanHR: 165))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 4: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        let summary = DrillIntervalEvaluator.evaluate(
            buckets: buckets,
            drillId: .cadencePyramids,
            baselineCadence: 160,
            workoutDuration: 900
        )

        // 3 out of 4 work reps met target
        XCTAssertEqual(summary.totalIntervals, 4)
        XCTAssertEqual(summary.intervalsMet, 3)
        XCTAssertEqual(summary.adherencePercentage, 75)
        XCTAssertEqual(summary.tier, .partiallyMet)
        XCTAssertEqual(summary.reps.count, 4)
        XCTAssertEqual(summary.reps[0].isMet, true)
        XCTAssertEqual(summary.reps[1].isMet, true)
        XCTAssertEqual(summary.reps[2].isMet, false)
        XCTAssertEqual(summary.reps[3].isMet, true)
        XCTAssertTrue(summary.workCadenceAvg >= 165)
        XCTAssertTrue(summary.recoveryCadenceAvg <= 140)

        // Verify framboise tags formatting and round-trip decoding
        let tags = summary.framboiseTags
        XCTAssertTrue(tags.contains("drillIntervals:3/4"))
        XCTAssertTrue(tags.contains("drillReps:1,1,0,1"))

        let reconstructed = DrillIntervalSummary.from(tags: tags, drillId: .cadencePyramids)
        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.intervalsMet, 3)
        XCTAssertEqual(reconstructed?.totalIntervals, 4)
        XCTAssertEqual(reconstructed?.tier, .partiallyMet)
    }

    func testDrillTitlesNeverContainUnderscores() {
        // Direct instantiation with raw underscore identifiers
        let drill1 = DrillRecommendation(drillTitle: "rhythm_intervals")
        XCTAssertEqual(drill1.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(drill1.formattedTitle, "Rhythm Intervals")

        let drill2 = DrillRecommendation(drillTitle: "cadence_pyramids")
        XCTAssertEqual(drill2.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(drill2.formattedTitle, "Cadence Pyramids")

        // Legacy record with raw string in property
        let legacyDrill = DrillRecommendation(drillTitle: "tempo_surges")
        legacyDrill.drillTitle = "tempo_surges"
        XCTAssertEqual(legacyDrill.formattedTitle, "Tempo Surges")

        // Canonical drill resolution across all raw identifiers
        for drill in PreRunDrillId.allCases {
            guard let resolved = PreRunDrillId.canonicalDrillTitle(for: drill.rawValue) else {
                XCTFail("Failed to resolve canonical title for \(drill.rawValue)")
                continue
            }
            XCTAssertFalse(resolved.contains("_"), "Canonical title for \(drill.rawValue) must not contain underscores")
            XCTAssertEqual(resolved, drill.title)
        }
    }

    @MainActor
    func testUserLinkedDrillNeverOverriddenByAutoMatch() {
        let workoutID = UUID()
        let initialRecord = RunRecord(
            hkWorkoutID: workoutID,
            date: Date(),
            totalDistanceMeters: 4000,
            duration: 1200,
            rawAvgPace: 300,
            rawAvgHeartRate: 155,
            rawAvgCadence: 162,
            workingAvgPace: 300,
            workingAvgCadence: 162,
            workingAvgHeartRate: 155,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.20,
            detectedTypeRaw: "Intervals",
            framboiseTags: ["prescribedDrill", "cadence_pyramids", "drill:Cadence Pyramids", "drillIntervals:3/4"]
        )

        // Seed old matched intent for Cadence Pyramids
        let oldIntent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: initialRecord.date,
            durationMinutes: 20,
            matchedWorkoutID: workoutID
        )
        WorkoutBridge.saveDrillIntent(oldIntent)

        // User updates drill to Rhythm Intervals
        WorkoutBridge.linkDrill(to: initialRecord, drillId: .rhythmIntervals)

        // Verify tags updated and user intent tagged
        XCTAssertTrue(initialRecord.framboiseTags.contains("userLinkedDrill"), "Must be tagged as userLinkedDrill")
        XCTAssertTrue(initialRecord.framboiseTags.contains("prescribedDrill"))
        XCTAssertTrue(initialRecord.framboiseTags.contains("drill:Rhythm Intervals"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drill:Cadence Pyramids"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("cadence_pyramids"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drillIntervals:3/4"), "Old drill interval scorecard tags must be cleared")

        // Verify old intent was replaced in recentIntents()
        let recent = WorkoutBridge.recentIntents()
        let matchingIntents = recent.filter { $0.matchedWorkoutID == workoutID }
        XCTAssertEqual(matchingIntents.count, 1)
        XCTAssertEqual(matchingIntents.first?.drillTitle, "Rhythm Intervals")

        // User unlinks the drill
        WorkoutBridge.unlinkDrill(from: initialRecord)
        XCTAssertTrue(initialRecord.framboiseTags.contains("userUnlinkedDrill"), "Must be tagged as userUnlinkedDrill")
        XCTAssertFalse(initialRecord.framboiseTags.contains("prescribedDrill"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drill:Rhythm Intervals"))
        XCTAssertFalse(WorkoutBridge.recentIntents().contains { $0.matchedWorkoutID == workoutID })
    }
}
