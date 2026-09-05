import Foundation
import HealthKit

// MARK: - Models

public struct RunMetrics {
    public var heartRateBuckets: [Bucket] = []
    public var cadenceBuckets: [Bucket] = []
    public var paceBuckets: [Bucket] = []

    public init(heartRateBuckets: [Bucket] = [], cadenceBuckets: [Bucket] = [], paceBuckets: [Bucket] = []) {
        self.heartRateBuckets = heartRateBuckets
        self.cadenceBuckets = cadenceBuckets
        self.paceBuckets = paceBuckets
    }

}

public struct Bucket: Equatable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }

}

public enum RunType: Equatable {
    case steady
    case intervals
    case unknown
}

// MARK: - Framboise Engine

public class FramboiseEngine {

    public init() {}


    /// Concurrent Time-Based Bucketing
    public static func fetchMetricsConcurrently(for workout: HKWorkout, healthStore: HKHealthStoreProtocol) async throws -> RunMetrics {

        let types: [(HKQuantityTypeIdentifier, HKStatisticsOptions, HKUnit)] = [
            (.heartRate, .discreteAverage, HKUnit.count().unitDivided(by: .minute())),
            (.stepCount, .cumulativeSum, HKUnit.count()), // for cadence
            (.runningSpeed, .discreteAverage, HKUnit.meter().unitDivided(by: .second())) // for pace
        ]

        return try await withThrowingTaskGroup(of: (HKQuantityTypeIdentifier, [Bucket]).self) { group in

            for (identifier, options, unit) in types {
                group.addTask {
                    guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
                        return (identifier, [])
                    }

                    let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

                    var interval = DateComponents()
                    interval.minute = 1

                    let query = HKStatisticsCollectionQuery(
                        quantityType: quantityType,
                        quantitySamplePredicate: predicate,
                        options: options,
                        anchorDate: workout.startDate,
                        intervalComponents: interval
                    )

                    return try await withCheckedThrowingContinuation { continuation in
                        query.initialResultsHandler = { query, results, error in
                            // Handle partial HealthKit permission rejections without crashing the entire extraction
                            if let _ = error {
                                continuation.resume(returning: (identifier, []))
                                return
                            }

                            guard let statsCollection = results else {
                                continuation.resume(returning: (identifier, []))
                                return
                            }

                            var buckets: [Bucket] = []
                            statsCollection.enumerateStatistics(from: workout.startDate, to: workout.endDate) { statistics, _ in
                                let date = statistics.startDate
                                var value: Double = 0.0

                                if options.contains(.discreteAverage), let quantity = statistics.averageQuantity() {
                                    value = quantity.doubleValue(for: unit)
                                } else if options.contains(.cumulativeSum), let quantity = statistics.sumQuantity() {
                                    value = quantity.doubleValue(for: unit)
                                }

                                // Specific transformation for metrics
                                if identifier == .runningSpeed {
                                    // speed is m/s. pace is min/km
                                    // 1 / (speed in m/s) = s/m
                                    // pace in sec/km = 1000 / speed
                                    if value > 0 {
                                        value = 1000.0 / value
                                    }
                                }

                                buckets.append(Bucket(date: date, value: value))
                            }
                            continuation.resume(returning: (identifier, buckets))
                        }
                        healthStore.execute(query)
                    }
                }
            }

            var result = RunMetrics()

            for try await (identifier, buckets) in group {
                // sort by date to maintain chronological order as tasks complete out of order
                let sortedBuckets = buckets.sorted { $0.date < $1.date }

                if identifier == .heartRate {
                    result.heartRateBuckets = sortedBuckets
                } else if identifier == .stepCount {
                    result.cadenceBuckets = sortedBuckets
                } else if identifier == .runningSpeed {
                    result.paceBuckets = sortedBuckets
                }
            }

            return result
        }
    }

    /// Helper to test time-based bucketing mathematically (since HKStatisticsCollection is unmockable)
    public static func generateTimeBuckets(for workout: HKWorkout) -> [Date] {
        var dates: [Date] = []
        var current = workout.startDate
        let calendar = Calendar.current
        while current < workout.endDate {
            dates.append(current)
            current = calendar.date(byAdding: .minute, value: 1, to: current) ?? current
        }
        return dates
    }

    /// Outlier Trimming
    public static func trimOutliers(from data: [Double]) -> [Double] {
        guard data.count > 2 else { return data }

        let sorted = data.sorted()
        let median = sorted[sorted.count / 2]
        let threshold = median * 0.7

        var left = 0
        var right = data.count - 1

        // Strip warm-ups
        while left <= right && data[left] < threshold {
            left += 1
        }

        // Strip cool-downs
        while right >= left && data[right] < threshold {
            right -= 1
        }

        if left > right { return [] }

        var trimmed = Array(data[left...right])

        // Strip dead stops (e.g. traffic lights)
        trimmed.removeAll { $0 < threshold }

        return trimmed
    }

    /// Framboise Heuristics Engine: Pace Variance
    public static func checkPaceVariance(paceBuckets: [Double]) -> String? {
        guard !paceBuckets.isEmpty else { return nil }

        let mean = paceBuckets.reduce(0, +) / Double(paceBuckets.count)
        let sumOfSquaredDifferences = paceBuckets.reduce(0) { total, value in
            let diff = value - mean
            return total + (diff * diff)
        }
        let variance = sumOfSquaredDifferences / Double(paceBuckets.count)
        let stdDev = variance.squareRoot()

        if stdDev <= 5 {
            return "Maintained steady pace"
        }

        return nil
    }

    /// Framboise Heuristics Engine: Cadence Fading
    public static func checkCadenceFading(cadenceBuckets: [Double]) -> String? {
        guard cadenceBuckets.count >= 5 else { return nil }

        let twentyPercentCount = max(1, cadenceBuckets.count / 5)

        let first20Percent = Array(cadenceBuckets.prefix(twentyPercentCount))
        let last20Percent = Array(cadenceBuckets.suffix(twentyPercentCount))

        let avgFirst = first20Percent.reduce(0, +) / Double(first20Percent.count)
        let avgLast = last20Percent.reduce(0, +) / Double(last20Percent.count)

        let delta = avgLast - avgFirst

        if delta <= -4 {
            return "Cadence declined at peak"
        }

        return nil
    }

    /// Classification Engine
    public static func classifyRun(paceBuckets: [Double], heartRateBuckets: [Double]) -> RunType {
        guard !paceBuckets.isEmpty else { return .unknown }

        let mean = paceBuckets.reduce(0, +) / Double(paceBuckets.count)
        let sumOfSquaredDifferences = paceBuckets.reduce(0) { total, value in
            let diff = value - mean
            return total + (diff * diff)
        }
        let variance = sumOfSquaredDifferences / Double(paceBuckets.count)
        let stdDev = variance.squareRoot()

        // Check peaks and valleys
        var crossings = 0
        let margin = stdDev * 0.5
        var isAbove = paceBuckets[0] > mean
        for pace in paceBuckets {
            if isAbove && pace < mean - margin {
                crossings += 1
                isAbove = false
            } else if !isAbove && pace > mean + margin {
                crossings += 1
                isAbove = true
            }
        }

        // High variance and repeating peaks/valleys -> intervals
        if stdDev > 10 && crossings >= 2 {
            return .intervals
        }

        // Low variance -> steady
        if stdDev <= 5 {
            return .steady
        }

        return .unknown
    }
}
