import XCTest
import HealthKit

@testable import Runalyst

import WorkoutKit

final class RunalystTests: XCTestCase {
    func testDrillWorkoutPlans() {
        for id in PreRunDrillId.allCases {
            let drill = PreRunDrill(id: id, previousCadence: 160)
            let plan = drill.buildWorkoutPlan()
            print("Successfully built plan for \(id.rawValue)")
        }
        
        let alertCpm = CadenceRangeAlert.cadence(155.0...165.0)
        XCTAssertTrue(CustomWorkout.supportsAlert(alertCpm, activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(3, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(2, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(1, .minutes), activity: .running, location: .outdoor))
        let hrZoneAlert = HeartRateZoneAlert(zone: 2)
        print("HR ZONE 2 SUPPORTS: \(CustomWorkout.supportsAlert(hrZoneAlert, activity: .running, location: .outdoor))")
    }
}

@MainActor
final class HealthKitManagerTests: XCTestCase {

    var mockStore: MockHealthStore!
    var sut: HealthKitManager!

    override func setUp() {
        super.setUp()
        mockStore = MockHealthStore()
    }

    override func tearDown() {
        mockStore = nil
        sut = nil
        super.tearDown()
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
        XCTAssertTrue(readTypes.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))

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

class MockHealthStore: HKHealthStoreProtocol {
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
        let cv = await engine.calculatePaceCV(bucketPaces: paces)
        XCTAssertEqual(cv, 0, accuracy: 0.001)
        
        let variablePaces = [200.0, 400.0]
        let cv2 = await engine.calculatePaceCV(bucketPaces: variablePaces)
        // mean = 300. variance = sum((x-300)^2) / 1 = 10000 + 10000 = 20000. sigma = sqrt(20000) ~ 141.42
        // CV = 141.42 / 300 = 0.471
        XCTAssertEqual(cv2, 0.471, accuracy: 0.01)
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
        
        // Instructional cues must interpolate computed target output, NOT the raw baseline
        let cue = template.generateInstructionalCue(computedTarget)
        XCTAssertTrue(cue.contains("158 SPM"), "Instructional cue should interpolate the computed target: \(cue)")
        XCTAssertFalse(cue.contains("151 SPM"), "Instructional cue must not repeat the raw baseline: \(cue)")
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

