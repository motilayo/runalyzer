import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    // Published so views can react to permission changes if needed
    @Published var isAuthorized: Bool = false

    var onWorkoutsUpdated: (() async -> Void)?

    private var observerQuery: HKObserverQuery?

    private init() {}

    /// Request read access for required running data
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!, // Used for cadence calculation
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!
        ]

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)

        // Update authorization status based on workout type, as read permissions are opaque in HealthKit
        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        self.isAuthorized = (workoutStatus == .sharingAuthorized) || (workoutStatus == .notDetermined)
        // Note: we can't accurately check READ permission status. Assuming authorized if no error thrown.
        self.isAuthorized = true

        try await enableBackgroundDelivery()
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

    /// Extract data from a workout to create a RunRecord
    func extractRunRecord(from workout: HKWorkout) async throws -> RunRecord {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0

        // Pace (minutes per km)
        let avgPace = Self.calculatePace(duration: duration, distance: distance)

        // Query average heart rate
        let avgHeartRate = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )

        // Calculate average cadence from step count
        let totalSteps = try await fetchSumQuantity(
            for: workout,
            quantityTypeIdentifier: .stepCount,
            unit: HKUnit.count()
        )

        let avgCadence = Self.calculateCadence(duration: duration, steps: totalSteps)

        // Query average vertical oscillation (in cm)
        let verticalOscillation = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .runningVerticalOscillation,
            unit: HKUnit.meterUnit(with: .centi)
        )

        return RunRecord(
            id: workout.uuid,
            date: workout.startDate,
            distance: distance,
            duration: duration,
            avgPace: avgPace,
            avgHeartRate: Int(avgHeartRate),
            avgCadence: avgCadence,
            verticalOscillation: verticalOscillation
        )
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

    // MARK: - Private Helpers

    private func fetchAverageQuantity(
        for workout: HKWorkout,
        quantityTypeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier) else {
            return 0.0
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error = error {
                    print("HKStatisticsQuery warning for \(quantityTypeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }

                guard let averageQuantity = result?.averageQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }

                continuation.resume(returning: averageQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchSumQuantity(
        for workout: HKWorkout,
        quantityTypeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier) else {
            return 0.0
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                // HealthKit throws "No data available for the specified predicate" if the sample type wasn't tracked for the workout.
                // We shouldn't fail the entire workout sync; we should just return 0.0.
                if let error = error {
                    print("HKStatisticsQuery warning for \(quantityTypeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }

                guard let sumQuantity = result?.sumQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }

                continuation.resume(returning: sumQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
