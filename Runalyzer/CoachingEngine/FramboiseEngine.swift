import Foundation
import HealthKit

// MARK: - Models

public struct RunMetrics: Sendable {
    public var distanceBuckets: [Bucket] = []
    public var heartRateBuckets: [Bucket] = []
    public var cadenceBuckets: [Bucket] = []
    public var paceBuckets: [Bucket] = []
    public var verticalOscillationBuckets: [Bucket] = []
    public var vo2MaxBuckets: [Bucket] = []
    public var groundContactTimeBuckets: [Bucket] = []
    public var strideLengthBuckets: [Bucket] = []

    public init(distanceBuckets: [Bucket] = [], heartRateBuckets: [Bucket] = [], cadenceBuckets: [Bucket] = [], paceBuckets: [Bucket] = [], verticalOscillationBuckets: [Bucket] = [], vo2MaxBuckets: [Bucket] = [], groundContactTimeBuckets: [Bucket] = [], strideLengthBuckets: [Bucket] = []) {
        self.distanceBuckets = distanceBuckets
        self.heartRateBuckets = heartRateBuckets
        self.cadenceBuckets = cadenceBuckets
        self.paceBuckets = paceBuckets
        self.verticalOscillationBuckets = verticalOscillationBuckets
        self.vo2MaxBuckets = vo2MaxBuckets
        self.groundContactTimeBuckets = groundContactTimeBuckets
        self.strideLengthBuckets = strideLengthBuckets
    }

}

public struct Bucket: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }

}

public enum RunType: Equatable {
    case steady
    case tempo
    case progressive
    case intervals
    case urbanTraffic
    case unknown
}

// MARK: - Framboise Engine

public class FramboiseEngine {

    public init() {}


