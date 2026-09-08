import XCTest
import SwiftData
import CoreML
import HealthKit
import WorkoutKit
@testable import Runalyzer

final class V2PaceFormatterTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "useMetricSystem")
        super.tearDown()
    }

    func testPaceFormatter_StandardMetric() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")

        // 300 seconds/km = 5:00/km
        let formatted = formatDisplayPace(secondsPerKilometer: 300)
        XCTAssertEqual(formatted, "5:00/km")

        // 325 seconds/km = 5:25/km
        let formatted2 = formatDisplayPace(secondsPerKilometer: 325)
        XCTAssertEqual(formatted2, "5:25/km")
    }

    func testPaceFormatter_SecondsNeverExceed59() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")

        // Test boundary near 60 seconds
        for sec in 355...365 {
            let formatted = formatDisplayPace(secondsPerKilometer: Double(sec))
            let parts = formatted.replacingOccurrences(of: "/km", with: "").split(separator: ":")
            XCTAssertEqual(parts.count, 2)
            if let s = Int(parts[1]) {
                XCTAssertLessThanOrEqual(s, 59, "Seconds should never exceed 59 in formatted pace: \(formatted)")
                XCTAssertGreaterThanOrEqual(s, 0)
            } else {
                XCTFail("Could not parse seconds from \(formatted)")
            }
        }
    }

    func testPaceFormatter_NoOverflow415Minutes() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")

        // Extremely slow / stalled run: 25,000 seconds/km
        let formattedHuge = formatDisplayPace(secondsPerKilometer: 25000)
        let parts = formattedHuge.replacingOccurrences(of: "/km", with: "").split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        if let _ = Int(parts[0]) {
            XCTAssertFalse(formattedHuge.contains("415:16"), "Pace formatter must never render 415:16/km: got \(formattedHuge)")
        }

        // Decimal minutes format
        let formattedDecimal = (415.26).formattedPaceString
        XCTAssertFalse(formattedDecimal.contains("415:"), "Pace formatter must never render 415:16/km: got \(formattedDecimal)")
    }

    func testPaceFormatter_ImperialConversion() {
        UserDefaults.standard.set(false, forKey: "useMetricSystem")

        // 300 seconds/km ≈ 482.8 seconds/mile ≈ 8:03/mi
        let formatted = formatDisplayPace(secondsPerKilometer: 300)
        XCTAssertTrue(formatted.hasSuffix("/mi"), "Imperial pace should end in /mi")
        XCTAssertEqual(formatted, "8:03/mi")
    }

    func testPaceFormatter_ZeroOrNegative() {
        let zeroPace = formatDisplayPace(secondsPerKilometer: 0)
        XCTAssertEqual(zeroPace, "--:--")

        let negPace = formatDisplayPace(secondsPerKilometer: -10)
        XCTAssertEqual(negPace, "--:--")
    }
}

final class V2FramboiseEngineTests: XCTestCase {

    func testLinearRegressionSlope() {
        // Linearly decreasing pace: 330, 320, 310, 300, 290
        let buckets: [Double] = [330, 320, 310, 300, 290]
        let mean = buckets.reduce(0, +) / Double(buckets.count)
        let midpoint = Double(buckets.count - 1) / 2.0
        let denom = buckets.enumerated().reduce(0.0) { sum, item in sum + pow(Double(item.offset) - midpoint, 2) }
        let slope = buckets.enumerated().reduce(0.0) { sum, item in
            sum + (Double(item.offset) - midpoint) * (item.element - mean)
        } / denom

        XCTAssertEqual(slope, -10.0, accuracy: 0.001)
    }

    func testCoefficientOfVariation() {
        // Uniform pace -> CV should be 0
        let uniform: [Double] = [300, 300, 300, 300]
        let mean = uniform.reduce(0, +) / Double(uniform.count)
        let variance = uniform.reduce(0.0) { sum, v in sum + pow(v - mean, 2) } / Double(uniform.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / mean
        XCTAssertEqual(cv, 0.0, accuracy: 0.001)

        // Varied pace -> CV > 0
        let varied: [Double] = [240, 360, 240, 360]
        let variedMean = varied.reduce(0, +) / Double(varied.count)
        let variedVariance = varied.reduce(0.0) { sum, v in sum + pow(v - variedMean, 2) } / Double(varied.count)
        let variedStdDev = sqrt(variedVariance)
        let variedCV = variedStdDev / variedMean
        XCTAssertGreaterThan(variedCV, 0.15)
    }

    func testOutlierTrimmingPreservesValidBuckets() {
        let rawPaces: [Double] = [310, 305, 0, 950, 308, 312, 0]
        let trimmed = FramboiseEngine.trimPaceOutliers(from: rawPaces)
        XCTAssertFalse(trimmed.contains(0), "Dead stops (0 sec/km) should be trimmed")
        XCTAssertFalse(trimmed.contains(950), "Extreme outlier stops (>900 sec/km) should be trimmed")
        XCTAssertEqual(trimmed.count, 4)
    }
}

final class V2CoreMLModelManagerTests: XCTestCase {

