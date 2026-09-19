import Foundation
import HealthKit

/// Represents a single 60-second slice of a run for analysis.
struct BucketData: Sendable {
    let startTime: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let meanPaceSecPerKm: Double
    let meanCadence: Double
    let meanHR: Double
    let meanVerticalOscillation: Double

    init(
        startTime: Date,
        distanceMeters: Double,
        durationSeconds: Double = 60.0,
        meanPaceSecPerKm: Double,
        meanCadence: Double,
        meanHR: Double,
        meanVerticalOscillation: Double = 0.0
    ) {
        self.startTime = startTime
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
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
            let speedMetersPerSecond = bucket.durationSeconds > 0 ? (bucket.distanceMeters / bucket.durationSeconds) : 0
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
        rawWorkoutDuration: Double? = nil,
        rawWorkoutDistance: Double? = nil,
        originalBucketCount: Int? = nil
    ) -> (workingPace: Double, workingCadence: Double, workingHR: Double, workingOscillation: Double, workingDistance: Double, workingDuration: Double) {
        guard !trimmed.isEmpty else { return (0, 0, 0, 0, 0, 0) }

        var totalDistanceMeters: Double = 0
        var totalCadence: Double = 0
        var totalHR: Double = 0
        var totalOscillation: Double = 0
        var oscillationBucketCount: Int = 0
        var validHRBucketCount: Int = 0

        for bucket in trimmed {
            totalDistanceMeters += bucket.distanceMeters
            totalCadence += bucket.meanCadence

            if bucket.meanHR >= 40 {
                totalHR += bucket.meanHR
                validHRBucketCount += 1
            }

            if bucket.meanVerticalOscillation > 0 {
                totalOscillation += bucket.meanVerticalOscillation
                oscillationBucketCount += 1
            }
        }

        // If no buckets were trimmed (no dead stops), Working stats MUST perfectly equal Raw stats
        let isFullyActive = (originalBucketCount != nil) && (trimmed.count == originalBucketCount)

        // Strictly sum the duration of only the kept/filtered samples
        let trimmedDuration = trimmed.reduce(0) { $0 + $1.durationSeconds }
        var workingDuration = isFullyActive ? (rawWorkoutDuration ?? trimmedDuration) : trimmedDuration

        // Hard safety constraint: workingDuration must be <= rawWorkout.duration
        if !isFullyActive, let rawDuration = rawWorkoutDuration, rawDuration > 0 {
            workingDuration = min(workingDuration, rawDuration)
        }

        // Pure aggregate ratio: Divide newly calculated workingDuration (in seconds) by workingDistance (in kilometers)
        let workingDistanceKm = isFullyActive ? ((rawWorkoutDistance ?? totalDistanceMeters) / 1000.0) : (totalDistanceMeters / 1000.0)
        let workingDistanceMetersFinal = isFullyActive ? (rawWorkoutDistance ?? totalDistanceMeters) : totalDistanceMeters
        let workingPace = workingDistanceKm > 0 ? (workingDuration / workingDistanceKm) : 0.0

        let workingCadence = totalCadence / Double(trimmed.count)
        let workingHR = validHRBucketCount > 0 ? (totalHR / Double(validHRBucketCount)) : 0.0
        let workingOscillation = oscillationBucketCount > 0 ? (totalOscillation / Double(oscillationBucketCount)) : 0.0

        return (workingPace, workingCadence, workingHR, workingOscillation, workingDistanceMetersFinal, workingDuration)
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

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for cadence across buckets.
    func calculateCadenceCV(bucketCadences: [Double]) -> Double {
        guard bucketCadences.count > 1 else { return 0 }
        let validCadences = bucketCadences.filter { $0 > 0 && $0.isFinite }
        guard validCadences.count > 1 else { return 0 }

        let mu = validCadences.reduce(0, +) / Double(validCadences.count)
        guard mu > 0 else { return 0 }

        let sumSquaredDiff = validCadences.reduce(0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(validCadences.count - 1)
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

    // MARK: - Classification (Physiological Weighted Engine)

    /// Multi-delta weighted classification engine enforcing turnover stability,
    /// cardiac strain guardrails, and pacing trends.
    func classifyRun(
        cv: Double,
        slope: Double,
        zone4: Double,
        durationMinutes: Double,
        cadenceCV: Double = 0.0,
        averageHR: Double? = nil,
        paceDelta: Double? = nil,
        hrDelta: Double? = nil
    ) -> String {
        // PHASE 1: Structural Gate (Intermittent vs. Continuous)
        // Intervals and Fartlek ("speed play") require alternating cadence surges and recovery.
        // A rock-solid turnover (cadenceCV < 0.025) guarantees a continuous run.
        let isIntermittentCandidate = cadenceCV >= 0.025 && cv >= 0.07

        if isIntermittentCandidate {
            if cv >= 0.12 || cadenceCV >= 0.038 {
                return "Intervals"
            } else {
                return "Fartlek"
            }
        }

        // PHASE 2: Continuous Structural Archetypes (Pacing Slope & Volume)
        if durationMinutes >= 68.0 && slope > -0.20 && zone4 < 0.45 {
            return "Long Run"
        }

        if slope < -0.225 && durationMinutes >= 20.0 {
            return "Progression Run"
        }

        // PHASE 3: Continuous Intensity Matrix (Zone 4 + HR Strain + Pace Delta)
        // Calculate normalized Intensity Score (0 to 100)
        let z4Score = min(100.0, zone4 * 125.0)

        let hrScore: Double
        if let hr = averageHR {
            if hr >= 170 {
                hrScore = min(100.0, 85.0 + (hr - 170.0) * 1.5)
            } else if hr >= 160 {
                hrScore = 70.0 + (hr - 160.0) * 1.5
            } else if hr >= 145 {
                hrScore = 45.0 + (hr - 145.0) * 1.6
            } else if hr >= 130 {
                hrScore = 25.0 + (hr - 130.0) * 1.3
            } else {
                hrScore = max(10.0, hr - 110.0)
            }
        } else if let delta = hrDelta {
            if delta >= 15 {
                hrScore = min(100.0, 85.0 + (delta - 15.0) * 1.5)
            } else if delta >= 5 {
                hrScore = 65.0 + (delta - 5.0) * 2.0
            } else if delta >= -5 {
                hrScore = 45.0 + (delta + 5.0) * 2.0
            } else {
                hrScore = max(10.0, 30.0 + delta)
            }
        } else {
            hrScore = z4Score
        }

        let paceScore: Double
        if let pDelta = paceDelta {
            if pDelta <= -30 {
                paceScore = 90.0
            } else if pDelta <= -10 {
                paceScore = 70.0
            } else if pDelta <= 10 {
                paceScore = 50.0
            } else {
                paceScore = max(15.0, 30.0 - (pDelta - 10.0))
            }
        } else {
            paceScore = hrScore
        }

        // Weighted combination: 45% Zone 4, 35% HR Strain, 20% Pace Effort
        let totalIntensity = (0.45 * z4Score) + (0.35 * hrScore) + (0.20 * paceScore)

        if totalIntensity < 22.0 && zone4 <= 0.03 && durationMinutes < 35.0 {
            return "Recovery Run"
        } else if totalIntensity < 48.0 && zone4 <= 0.20 {
            return "Easy Run"
        } else if totalIntensity >= 72.0 && zone4 >= 0.50 && durationMinutes >= 20.0 && (paceDelta.map { $0 <= -15.0 } ?? true) {
            return "Tempo Run"
        } else {
            return "Steady Effort"
        }
    }

    // MARK: - Tags

    func generateFramboiseTags(cv: Double, slope: Double, deadStopsCount: Int) -> [String] {
        var tags = [String]()

        if deadStopsCount > 5 {
            tags.append("urbanTraffic")
        }
        if slope > 0.225 {
            tags.append("fatigueDrift")
        }
        if slope < -0.375 {
            tags.append("progressiveFinish")
        }
        if cv > 0.18 && deadStopsCount <= 2 {
            tags.append("highVolatility")
        }

        return tags
    }
}
