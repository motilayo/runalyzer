import XCTest
@testable import Runalyst

final class FramboiseEngineTests: XCTestCase {
    var engine: FramboiseEngine!

    override func setUp() async throws {
        engine = FramboiseEngine()
    }

    func testTrimDeadStops() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 100),
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 0.1, meanPaceSecPerKm: 0, meanCadence: 20, meanHR: 120)
        ]

        let trimmed = await engine.trimDeadStops(buckets: buckets)
        XCTAssertEqual(trimmed.count, 1)
        XCTAssertEqual(trimmed[0].distanceMeters, 100)
    }

    func testCalculateWorkingAverages() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingCadence, 162)
        XCTAssertEqual(averages.workingHR, 142)
        XCTAssertEqual(averages.workingDistance, 400, accuracy: 0.01)
        XCTAssertEqual(averages.workingDuration, 120, accuracy: 0.01)
        // 400 meters in 120 seconds -> 120 / 0.4 = 300 sec/km
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01)
    }

    func testCalculateWorkingAverages_VerticalOscillationExcludesZeroBuckets() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140, meanVerticalOscillation: 8.8),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144, meanVerticalOscillation: 0.0), // no sample this minute
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 162, meanHR: 142, meanVerticalOscillation: 9.2)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        // Only the two non-zero buckets (8.8 and 9.2) should be averaged -> 9.0, not (8.8 + 0 + 9.2) / 3 = 6.0
        XCTAssertEqual(averages.workingOscillation, 9.0, accuracy: 0.01)
    }

    func testFilterRunningSamples_DropsStationaryAndWalking() async {
        let buckets = [
            // Stationary: 0 m/s, 0 SPM -> Drop
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 90),
            // Walking break: 60m in 60s = 1.0 m/s (< 1.5), cadence 105 (< 130) -> Drop
            BucketData(startTime: Date(), distanceMeters: 60, meanPaceSecPerKm: 1000, meanCadence: 105, meanHR: 110),
            // Running by speed: 120m in 60s = 2.0 m/s (> 1.5), cadence 125 -> Keep
            BucketData(startTime: Date(), distanceMeters: 120, meanPaceSecPerKm: 500, meanCadence: 125, meanHR: 145),
            // Running by cadence: 80m in 60s = 1.33 m/s, cadence 150 (> 130) -> Keep
            BucketData(startTime: Date(), distanceMeters: 80, meanPaceSecPerKm: 750, meanCadence: 150, meanHR: 140)
        ]

        let filtered = await engine.filterRunningSamples(buckets: buckets)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].distanceMeters, 120)
        XCTAssertEqual(filtered[1].distanceMeters, 80)
    }

    func testCalculateWorkingAverages_EnforcesDurationSafetyConstraint() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140)
        ]
        // 2 buckets = 120 seconds, but raw workout duration was 100 seconds
        let averages = await engine.calculateWorkingAverages(trimmed: buckets, rawWorkoutDuration: 100)
        XCTAssertEqual(averages.workingDuration, 100, "workingDuration must be <= rawWorkoutDuration")
    }

    func testCalculateWorkingAverages_PureAggregateRatioPace() async {
        // Harmonic distortion check:
        // Bucket 1: 100m in 60s (pace = 600 s/km)
        // Bucket 2: 300m in 60s (pace = 200 s/km)
        // Arithmetic mean of paces = (600 + 200) / 2 = 400 s/km (WRONG)
        // Aggregate ratio = 120s / 0.4km = 300 s/km (CORRECT)
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 600, meanCadence: 150, meanHR: 130),
            BucketData(startTime: Date(), distanceMeters: 300, meanPaceSecPerKm: 200, meanCadence: 170, meanHR: 160)
        ]
        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01, "workingPace must use pure aggregate ratio (duration / distanceKm)")
    }

    func testCalculatePaceCV() async {
        let paces = [300.0, 300.0, 300.0, 300.0]
        let calculatedCV = await engine.calculatePaceCV(bucketPaces: paces)
        XCTAssertEqual(calculatedCV, 0, accuracy: 0.001)

        let variablePaces = [200.0, 400.0]
        let calculatedCV2 = await engine.calculatePaceCV(bucketPaces: variablePaces)
        // mean = 300. variance = sum((x-300)^2) / 1 = 10000 + 10000 = 20000. sigma = sqrt(20000) ~ 141.42
        // CV = 141.42 / 300 = 0.471
        XCTAssertEqual(calculatedCV2, 0.471, accuracy: 0.01)
    }

    func testCalculatePaceSlope() async {
        let paces = [300.0, 310.0, 320.0, 330.0]
        let slope = await engine.calculatePaceSlope(bucketPaces: paces)
        // Increasing by 10 per bucket -> slope = +10
        XCTAssertEqual(slope, 10, accuracy: 0.01)

        let paces2 = [300.0, 290.0, 280.0, 270.0]
        let slope2 = await engine.calculatePaceSlope(bucketPaces: paces2)
        // Decreasing by 10 per bucket -> slope = -10
        XCTAssertEqual(slope2, -10, accuracy: 0.01)
    }

    // MARK: - Topological Signature Classification Tests (ADR-0003)

    func testSept24IncidentReplay_SteadyEffortWithWarmupAndFadeNotFartlek() async {
        // September 24 incident replay: 32:46 run with warmup -> cruise -> fade arc
        // cv ≈ 0.08, cadenceCV ≈ 0.028 (which falsely crossed legacy scalar thresholds)
        // With topological signature analysis, 0 or 1 alternating cycles exist -> Steady Effort!
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 1. Warmup (5 min = 10 30-second buckets): ~451 s/km (7'31"), 150 SPM, 135 HR
        for _ in 0..<10 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 66.5,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 451.0,
                meanCadence: 150.0,
                meanHR: 135.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        // 2. Steady Cruise (20 min = 40 30-second buckets): ~402 s/km (6'42"), 156 SPM, 152 HR
        for _ in 0..<40 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 74.6,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 402.0,
                meanCadence: 156.0,
                meanHR: 152.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        // 3. Late-Run Fatigue Fade (7 min = 14 30-second buckets): ~451 s/km (7'31"), 148 SPM, 155 HR
        for _ in 0..<14 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 66.5,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 451.0,
                meanCadence: 148.0,
                meanHR: 155.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "Smooth continuous arc must produce < 3 oscillation cycles")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.08,
            slope: 0.0,
            zone4: 0.25,
            durationMinutes: 32.7,
            cadenceCV: 0.028,
            averageHR: 156.0
        )

        XCTAssertNotEqual(classification, "Fartlek", "Continuous warmup/cruise/fade run must NEVER be classified as Fartlek")
        XCTAssertNotEqual(classification, "Intervals", "Continuous warmup/cruise/fade run must NEVER be classified as Intervals")
        XCTAssertEqual(classification, "Steady Effort")
    }

    func testTrueFartlekClassification_IrregularSurges() async {
        // True Fartlek: 5 irregular surges of highly variable durations (30s, 120s, 45s, 180s, 30s)
        // alternating with variable recovery jogs (60s, 150s, 45s, 90s, 60s)
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Warmup: 3 min (12 buckets of 15s) at 145 SPM, 480 s/km
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 31.25, durationSeconds: 15, meanPaceSecPerKm: 480, meanCadence: 145, meanHR: 130))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 1: 30s surge (2 buckets) at 178 SPM, 320 s/km, 165 HR; 60s rec (4 buckets) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 46.87, durationSeconds: 15, meanPaceSecPerKm: 320, meanCadence: 178, meanHR: 165))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 138, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 2: 120s surge (8 buckets) at 176 SPM, 330 s/km, 168 HR; 150s rec (10 buckets) at 138 SPM, 510 s/km, 138 HR
        for _ in 0..<8 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45.45, durationSeconds: 15, meanPaceSecPerKm: 330, meanCadence: 176, meanHR: 168))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 29.4, durationSeconds: 15, meanPaceSecPerKm: 510, meanCadence: 138, meanHR: 138))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 3: 45s surge (3 buckets) at 178 SPM, 320 s/km, 166 HR; 45s rec (3 buckets) at 140 SPM, 500 s/km, 140 HR
        for _ in 0..<3 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 46.87, durationSeconds: 15, meanPaceSecPerKm: 320, meanCadence: 178, meanHR: 166))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<3 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 140, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 4: 180s surge (12 buckets) at 174 SPM, 340 s/km, 167 HR; 90s rec (6 buckets) at 139 SPM, 500 s/km, 140 HR
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 44.1, durationSeconds: 15, meanPaceSecPerKm: 340, meanCadence: 174, meanHR: 167))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 139, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 5: 30s surge (2 buckets) at 180 SPM, 310 s/km, 168 HR; 60s rec (4 buckets) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 48.38, durationSeconds: 15, meanPaceSecPerKm: 310, meanCadence: 180, meanHR: 168))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 138, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "True Fartlek must detect >= 3 oscillation cycles")

        let regularity = await engine.calculateCycleRegularity(cycles: cycles)
        XCTAssertLessThan(regularity, 0.65, "Irregular Fartlek surge durations must produce regularity < 0.65")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.13,
            slope: 0.0,
            zone4: 0.35,
            durationMinutes: 25.0,
            cadenceCV: 0.045,
            averageHR: 155.0
        )
        XCTAssertEqual(classification, "Fartlek")
    }

    func testStructuredIntervalsClassification_MetronomicReps() async {
        // Structured Intervals: 4 uniform reps (60s work, 60s recovery)
        var buckets: [BucketData] = []
        var currentTime = Date()

        for _ in 0..<4 {
            // Work: 60s (2 buckets of 30s) at 180 SPM, 300 s/km, 172 HR
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 300, meanCadence: 180, meanHR: 172))
                currentTime = currentTime.addingTimeInterval(30)
            }
            // Recovery: 60s (2 buckets of 30s) at 135 SPM, 520 s/km, 138 HR
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 57.7, durationSeconds: 30, meanPaceSecPerKm: 520, meanCadence: 135, meanHR: 138))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "Interval workout must produce >= 3 oscillation cycles")

        let regularity = await engine.calculateCycleRegularity(cycles: cycles)
        XCTAssertGreaterThanOrEqual(regularity, 0.65, "Metronomic intervals must produce regularity >= 0.65")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.15,
            slope: 0.0,
            zone4: 0.50,
            durationMinutes: 20.0,
            cadenceCV: 0.050,
            averageHR: 160.0
        )
        XCTAssertEqual(classification, "Intervals")
    }

    func testProgressionRun_QuintileMonotonicity() async {
        // Progression Run: 5 quintiles accelerating monotonically (lower pace = faster)
        var buckets: [BucketData] = []
        var currentTime = Date()

        let paces = [400.0, 375.0, 350.0, 325.0, 300.0]
        for pace in paces {
            // 4 buckets per quintile = 20 buckets total (10 min)
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 162, meanHR: 150))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let isMonotonic = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertTrue(isMonotonic, "Continuously accelerating quintiles must pass quintile progression test")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.06,
            slope: -0.30,
            zone4: 0.20,
            durationMinutes: 25.0,
            cadenceCV: 0.015,
            averageHR: 152.0
        )
        XCTAssertEqual(classification, "Progression Run")
    }

    func testSteadyRunWithSingleTrafficStop_RemainsContinuous() async {
        // Continuous run with a single 30s stop midway
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 10 buckets cruising at 158 SPM
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 80, durationSeconds: 30, meanPaceSecPerKm: 375, meanCadence: 158, meanHR: 148))
            currentTime = currentTime.addingTimeInterval(30)
        }
        // 1 bucket traffic stop at 0 SPM
        buckets.append(BucketData(startTime: currentTime, distanceMeters: 0, durationSeconds: 30, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 120))
        currentTime = currentTime.addingTimeInterval(30)
        // 10 buckets cruising at 158 SPM
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 80, durationSeconds: 30, meanPaceSecPerKm: 375, meanCadence: 158, meanHR: 148))
            currentTime = currentTime.addingTimeInterval(30)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "A single traffic pause must produce at most 1 cycle, not triggering intermittent classification")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.09,
            slope: 0.0,
            zone4: 0.15,
            durationMinutes: 21.0,
            cadenceCV: 0.030,
            averageHR: 146.0
        )
        XCTAssertNotEqual(classification, "Fartlek")
        XCTAssertNotEqual(classification, "Intervals")
        XCTAssertTrue(classification == "Steady Effort" || classification == "Easy Run")
    }
}
