import Foundation
import HealthKit

public protocol HKHealthStoreProtocol: AnyObject, Sendable {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws
    func execute(_ query: HKQuery)
}

extension HKHealthStore: HKHealthStoreProtocol {}


/// A singleton manager responsible for all interactions with Apple HealthKit.
///
/// `HealthKitManager` requests permissions, configures background delivery, and fetches recent running workouts.
/// It also queries discrete and cumulative statistics (like VO2 Max, Cadence, and Vertical Oscillation) and maps them
/// into the app's native `RunRecord` model for processing and AI analysis.
@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let healthStore: HKHealthStoreProtocol
    var isHealthDataAvailable: () -> Bool

    // Published so views can react to permission changes if needed
    @Published var isAuthorized: Bool = false

    var onWorkoutsUpdated: (@Sendable () async -> Void)?

    private var observerQuery: HKObserverQuery?
    private var authorizationTask: Task<Void, Error>?

    init(
        healthStore: HKHealthStoreProtocol = HKHealthStore(),
        isHealthDataAvailable: @escaping () -> Bool = { HKHealthStore.isHealthDataAvailable() }
    ) {
        self.healthStore = healthStore
        self.isHealthDataAvailable = isHealthDataAvailable
        checkAuthorizationStatus()
    }

    /// Checks if we already have authorization
    func checkAuthorizationStatus() {
        guard isHealthDataAvailable() else { return }

        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)

        // HealthKit doesn't explicitly tell us if read access is granted,
        // but if we are sharingAuthorized, we assume we have full access.
        if status == .sharingAuthorized {
            self.isAuthorized = true
        }
    }

    /// Request read access for required running data
    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!, // Used for cadence calculation
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: .runningStrideLength)!
        ]

        // We do not need to share/write any data for Runalyzer currently
        let typesToShare: Set<HKSampleType> = []

        try await requestAuthorization(toShare: typesToShare, read: typesToRead)

        // If we get here without throwing, auth request was completed (though user may have denied some)
        // We assume authorization is sufficient to at least try fetching.
        DispatchQueue.main.async {
            self.isAuthorized = true
        }

        try await enableBackgroundDelivery()
        startObservingWorkouts()
    }

    func requestWriteAuthorization(toShare typesToShare: Set<HKSampleType>) async throws {
        try await requestAuthorization(toShare: typesToShare, read: [])
    }

    private func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        if let authorizationTask {
            try await authorizationTask.value
            return
        }

        let task = Task { [healthStore] in
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        }
        authorizationTask = task
        defer { authorizationTask = nil }
        try await task.value
    }

    /// Enable background delivery for workouts
    func enableBackgroundDelivery() async throws {
        try await healthStore.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    /// Start observing workouts
    func startObservingWorkouts() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                completionHandler()
                Task { @MainActor in
                    await self?.onWorkoutsUpdated?()
                }
            } else {
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    /// Fetch running workouts from HealthKit.
    /// If startDate is provided, fetches workouts from that date onwards. Otherwise fetches all running workouts.
    func fetchRecentRunningWorkouts(startDate: Date? = nil) async throws -> [HKWorkout] {
        let typePredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate: NSPredicate
        if let startDate = startDate {
            let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])
        } else {
            predicate = typePredicate
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                // Ingest all valid running workouts with distance > 0 into SwiftData.
                // Distance filtering (minimumRunDistance slider) is applied dynamically in presentation views (DashboardView)
                // so that shorter runs are preserved in SwiftData for baseline metrics and unfiltered queries.
                let validWorkouts = workouts.filter { workout in
                    let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
                    return distance > 0
                }

                continuation.resume(returning: validWorkouts)
            }
            healthStore.execute(query)
        }
    }

    /// Fetches the single most recent global VO2 Max reading from HealthKit
    func fetchLatestGlobalVO2Max() async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }

        // No predicate, just get the absolute latest globally
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let vo2 = sample.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }

    /// Extract data from a workout to create a RunRecord
    func extractRunRecord(from workout: HKWorkout) async throws -> RunRecord {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0

        // Framboise owns the bucketed HealthKit read, trimming, heuristics, and mathematical feature extraction.
        let trimmedMetrics = try await FramboiseEngine.extractTrimmedMetrics(for: workout, healthStore: healthStore)

        // CoreML Classification against writable model
        let features = RunFeatures(
            averagePace: trimmedMetrics.workingAvgPace,
            paceCV: trimmedMetrics.paceCV,
            paceSlope: trimmedMetrics.paceSlope,
            percentZone4: trimmedMetrics.percentZone4,
            durationMinutes: trimmedMetrics.durationMinutes
        )

        let modelPrediction = ModelManager.shared.classify(features: features)
        let predictedTypeRaw: String
        if modelPrediction != "unknown" && !modelPrediction.isEmpty && modelPrediction != "urbanTraffic" {
            predictedTypeRaw = modelPrediction
        } else if trimmedMetrics.detectedType != .unknown && trimmedMetrics.detectedType != .urbanTraffic {
            predictedTypeRaw = trimmedMetrics.detectedType.rawValue
        } else {
            predictedTypeRaw = "steady"
        }

        let record = RunRecord(
            id: workout.uuid,
            hkWorkoutID: workout.uuid,
            date: workout.startDate,
            duration: duration,
            totalDistanceMeters: distance,
            rawAvgPace: trimmedMetrics.rawAvgPace,
            rawAvgCadence: trimmedMetrics.rawAvgCadence,
            rawAvgHeartRate: trimmedMetrics.rawAvgHeartRate,
            workingAvgPace: trimmedMetrics.workingAvgPace,
            workingAvgCadence: trimmedMetrics.workingAvgCadence,
            workingAvgHeartRate: trimmedMetrics.workingAvgHeartRate,
            paceCV: trimmedMetrics.paceCV,
            paceSlope: trimmedMetrics.paceSlope,
            percentZone4: trimmedMetrics.percentZone4,
            detectedTypeRaw: predictedTypeRaw,
            framboiseTags: trimmedMetrics.framboiseTags,
            verticalOscillation: trimmedMetrics.verticalOscillation,
            vo2Max: trimmedMetrics.vo2Max,
            groundContactTime: trimmedMetrics.groundContactTime,
            strideLength: trimmedMetrics.strideLength
        )

        return record
    }

    // MARK: - Calculation Helpers

    static func calculatePace(duration: TimeInterval, distance: Double) -> Double {
        if distance > 0 && duration > 0 {
            // (duration in seconds / 60) / (distance in meters / 1000)
            return (duration / 60.0) / (distance / 1000.0)
        }
        return 0.0
    }

    static func calculateCadence(duration: TimeInterval, steps: Double) -> Int {
        if duration > 0 {
            // Steps per minute
            return Int(steps / (duration / 60.0))
        }
        return 0
    }

}