    /// Concurrent Time-Based Bucketing
    public static func fetchMetricsConcurrently(for workout: HKWorkout, healthStore: HKHealthStoreProtocol) async throws -> RunMetrics {

        let types: [(HKQuantityTypeIdentifier, HKStatisticsOptions, HKUnit)] = [
            (.distanceWalkingRunning, .cumulativeSum, HKUnit.meter()),
            (.heartRate, .discreteAverage, HKUnit.count().unitDivided(by: .minute())),
            (.stepCount, .cumulativeSum, HKUnit.count()), // for cadence
            (.runningSpeed, .discreteAverage, HKUnit.meter().unitDivided(by: .second())), // for pace
            (.runningVerticalOscillation, .discreteAverage, HKUnit.meterUnit(with: .centi)),
            (.vo2Max, .discreteAverage, HKUnit(from: "ml/kg*min")),
            (.runningGroundContactTime, .discreteAverage, HKUnit.secondUnit(with: .milli)),
            (.runningStrideLength, .discreteAverage, HKUnit.meter())
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

                if identifier == .distanceWalkingRunning {
                    result.distanceBuckets = sortedBuckets
                } else if identifier == .heartRate {
                    result.heartRateBuckets = sortedBuckets
                } else if identifier == .stepCount {
                    result.cadenceBuckets = sortedBuckets
                } else if identifier == .runningSpeed {
                    result.paceBuckets = sortedBuckets
                } else if identifier == .runningVerticalOscillation {
                    result.verticalOscillationBuckets = sortedBuckets
                } else if identifier == .vo2Max {
                    result.vo2MaxBuckets = sortedBuckets
                } else if identifier == .runningGroundContactTime {
                    result.groundContactTimeBuckets = sortedBuckets
                } else if identifier == .runningStrideLength {
                    result.strideLengthBuckets = sortedBuckets
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

    /// Trims pace buckets expressed as seconds per kilometer. Pace has inverse
    /// directionality to cadence and heart rate: a stop is zero or very slow,
    /// while a lower positive value is a faster effort and must be retained.
    public static func trimPaceOutliers(from data: [Double]) -> [Double] {
        let validData = data.filter { $0 > 0 }
        guard validData.count > 2 else { return validData }

        let sorted = validData.sorted()
        let median = sorted[sorted.count / 2]
        let threshold = median * 1.3

        var left = 0
        var right = data.count - 1
        while left <= right && (data[left] <= 0 || data[left] > threshold) {
            left += 1
        }
        while right >= left && (data[right] <= 0 || data[right] > threshold) {
            right -= 1
        }

        guard left <= right else { return [] }
        return data[left...right].filter { $0 > 0 && $0 <= threshold }
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
    public static func classifyRun(
        paceBuckets: [Double],
        cadenceBuckets: [Double],
        heartRateBuckets: [Double],
        distanceBuckets: [Double] = [],
        rawPaceBuckets: [Double] = []
    ) -> RunType {
        guard !paceBuckets.isEmpty else { return .unknown }

        let trafficStopCount = zip(distanceBuckets, zip(cadenceBuckets, heartRateBuckets)).filter { distance, metrics in
            distance <= 0 || (metrics.0 <= 0 && metrics.1 > 0)
        }.count
        if distanceBuckets.count >= 5 && trafficStopCount > 0 {
            return .urbanTraffic
        }

        let values = paceBuckets.filter { $0 > 0 }
        let cadenceValues = cadenceBuckets.filter { $0 > 0 }
        let heartRateValues = heartRateBuckets.filter { $0 > 0 }
        guard values.count >= 3, cadenceValues.count >= 3 else { return .unknown }

        func standardDeviation(_ values: [Double]) -> Double {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { total, value in
                let difference = value - mean
                return total + difference * difference
            } / Double(values.count)
            return variance.squareRoot()
        }

        let paceMean = values.reduce(0, +) / Double(values.count)
        let paceStdDev = standardDeviation(values)
        let cadenceMean = cadenceValues.reduce(0, +) / Double(cadenceValues.count)
        let cadenceStdDev = standardDeviation(cadenceValues)

        // A progressive run has a sustained one-direction pace trend, not repeated peaks.
        let midpoint = Double(values.count - 1) / 2.0
        let denominator = values.reduce(0) { total, _ in total + pow(midpoint, 2) }
        let slope = denominator == 0 ? 0 : values.enumerated().reduce(0) { total, item in
            total + (Double(item.offset) - midpoint) * (item.element - paceMean)
        } / denominator
        let explainedVariance = paceStdDev == 0 ? 0 : values.enumerated().reduce(0) { total, item in
            let predicted = paceMean + slope * (Double(item.offset) - midpoint)
            return total + pow(item.element - predicted, 2)
        }
        let trendFit = paceStdDev == 0 ? 0 : 1 - (explainedVariance / Double(values.count)) / pow(paceStdDev, 2)

        if slope < -1.5 && trendFit >= 0.55 && (values.max()! - values.min()!) >= 12 {
            return .progressive
        }

        // Intervals require repeated, prominent alternation around the mean.
        var crossings = 0
        let margin = max(8, cadenceStdDev * 0.75)
        var phase = 0
        for cadence in cadenceValues {
            if phase == 0 && cadence > cadenceMean + margin {
                phase = 1
            } else if phase == 0 && cadence < cadenceMean - margin {
                phase = -1
            } else if phase == 1 && cadence < cadenceMean - margin {
                crossings += 1
                phase = -1
            } else if phase == -1 && cadence > cadenceMean + margin {
                crossings += 1
                phase = 1
            }
        }

        if cadenceStdDev > 8 && paceStdDev > 15 && crossings >= 3 {
            return .intervals
        }

        // A steady, high-effort run is tempo; progressive runs were handled above.
        let averageHeartRate = heartRateValues.isEmpty ? 0 : heartRateValues.reduce(0, +) / Double(heartRateValues.count)
        if cadenceStdDev <= 3 && paceStdDev <= 15 && averageHeartRate >= 162 {
            return .tempo
        }

        if cadenceStdDev <= 3 && paceStdDev <= 15 {
            return .steady
        }

        return .unknown
    }
}
