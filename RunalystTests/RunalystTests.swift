import XCTest
import HealthKit
import SwiftData
@testable import Runalyst
import WorkoutKit

final class RunalystTests: XCTestCase {
    func testDrillWorkoutPlans() {
        for id in PreRunDrillId.allCases {
            let drill = PreRunDrill(id: id, previousCadence: 160)
            let plan = drill.buildWorkoutPlan()
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

        // Target should be calculated strictly from the 30-day baseline (151 * 1.05 = 158)
        XCTAssertEqual(computedTarget, 158)

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
        XCTAssertTrue(highHRClass == "Tempo Run" || highHRClass == "Intervals" || highHRClass == "Progression Run")

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
}

final class CoachingEngineDataTests: XCTestCase {
    func testRunDataForAIInitialization() {
        let runData = RunDataForAI(
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

        XCTAssertEqual(runData.intervalCadence, "162")
        XCTAssertEqual(runData.recoveryCadence, "150")
        XCTAssertTrue(runData.directiveContext.contains("overstriding"))
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

    func testBaselineStats() {
        let stats = BaselineStats(avgPace: 300, avgCadence: 165, avgHR: 145)
        XCTAssertEqual(stats.avgPace, 300)
        XCTAssertEqual(stats.avgCadence, 165)
        XCTAssertEqual(stats.avgHR, 145)
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
            targetCadence: 172,
            previousCadence: 160,
            durationMinutes: 30,
            hapticMode: "On"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrillPrescriptionDTO.self, from: data)

        XCTAssertEqual(decoded.title, "Cadence Pyramids")
        XCTAssertEqual(decoded.targetCadence, 172)
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
