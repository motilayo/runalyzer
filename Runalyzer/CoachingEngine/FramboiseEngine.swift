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

    public init(
        distanceBuckets: [Bucket] = [],
        heartRateBuckets: [Bucket] = [],
        cadenceBuckets: [Bucket] = [],
        paceBuckets: [Bucket] = [],
        verticalOscillationBuckets: [Bucket] = [],
        vo2MaxBuckets: [Bucket] = [],
        groundContactTimeBuckets: [Bucket] = [],
        strideLengthBuckets: [Bucket] = []
    ) {
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

public enum RunType: String, Equatable, CaseIterable, Sendable {
    case steady
    case tempo
    case progressive
    case intervals
    case urbanTraffic
    case unknown
}

/// A Sendable DTO representing the calculated features, working averages, and classification
/// extracted deterministically by the Framboise Engine.
public struct FramboiseTrimmedMetricsDTO: Sendable {
    public let rawAvgPace: Double          // sec/km
    public let rawAvgCadence: Double       // SPM
    public let rawAvgHeartRate: Double     // BPM

    public let workingAvgPace: Double      // sec/km
    public let workingAvgCadence: Double   // SPM
    public let workingAvgHeartRate: Double // BPM

    public let paceCV: Double              // Coefficient of variation (σ / μ)
    public let paceSlope: Double           // Linear regression slope
    public let percentZone4: Double        // 0.0 - 1.0
    public let durationMinutes: Double     // minutes

    public let hasUrbanTraffic: Bool
    public let framboiseTags: [String]
    public let detectedType: RunType

    public let verticalOscillation: Double
    public let vo2Max: Double
    public let groundContactTime: Double
    public let strideLength: Double

    public init(
        rawAvgPace: Double,
        rawAvgCadence: Double,
        rawAvgHeartRate: Double,
        workingAvgPace: Double,
        workingAvgCadence: Double,
        workingAvgHeartRate: Double,
        paceCV: Double,
        paceSlope: Double,
        percentZone4: Double,
        durationMinutes: Double,
        hasUrbanTraffic: Bool,
        framboiseTags: [String],
        detectedType: RunType,
        verticalOscillation: Double,
        vo2Max: Double,
        groundContactTime: Double,
        strideLength: Double
    ) {
        self.rawAvgPace = rawAvgPace
        self.rawAvgCadence = rawAvgCadence
        self.rawAvgHeartRate = rawAvgHeartRate
        self.workingAvgPace = workingAvgPace
        self.workingAvgCadence = workingAvgCadence
        self.workingAvgHeartRate = workingAvgHeartRate
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.durationMinutes = durationMinutes
        self.hasUrbanTraffic = hasUrbanTraffic
        self.framboiseTags = framboiseTags
        self.detectedType = detectedType
        self.verticalOscillation = verticalOscillation
        self.vo2Max = vo2Max
        self.groundContactTime = groundContactTime
        self.strideLength = strideLength
    }
}

/// Discrete 1-minute window
public struct MinuteBucket: Sendable {
    public let date: Date
    public let distanceMeters: Double
    public let meanPace: Double       // sec/km
    public let meanCadence: Double    // SPM
    public let meanHR: Double         // BPM
}

// MARK: - Framboise Engine

public class FramboiseEngine {

    public init() {}

    /// Primary pipeline method: queries HealthKit concurrently, buckets into 1-minute windows,
    /// filters dead stops, applies median trimming, and calculates statistical features.
    public static func extractTrimmedMetrics(for workout: HKWorkout, healthStore: HKHealthStoreProtocol) async throws -> FramboiseTrimmedMetricsDTO {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
        let durationMinutes = max(1.0, duration / 60.0)

        // 1. Concurrent Extraction
        let runMetrics = try await fetchMetricsConcurrently(for: workout, healthStore: healthStore)

        // 2. 1-Minute Discrete Bucketing
        let minuteBuckets = alignIntoMinuteBuckets(runMetrics: runMetrics, startDate: workout.startDate, endDate: workout.endDate)

        // 3. Dead Stop Filter (.urbanTraffic)
        // Evaluate buckets where distanceMeters == 0 or meanCadence == 0, but meanHR > 0.
        let deadStopBuckets = minuteBuckets.filter { bucket in
            (bucket.distanceMeters <= 0 || bucket.meanCadence <= 0) && bucket.meanHR > 0
        }
        let hasUrbanTraffic = !deadStopBuckets.isEmpty

        // Slice dead stops out before calculating true workingAverages
        let movingBuckets = minuteBuckets.filter { bucket in
            !((bucket.distanceMeters <= 0 || bucket.meanCadence <= 0) && bucket.meanHR > 0)
        }

        let rawPaces = minuteBuckets.map(\.meanPace).filter { $0 > 0 }
        let rawCadences = minuteBuckets.map(\.meanCadence).filter { $0 > 0 }
        let rawHRs = minuteBuckets.map(\.meanHR).filter { $0 > 0 }

        // 4. Median Trimming on pace array
        let candidatePaces = movingBuckets.map(\.meanPace).filter { $0 > 0 }
        let trimmedPaces = trimPaceOutliers(from: candidatePaces)

        // Working cadences and HRs
        let candidateCadences = movingBuckets.map(\.meanCadence).filter { $0 > 0 }
        let candidateHRs = movingBuckets.map(\.meanHR).filter { $0 > 0 }
        let trimmedCadences = trimOutliers(from: candidateCadences)
        let trimmedHRs = trimOutliers(from: candidateHRs)

        // 5. Statistical Calculations
        let validPaces = trimmedPaces.isEmpty ? candidatePaces : trimmedPaces
        let paceCount = Double(max(1, validPaces.count))

        // Mean Pace (μ)
        let paceMean = validPaces.reduce(0, +) / paceCount

        // Pace Standard Deviation (σ)
        let paceVariance = validPaces.reduce(0) { total, val in
            let diff = val - paceMean
            return total + (diff * diff)
        } / paceCount
        let paceStdDev = paceVariance.squareRoot()

        // Pace Coefficient of Variation (CV_pace = σ / μ)
        let paceCV = paceMean > 0 ? (paceStdDev / paceMean) : 0.0

        // Pace Slope: m = [n * Σ(xy) - (Σx)(Σy)] / [n * Σ(x^2) - (Σx)^2]
        let paceSlope = calculateSlope(values: validPaces)

        // Percent Zone 4: Fraction of moving buckets with heart rate >= 160 BPM
        let zone4Count = movingBuckets.filter { $0.meanHR >= 160.0 }.count
        let totalMoving = max(1, movingBuckets.count)
        let percentZone4 = Double(zone4Count) / Double(totalMoving)

        // Raw averages
        let calculatedRawPace = distance > 0 ? (duration / (distance / 1000.0)) : (rawPaces.isEmpty ? 0 : rawPaces.reduce(0, +) / Double(rawPaces.count))
        let rawAvgCadence = rawCadences.isEmpty ? 0.0 : rawCadences.reduce(0, +) / Double(rawCadences.count)
        let rawAvgHeartRate = rawHRs.isEmpty ? 0.0 : rawHRs.reduce(0, +) / Double(rawHRs.count)

        // Working averages
        let workingAvgPace = paceMean > 0 ? paceMean : calculatedRawPace
        let workingAvgCadence = trimmedCadences.isEmpty ? (rawAvgCadence > 0 ? rawAvgCadence : 0.0) : trimmedCadences.reduce(0, +) / Double(trimmedCadences.count)
        let workingAvgHeartRate = trimmedHRs.isEmpty ? (rawAvgHeartRate > 0 ? rawAvgHeartRate : 0.0) : trimmedHRs.reduce(0, +) / Double(trimmedHRs.count)

        // Heuristic tags
        var tags: [String] = []
        if hasUrbanTraffic {
            tags.append("Traffic stops trimmed")
        }
        if let paceTag = checkPaceVariance(paceBuckets: validPaces) { tags.append(paceTag) }
        if let cadenceTag = checkCadenceFading(cadenceBuckets: trimmedCadences.isEmpty ? candidateCadences : trimmedCadences) { tags.append(cadenceTag) }

        // Heuristic run classification based on trimmed working metrics
        let classifiedType = classifyRun(
            paceBuckets: validPaces,
            cadenceBuckets: trimmedCadences.isEmpty ? candidateCadences : trimmedCadences,
            heartRateBuckets: trimmedHRs.isEmpty ? candidateHRs : trimmedHRs,
            distanceBuckets: minuteBuckets.map(\.distanceMeters),
            rawPaceBuckets: rawPaces
        )

        func avgOfBuckets(_ buckets: [Bucket]) -> Double {
            let valid = buckets.map(\.value).filter { $0 > 0 }
            guard !valid.isEmpty else { return 0.0 }
            return valid.reduce(0, +) / Double(valid.count)
        }

        return FramboiseTrimmedMetricsDTO(
            rawAvgPace: calculatedRawPace,
            rawAvgCadence: rawAvgCadence,
            rawAvgHeartRate: rawAvgHeartRate,
            workingAvgPace: workingAvgPace,
            workingAvgCadence: workingAvgCadence,
            workingAvgHeartRate: workingAvgHeartRate,
            paceCV: paceCV,
            paceSlope: paceSlope,
            percentZone4: percentZone4,
            durationMinutes: durationMinutes,
            hasUrbanTraffic: hasUrbanTraffic,
            framboiseTags: tags,
            detectedType: classifiedType,
            verticalOscillation: avgOfBuckets(runMetrics.verticalOscillationBuckets),
            vo2Max: avgOfBuckets(runMetrics.vo2MaxBuckets),
            groundContactTime: avgOfBuckets(runMetrics.groundContactTimeBuckets),
            strideLength: avgOfBuckets(runMetrics.strideLengthBuckets)
        )
    }

    /// Aligns discrete HealthKit statistic buckets into 1-minute windows
    public static func alignIntoMinuteBuckets(runMetrics: RunMetrics, startDate: Date, endDate: Date) -> [MinuteBucket] {
        var minuteBuckets: [MinuteBucket] = []
        let calendar = Calendar.current
        var currentWindowStart = startDate

        let distances = runMetrics.distanceBuckets.sorted { $0.date < $1.date }
        let paces = runMetrics.paceBuckets.sorted { $0.date < $1.date }
        let cadences = runMetrics.cadenceBuckets.sorted { $0.date < $1.date }
        let hrs = runMetrics.heartRateBuckets.sorted { $0.date < $1.date }

        while currentWindowStart < endDate {
            guard let nextWindow = calendar.date(byAdding: .minute, value: 1, to: currentWindowStart) else { break }

            let dVal = distances.first(where: { $0.date >= currentWindowStart && $0.date < nextWindow })?.value ?? 0.0
            let pVal = paces.first(where: { $0.date >= currentWindowStart && $0.date < nextWindow })?.value ?? 0.0
            let cVal = cadences.first(where: { $0.date >= currentWindowStart && $0.date < nextWindow })?.value ?? 0.0
            let hVal = hrs.first(where: { $0.date >= currentWindowStart && $0.date < nextWindow })?.value ?? 0.0

            minuteBuckets.append(MinuteBucket(
                date: currentWindowStart,
                distanceMeters: dVal,
                meanPace: pVal,
                meanCadence: cVal,
                meanHR: hVal
            ))

            currentWindowStart = nextWindow
        }

        return minuteBuckets
    }

    /// Calculates linear regression slope: m = [n * Σ(xy) - (Σx)(Σy)] / [n * Σ(x^2) - (Σx)^2]
    public static func calculateSlope(values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0.0 }

        var sumX: Double = 0.0
        var sumY: Double = 0.0
        var sumXY: Double = 0.0
        var sumX2: Double = 0.0

        for (index, y) in values.enumerated() {
            let x = Double(index)
            sumX += x
            sumY += y
            sumXY += (x * y)
            sumX2 += (x * x)
        }

        let denominator = (n * sumX2) - (sumX * sumX)
        guard abs(denominator) > 1e-9 else { return 0.0 }

        let numerator = (n * sumXY) - (sumX * sumY)
        return numerator / denominator
    }

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
                        query.initialResultsHandler = { _, results, error in
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

                                if identifier == .runningSpeed {
                                    // speed is m/s. pace in sec/km = 1000 / speed
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

    /// Helper to test time-based bucketing mathematically
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

        while left <= right && data[left] < threshold {
            left += 1
        }

        while right >= left && data[right] < threshold {
            right -= 1
        }

        if left > right { return [] }

        var trimmed = Array(data[left...right])
        trimmed.removeAll { $0 < threshold }
        return trimmed
    }

    /// Trims pace buckets expressed as seconds per kilometer.
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
        let values = paceBuckets.filter { $0 > 0 }
        let cadenceValues = cadenceBuckets.filter { $0 > 0 }
        let heartRateValues = heartRateBuckets.filter { $0 > 0 }
        guard values.count >= 3, cadenceValues.count >= 3 else { return .steady }

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

        let averageHeartRate = heartRateValues.isEmpty ? 0 : heartRateValues.reduce(0, +) / Double(heartRateValues.count)
        if averageHeartRate >= 160 && paceStdDev <= 25 {
            return .tempo
        }

        return .steady
    }
}
