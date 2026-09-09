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
    
    // MARK: - Dead Stop Trimming
    
    /// Filters out buckets where the user was stationary (e.g., waiting at traffic lights).
    /// A bucket is considered a dead stop if distance is 0 or cadence is 0, but HR is > 0.
    func trimDeadStops(buckets: [BucketData]) -> [BucketData] {
        return buckets.filter { bucket in
            let isMoving = bucket.distanceMeters > 0.5 && bucket.meanCadence > 40
            return isMoving
        }
    }
    
    // MARK: - Working Averages
    
    /// Calculates true working average pace from total trimmed time and distance, avoiding ratio averaging skew.
    func calculateWorkingAverages(trimmed: [BucketData]) -> (workingPace: Double, workingCadence: Double, workingHR: Double, workingOscillation: Double) {
        guard !trimmed.isEmpty else { return (0, 0, 0, 0) }
        
        var totalDistance: Double = 0
        var totalCadence: Double = 0
        var totalHR: Double = 0
        var totalOscillation: Double = 0
        var oscillationBucketCount: Int = 0
        
        for bucket in trimmed {
            totalDistance += bucket.distanceMeters
            totalCadence += bucket.meanCadence
            totalHR += bucket.meanHR
            if bucket.meanVerticalOscillation > 0 {
                totalOscillation += bucket.meanVerticalOscillation
                oscillationBucketCount += 1
            }
        }
        
        let totalTimeSeconds = Double(trimmed.count * 60)
        
        let workingPace = totalDistance > 0 ? (totalTimeSeconds / (totalDistance / 1000.0)) : 0
        let workingCadence = totalCadence / Double(trimmed.count)
        let workingHR = totalHR / Double(trimmed.count)
        let workingOscillation = oscillationBucketCount > 0 ? (totalOscillation / Double(oscillationBucketCount)) : 0.0
        
        return (workingPace, workingCadence, workingHR, workingOscillation)
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
    
    /// Rule-based fallback classifier used until a CoreML model is available.
    func classifyRun(cv: Double, slope: Double, zone4: Double, durationMinutes: Double) -> String {
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