    func testRunFeatures_ToMultiArray() throws {
        let features = RunFeatures(
            averagePace: 300.0,
            paceCV: 0.05,
            paceSlope: -2.5,
            percentZone4: 0.35,
            durationMinutes: 30.0
        )

        let array = try features.toMultiArray()
        XCTAssertEqual(array.shape, [5])
        XCTAssertEqual(array[0].floatValue, 300.0, accuracy: 0.01)
        XCTAssertEqual(array[1].floatValue, 0.05, accuracy: 0.01)
        XCTAssertEqual(array[2].floatValue, -2.5, accuracy: 0.01)
        XCTAssertEqual(array[3].floatValue, 0.35, accuracy: 0.01)
        XCTAssertEqual(array[4].floatValue, 30.0, accuracy: 0.01)
    }

    func testTrainingFeatureProvider_FeatureAccess() throws {
        let features = RunFeatures(
            averagePace: 320.0,
            paceCV: 0.15,
            paceSlope: 1.0,
            percentZone4: 0.10,
            durationMinutes: 45.0
        )
        let multiArray = try features.toMultiArray()
        let provider = TrainingFeatureProvider(multiArray: multiArray, label: "tempo")

        XCTAssertTrue(provider.featureNames.contains("features"))
        XCTAssertTrue(provider.featureNames.contains("label"))

        let featValue = provider.featureValue(for: "features")
        XCTAssertNotNil(featValue?.multiArrayValue)

        let labelValue = provider.featureValue(for: "label")
        XCTAssertEqual(labelValue?.stringValue, "tempo")
    }

    @MainActor
    func testModelManager_FallbackClassification() {
        let manager = ModelManager.shared

        // Test high CV fallback -> intervals
        let features = RunFeatures(
            averagePace: 300,
            paceCV: 0.20,
            paceSlope: 0.0,
            percentZone4: 0.1,
            durationMinutes: 30.0
        )
        let classification = manager.classify(features: features)
        XCTAssertEqual(classification, "intervals")
    }
}

final class V2ZeroNumbersSanitizerTests: XCTestCase {

    func testSanitizeZeroNumbers_StripsDigitsAndPercent() {
        let input = "Your cadence was 165 SPM, which is 10% higher than your baseline of 150."
        let sanitized = sanitizeZeroNumbers(input)

        XCTAssertFalse(sanitized.contains("165"), "Digits must be removed")
        XCTAssertFalse(sanitized.contains("10"), "Digits must be removed")
        XCTAssertFalse(sanitized.contains("%"), "Percent sign must be removed")
        XCTAssertFalse(sanitized.contains("150"), "Digits must be removed")
        XCTAssertTrue(sanitized.contains("cadence"), "Qualitative words must be preserved")
        XCTAssertTrue(sanitized.contains("higher than your baseline"), "Qualitative phrases must be preserved")
    }

    func testSanitizeZeroNumbers_PureQualitativeRemainsIntact() {
        let input = "Strong rhythmic consistency throughout the run with steady turnover."
        let sanitized = sanitizeZeroNumbers(input)
        XCTAssertEqual(sanitized, input)
    }
}

final class V2WorkoutKitHandoffTests: XCTestCase {

    func testProgrammaticWorkoutStructure() {
        // Validate building a WorkoutStep, Cadence Alert, and IntervalBlock
        let alertRange = 165.0...175.0
        var workStep = WorkoutStep(goal: .time(60, .seconds))
        workStep.alert = .cadence(alertRange)

        let recoveryStep = WorkoutStep(goal: .time(60, .seconds))
        let intervalBlock = IntervalBlock(
            steps: [
                IntervalStep(.work, step: workStep),
                IntervalStep(.recovery, step: recoveryStep)
            ],
            iterations: 5
        )

        let warmup = WorkoutStep(goal: .time(300, .seconds))
        let customWorkout = CustomWorkout(
            activity: .running,
            location: .outdoor,
            warmup: warmup,
            blocks: [intervalBlock]
        )

        let plan = WorkoutPlan(.custom(customWorkout))
        XCTAssertNotNil(plan)
    }
}
