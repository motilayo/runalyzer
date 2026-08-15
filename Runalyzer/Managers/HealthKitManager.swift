import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    // Published so views can react to permission changes if needed
    @Published var isAuthorized: Bool = false

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
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)

        // Update authorization status based on workout type, as read permissions are opaque in HealthKit
        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        self.isAuthorized = (workoutStatus == .sharingAuthorized) || (workoutStatus == .notDetermined)
        // Note: we can't accurately check READ permission status. Assuming authorized if no error thrown.
        self.isAuthorized = true
    }

    /// Fetch the last 5 running workouts
    func fetchLastFiveRunningWorkouts() async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 5,
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

                continuation.resume(returning: workouts)
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

        return RunRecord(
            id: workout.uuid,
            date: workout.startDate,
            distance: distance,
            duration: duration,
            avgPace: avgPace,
            avgHeartRate: Int(avgHeartRate),
            avgCadence: avgCadence
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
                    continuation.resume(throwing: error)
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
                if let error = error {
                    continuation.resume(throwing: error)
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
