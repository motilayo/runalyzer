import Foundation
import HealthKit

public protocol HKHealthStoreProtocol {
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

    var onWorkoutsUpdated: (() async -> Void)?

    private var observerQuery: HKObserverQuery?

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

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)

        // If we get here without throwing, auth request was completed (though user may have denied some)
        // We assume authorization is sufficient to at least try fetching.
        DispatchQueue.main.async {
            self.isAuthorized = true
        }

        try await enableBackgroundDelivery()
        startObservingWorkouts()
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
                Task {
                    await self?.onWorkoutsUpdated?()
                    completionHandler()
                }
            } else {
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    /// Fetch running workouts from the last 30 days
    func fetchRecentRunningWorkouts() async throws -> [HKWorkout] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return []
        }

        let typePredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: nil, options: .strictStartDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])

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

                let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                let minimumRunDistance = UserDefaults.standard.double(forKey: "minimumRunDistance")
                let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)

                let filteredWorkouts = workouts.filter { workout in
                    let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
                    // if minimumRunDistance is default 0 from UserDefaults (not saved), we will fallback to 1000
                    let limit = minimumRunDistance == 0 ? 1000.0 : minDistanceInMeters
                    return distance >= (limit - 0.01) // Small buffer
                }

                continuation.resume(returning: filteredWorkouts)
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

        // Framboise owns the bucketed HealthKit read, trimming, heuristics, and classification.
        let runMetrics = try await FramboiseEngine.fetchMetricsConcurrently(for: workout, healthStore: healthStore)

        let rawHR = runMetrics.heartRateBuckets.map(\.value)
        let rawCadence = runMetrics.cadenceBuckets.map(\.value)
        let trimmedHR = FramboiseEngine.trimOutliers(from: rawHR)
        let trimmedCadence = FramboiseEngine.trimOutliers(from: rawCadence)
        let trimmedPace = FramboiseEngine.trimOutliers(from: runMetrics.paceBuckets.map(\.value))

        // Raw values are calculated from the same bucketed source for the transparency toggle.
        let rawAvgPace = Self.calculatePace(duration: duration, distance: distance)
        let rawAvgHeartRate = rawHR.isEmpty ? 0 : Int(round(rawHR.reduce(0, +) / Double(rawHR.count)))
        let rawAvgCadence = rawCadence.isEmpty ? 0 : Int(round(rawCadence.reduce(0, +) / Double(rawCadence.count)))
        let workingAvgHeartRate = trimmedHR.isEmpty ? nil : Int(round(trimmedHR.reduce(0, +) / Double(trimmedHR.count)))
        let workingAvgCadence = trimmedCadence.isEmpty ? nil : Int(round(trimmedCadence.reduce(0, +) / Double(trimmedCadence.count)))
        let workingAvgPace = trimmedPace.isEmpty ? nil : trimmedPace.reduce(0, +) / Double(trimmedPace.count)

        let type = FramboiseEngine.classifyRun(paceBuckets: trimmedPace, heartRateBuckets: trimmedHR)
        let runTypeRaw: String = switch type {
        case .steady: "steady"
        case .intervals: "intervals"
        case .unknown: "unknown"
        }
        var tags: [String] = []
        if let paceTag = FramboiseEngine.checkPaceVariance(paceBuckets: trimmedPace) { tags.append(paceTag) }
        if let cadenceTag = FramboiseEngine.checkCadenceFading(cadenceBuckets: trimmedCadence) { tags.append(cadenceTag) }

        func average(_ buckets: [Bucket]) -> Double {
            guard !buckets.isEmpty else { return 0 }
            return buckets.map(\.value).reduce(0, +) / Double(buckets.count)
        }

        let record = RunRecord(
            id: workout.uuid,
            date: workout.startDate,
            distance: distance,
            duration: duration,
            avgPace: rawAvgPace,
            avgHeartRate: rawAvgHeartRate,
            avgCadence: rawAvgCadence,
            verticalOscillation: average(runMetrics.verticalOscillationBuckets),
            vo2Max: average(runMetrics.vo2MaxBuckets),
            groundContactTime: average(runMetrics.groundContactTimeBuckets),
            strideLength: average(runMetrics.strideLengthBuckets)
        )
        record.workingAvgPace = workingAvgPace
        record.workingAvgHeartRate = workingAvgHeartRate
        record.workingAvgCadence = workingAvgCadence
        record.runTypeRaw = runTypeRaw
        record.framboiseTags = tags

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
