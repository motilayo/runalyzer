import Foundation
import HealthKit

/// Represents a single 60-second slice of a run for analysis.
struct BucketData: Sendable {
    let startTime: Date
    let distanceMeters: Double
    let meanPaceSecPerKm: Double
    let meanCadence: Double
    let meanHR: Double
    let meanVerticalOscillation: Double

    init(
        startTime: Date,
        distanceMeters: Double,
        meanPaceSecPerKm: Double,
        meanCadence: Double,
        meanHR: Double,
        meanVerticalOscillation: Double = 0.0
    ) {
        self.startTime = startTime
        self.distanceMeters = distanceMeters
        self.meanPaceSecPerKm = meanPaceSecPerKm
        self.meanCadence = meanCadence
        self.meanHR = meanHR
        self.meanVerticalOscillation = meanVerticalOscillation
    }
}

/// The deterministic math engine for Runalyst V2.
/// Responsible for transforming raw HealthKit continuous streams into structured,
/// noise-filtered metrics (working averages, CV, linear regression, and rule-based classification).
actor FramboiseEngine {

    // MARK: - Dead Stop & Walking Filter

    /// Filters out stationary time, traffic stops, and walking breaks.
    /// Strictly filters to KEEP samples where speed is greater than the walking threshold
    /// (e.g., speed > 1.5 m/s or cadence > 130 SPM). Drops everything else.
    func filterRunningSamples(buckets: [BucketData]) -> [BucketData] {
        return buckets.filter { bucket in
            let speedMetersPerSecond = bucket.distanceMeters / 60.0
            let isRunning = speedMetersPerSecond > 1.5 || bucket.meanCadence > 130.0
            return isRunning
        }
    }

    /// Alias for filterRunningSamples to maintain backward compatibility with callers.
    func trimDeadStops(buckets: [BucketData]) -> [BucketData] {
        return filterRunningSamples(buckets: buckets)
    }

    // MARK: - Working Averages & Aggregate Pace

    /// Calculates true working averages by strictly summing the filtered running samples.
    /// - Strictly sums the duration of only the kept/filtered samples.
    /// - Enforces hard safety constraint: workingDuration <= rawWorkoutDuration.
    /// - Calculates pace using pure aggregate ratios (workingDuration / workingDistanceKm) to eliminate harmonic distortion.
    func calculateWorkingAverages(
        trimmed: [BucketData],
        rawWorkoutDuration: Double? = nil
    ) -> (workingPace: Double, workingCadence: Double, workingHR: Double, workingOscillation: Double, workingDistance: Double, workingDuration: Double) {
        guard !trimmed.isEmpty else { return (0, 0, 0, 0, 0, 0) }

        var totalDistanceMeters: Double = 0
        var totalCadence: Double = 0
        var totalHR: Double = 0
        var totalOscillation: Double = 0
        var oscillationBucketCount: Int = 0

        for bucket in trimmed {
            totalDistanceMeters += bucket.distanceMeters
            totalCadence += bucket.meanCadence
            totalHR += bucket.meanHR
            if bucket.meanVerticalOscillation > 0 {
                totalOscillation += bucket.meanVerticalOscillation
                oscillationBucketCount += 1
            }
        }

        // Strictly sum the duration of only the kept/filtered samples (60s per bucket)
        var workingDuration = Double(trimmed.count * 60)

        // Hard safety constraint: workingDuration must be <= rawWorkout.duration
        if let rawDuration = rawWorkoutDuration, rawDuration > 0 {
            workingDuration = min(workingDuration, rawDuration)
        }

        // Pure aggregate ratio: Divide newly calculated workingDuration (in seconds) by workingDistance (in kilometers)
        let workingDistanceKm = totalDistanceMeters / 1000.0
        let workingPace = workingDistanceKm > 0 ? (workingDuration / workingDistanceKm) : 0.0

        let workingCadence = totalCadence / Double(trimmed.count)
        let workingHR = totalHR / Double(trimmed.count)
        let workingOscillation = oscillationBucketCount > 0 ? (totalOscillation / Double(oscillationBucketCount)) : 0.0

        return (workingPace, workingCadence, workingHR, workingOscillation, totalDistanceMeters, workingDuration)
    }

    // MARK: - Mathematical Features

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for pace across buckets.
    func calculatePaceCV(bucketPaces: [Double]) -> Double {
        guard bucketPaces.count > 1 else { return 0 }
        let validPaces = bucketPaces.filter { $0 > 0 && $0.isFinite }
        guard validPaces.count > 1 else { return 0 }

        let mu = validPaces.reduce(0, +) / Double(validPaces.count)
        guard mu > 0 else { return 0 }

        let sumSquaredDiff = validPaces.reduce(0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(validPaces.count - 1)
        let sigma = sqrt(variance)

        return sigma / mu
    }

    /// Calculates the linear regression slope of pace over time (least-squares).
    /// Negative slope = speeding up (progression). Positive slope = slowing down (fatigue).
    func calculatePaceSlope(bucketPaces: [Double]) -> Double {
        guard bucketPaces.count > 1 else { return 0 }
        let validPaces = bucketPaces.filter { $0 > 0 && $0.isFinite }
        let n = Double(validPaces.count)
        guard n > 1 else { return 0 }

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (i, y) in validPaces.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = (n * sumX2) - (sumX * sumX)
        guard denominator != 0 else { return 0 }

        let slope = ((n * sumXY) - (sumX * sumY)) / denominator
        return slope
    }

    /// Calculates the fraction of time spent in Zone 4 (or higher).
    func calculatePercentZone4(bucketHRs: [Double], maxHR: Double) -> Double {
        guard maxHR > 0, !bucketHRs.isEmpty else { return 0 }
        // Zone 4 typically starts around 80-85% of max HR. Let's use 85%.
        let zone4Threshold = maxHR * 0.85
        let zone4Count = bucketHRs.filter { $0 >= zone4Threshold }.count
        return Double(zone4Count) / Double(bucketHRs.count)
    }

    // MARK: - Classification (Rule-based Stub)

    /// Rule-based fallback classifier used until a CoreML model is available or as fallback.
    /// Enforces strict cardiac guardrails (runs with high HR or high Zone 4 are never easy/recovery).
    func classifyRun(cv: Double, slope: Double, zone4: Double, durationMinutes: Double, averageHR: Double? = nil) -> String {
        // Strict cardiac guardrail
        if let hr = averageHR, hr >= 165 || zone4 >= 0.25 {
            if zone4 > 0.40 || cv > 0.15 {
                return "Intervals"
            } else if slope < -0.3 {
                return "Progression Run"
            } else {
                return "Tempo Run"
            }
        }

        if cv > 0.20 && slope > -1.0 && slope < 1.0 {
            if zone4 < 0.10 {
                return "urbanTraffic"
            } else if zone4 > 0.40 {
                return "Intervals" // Or Pyramids/Hill Repeats, simplified for stub
            } else {
                return "Fartlek"
            }
        }

        if slope < -0.4 {
            return "Progression Run"
        }

        if durationMinutes > 70 && slope > 0.10 {
            return "Long Run"
        }

        if cv < 0.05 && zone4 > 0.50 {
            return "Tempo Run"
        }

        if zone4 < 0.03 && durationMinutes < 40 {
            return "Recovery Run"
        }

        if zone4 > 0.05 && zone4 < 0.20 && cv < 0.06 {
            return "Steady Run"
        }

        return "Easy Run"
    }

    // MARK: - Tags

    func generateFramboiseTags(cv: Double, slope: Double, deadStopsCount: Int) -> [String] {
        var tags = [String]()

        if deadStopsCount > 5 {
            tags.append("urbanTraffic")
        }
        if slope > 0.3 {
            tags.append("fatigueDrift")
        }
        if slope < -0.5 {
            tags.append("progressiveFinish")
        }
        if cv > 0.25 && deadStopsCount <= 2 {
            tags.append("highVolatility")
        }

        return tags
    }
}
