import XCTest
import HealthKit

import Foundation
@testable import Runalyzer

final class RunalyzerTests: XCTestCase {

    @MainActor
    func testPaceCalculation() throws {
        // Distance: 5 km (5000 meters)
        // Duration: 25 minutes (1500 seconds)
        // Pace should be 5.00 min/km

        let duration: TimeInterval = 1500
        let distance: Double = 5000

        let pace = HealthKitManager.calculatePace(duration: duration, distance: distance)
        XCTAssertEqual(pace, 5.0, accuracy: 0.01)
    }

    @MainActor
    func testCadenceCalculation() throws {
        // Duration: 25 minutes (1500 seconds)
        // Steps: 4000
        // Cadence should be 160 SPM

        let duration: TimeInterval = 1500
        let steps: Double = 4000

        let cadence = HealthKitManager.calculateCadence(duration: duration, steps: steps)
        XCTAssertEqual(cadence, 160)
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
        mockStore.authorizationStatusCalled = false
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

final class MockHealthStore: HKHealthStoreProtocol, @unchecked Sendable {
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

    func testTimeBasedBucketing() {
        let start = Date()
        let end = start.addingTimeInterval(45 * 60) // 45 mins
        let workout = HKWorkout(activityType: .running, start: start, end: end, duration: end.timeIntervalSince(start), totalEnergyBurned: nil, totalDistance: nil, device: nil, metadata: nil)

        let buckets = FramboiseEngine.generateTimeBuckets(for: workout)
        XCTAssertEqual(buckets.count, 45, "A 45-minute HKWorkout should yield exactly 45 buckets")
    }

    func testOutlierTrimmer_RemovesDeadStops() {
        let input: [Double] = [150, 152, 0, 80, 155, 154]
        let trimmed = FramboiseEngine.trimOutliers(from: input)
        XCTAssertEqual(trimmed, [150, 152, 155, 154])
    }

    func testPaceOutlierTrimmerKeepsFasterPaceAndRemovesStops() {
        let input: [Double] = [407, 410, 0, 900, 408, 405]
        let trimmed = FramboiseEngine.trimPaceOutliers(from: input)
        XCTAssertEqual(trimmed, [407, 410, 408, 405])
    }

    func testVarianceCheck_SteadyPace() {
        let paceBuckets: [Double] = [300, 302, 298, 305, 301, 299]
        let result = FramboiseEngine.checkPaceVariance(paceBuckets: paceBuckets)
        XCTAssertEqual(result, "Maintained steady pace")
    }

    func testDeltaCheck_FadedCadence() {
        let cadenceBuckets: [Double] = [165, 163, 160, 159, 158]
        let result = FramboiseEngine.checkCadenceFading(cadenceBuckets: cadenceBuckets)
        XCTAssertEqual(result, "Cadence declined at peak")
    }

    func testClassificationEngine_Intervals() {
        let paceBuckets: [Double] = [300, 350, 250, 350, 250, 300]
        let cadenceBuckets: [Double] = [175, 145, 176, 144, 175, 145]
        let type = FramboiseEngine.classifyRun(paceBuckets: paceBuckets, cadenceBuckets: cadenceBuckets, heartRateBuckets: [])
        XCTAssertEqual(type, .intervals)
    }

    func testClassificationEngine_Tempo() {
        let paceBuckets: [Double] = [300, 306, 294, 308, 292, 301]
        let cadenceBuckets: [Double] = [172, 174, 173, 175, 172, 174]
        let heartRateBuckets: [Double] = [170, 172, 171, 173, 172, 171]
        let type = FramboiseEngine.classifyRun(paceBuckets: paceBuckets, cadenceBuckets: cadenceBuckets, heartRateBuckets: heartRateBuckets)
        XCTAssertEqual(type, .tempo)
    }

    func testClassificationEngine_Progressive() {
        let paceBuckets: [Double] = [330, 326, 322, 318, 314, 310, 306, 302, 298]
        let cadenceBuckets: [Double] = [155, 157, 159, 161, 163, 165, 167, 169, 171]
        let type = FramboiseEngine.classifyRun(paceBuckets: paceBuckets, cadenceBuckets: cadenceBuckets, heartRateBuckets: [])
        XCTAssertEqual(type, .progressive)
    }

    func testClassificationEngine_UrbanTraffic() {
        let paceBuckets: [Double] = [300, 0, 302, 0, 298, 301]
        let type = FramboiseEngine.classifyRun(
            paceBuckets: [300, 302, 298, 301],
            cadenceBuckets: [165, 165, 165, 165],
            heartRateBuckets: [150, 150, 150, 150],
            distanceBuckets: [180, 0, 175, 180],
            rawPaceBuckets: paceBuckets
        )
        XCTAssertEqual(type, .steady)
    }

    func testPaceFormatterConvertsDecimalMinutesToTotalSeconds() {
        let originalValue = UserDefaults.standard.object(forKey: "useMetricSystem")
        defer {
            if let originalValue {
                UserDefaults.standard.set(originalValue, forKey: "useMetricSystem")
            } else {
                UserDefaults.standard.removeObject(forKey: "useMetricSystem")
            }
        }

        UserDefaults.standard.set(true, forKey: "useMetricSystem")
        XCTAssertEqual((6.9166667).formattedPaceString, "6:55/km")
    }

    func testConcurrentBucketing_Aggregation() async throws {
        let mockStore = MockHealthStoreForBucketing()
        let start = Date()
        let end = start.addingTimeInterval(5 * 60)
        let workout = HKWorkout(activityType: .running, start: start, end: end, duration: end.timeIntervalSince(start), totalEnergyBurned: nil, totalDistance: nil, device: nil, metadata: nil)

        let metrics = try await FramboiseEngine.fetchMetricsConcurrently(for: workout, healthStore: mockStore)

        // Expected empty lists since mock returns errors, but confirms concurrent execution without crash
        XCTAssertTrue(metrics.heartRateBuckets.isEmpty)
        XCTAssertTrue(metrics.cadenceBuckets.isEmpty)
        XCTAssertTrue(metrics.paceBuckets.isEmpty)
    }
}

final class MockHealthStoreForBucketing: HKHealthStoreProtocol, @unchecked Sendable {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {}
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { return .notDetermined }
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws {}

    func execute(_ query: HKQuery) {
        if let collectionQuery = query as? HKStatisticsCollectionQuery {
            if let handler = collectionQuery.initialResultsHandler {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double.random(in: 0.1...0.3)) {
                    let error = NSError(domain: "MockError", code: 1, userInfo: nil)
                    handler(collectionQuery, nil, error)
                }
            }
        }
    }
}
