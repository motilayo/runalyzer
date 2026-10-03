import XCTest
@testable import Runalyst

final class WorkoutTelemetryVeracityTests: XCTestCase {
    var engine: FramboiseEngine!

    override func setUp() async throws {
        engine = FramboiseEngine()
    }

    // MARK: - 1. Authentic Golden Fixtures Accuracy

    func testGoldenFixtures_AuthenticIntervalsWithCardiacLag() async {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let buckets = fixture.toBucketData()

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(
            cycles.count,
            3,
            "Authentic 3x5.5m intervals with cardiac lag and terminal rep must detect >= 3 corroborated cycles"
        )

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.16,
            slope: -0.30,
            zone4: 0.60,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.045,
            averageHR: 156.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_HillySteadyAerobicRun() async {
        let fixture = GoldenTelemetryFixtures.hillySteadyAerobicRun
        let buckets = fixture.toBucketData()

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(
            cycles.count,
            3,
            "Hilly steady run without cadence surges must produce < 3 cycles despite large pace fluctuations"
        )

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.12,
            slope: 0.0,
            zone4: 0.20,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.015,
            averageHR: 146.0
        )
        XCTAssertTrue(
            classification == "Steady Effort" || classification == "Easy Run",
            "Hilly steady run must classify as continuous steady or easy effort, got \(classification)"
        )
    }

    func testGoldenFixtures_MonotonicProgressionRun() async {
        let fixture = GoldenTelemetryFixtures.monotonicProgressionRun
        let buckets = fixture.toBucketData()

        let isProgression = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertTrue(isProgression, "Monotonic quintiles must validate as progression")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.075,
            slope: -0.35,
            zone4: 0.35,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.022,
            averageHR: 152.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_TrueFartlekIrregularRun() async {
        let fixture = GoldenTelemetryFixtures.trueFartlekIrregularRun
        let buckets = fixture.toBucketData()

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "Unstructured Fartlek must detect >= 3 cycles")

        let regularity = await engine.calculateCycleRegularity(cycles: cycles)
        XCTAssertLessThan(regularity, 0.65, "Irregular surge durations must produce regularity < 0.65")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.14,
            slope: 0.0,
            zone4: 0.40,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.042,
            averageHR: 154.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_FadingCadenceFatigueRun() async {
        let fixture = GoldenTelemetryFixtures.fadingCadenceFatigueRun
        let buckets = fixture.toBucketData()

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "Continuous run with gradual fatigue must not detect intermittent cycles")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.045,
            slope: 0.25,
            zone4: 0.25,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.025,
            averageHR: 148.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_PyramidsLadderRun() async {
        let fixture = GoldenTelemetryFixtures.authenticPyramidsLadder
        let buckets = fixture.toBucketData()

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "Pyramids ladder must detect >= 3 oscillation cycles")

        let symmetry = await engine.calculateWorkBlockSymmetry(cycles: cycles)
        XCTAssertGreaterThanOrEqual(symmetry, 0.70, "Pyramids ladder must exhibit workBlockSymmetry >= 0.70, got \(symmetry)")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.14,
            slope: 0.0,
            zone4: 0.45,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.045,
            averageHR: 156.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_UrbanTrafficCrosswalkRun() async {
        let fixture = GoldenTelemetryFixtures.urbanTrafficCrosswalkRun
        let buckets = fixture.toBucketData()

        let entropy = await engine.detectUrbanTrafficEntropy(buckets: buckets)
        XCTAssertGreaterThanOrEqual(entropy, 0.04, "Chaotic crosswalk pauses must produce urban traffic entropy")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.14,
            slope: 0.0,
            zone4: 0.10,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.035,
            averageHR: 145.0,
            deadStopsCount: 4
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testGoldenFixtures_HillRepeatsSawtooth() async {
        let fixture = GoldenTelemetryFixtures.authenticHillRepeatsSawtooth
        let buckets = fixture.toBucketData()

        let isHills = await engine.detectHillRepeats(buckets: buckets)
        XCTAssertTrue(isHills, "Authentic sawtooth climb episodes must be recognized as hill repeats")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.08,
            slope: 0.0,
            zone4: 0.40,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.030,
            averageHR: 155.0
        )
        XCTAssertEqual(classification, fixture.expectedClassification)
    }

    func testRecoveryFloor_WalkingRestIntervalsVsJoggingRecoveryFartlek() async {
        // Construct 3 cycles with walking rest (cadence = 90 SPM during recovery)
        let walkingCycles = [
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 90, workPace: 300, recoveryPace: 550, workHR: 165, recoveryHR: 130, isCorroborated: true),
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 90, workPace: 300, recoveryPace: 550, workHR: 165, recoveryHR: 130, isCorroborated: true),
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 90, workPace: 300, recoveryPace: 550, workHR: 165, recoveryHR: 130, isCorroborated: true)
        ]
        let walkingFloor = await engine.calculateRecoveryCadenceFloor(buckets: [], cycles: walkingCycles)
        XCTAssertLessThan(walkingFloor, 120.0, "Walking recovery floor must be < 120 SPM")

        // Construct 3 cycles with active jogging recovery (cadence = 142 SPM during recovery)
        let joggingCycles = [
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 142, workPace: 300, recoveryPace: 480, workHR: 165, recoveryHR: 145, isCorroborated: true),
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 142, workPace: 300, recoveryPace: 480, workHR: 165, recoveryHR: 145, isCorroborated: true),
            SurgeRecoveryCycle(workDuration: 60, recoveryDuration: 60, workCadence: 175, recoveryCadence: 142, workPace: 300, recoveryPace: 480, workHR: 165, recoveryHR: 145, isCorroborated: true)
        ]
        let joggingFloor = await engine.calculateRecoveryCadenceFloor(buckets: [], cycles: joggingCycles)
        XCTAssertGreaterThanOrEqual(joggingFloor, 135.0, "Jogging recovery floor must be >= 135 SPM")
    }

    func testNoiseResilience_IntervalsUnderSensorJitter() async {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let cleanBuckets = fixture.toBucketData()

        // Test across 3 distinct random seeds
        let seeds: [UInt64] = [101, 202, 303]
        for seed in seeds {
            let noisyBuckets = TelemetryNoiseInjector.injectSensorJitter(
                to: cleanBuckets,
                cadenceNoiseRange: -1.2...1.2,
                hrNoiseRange: -1.5...1.5,
                paceNoiseRange: -3.0...3.0,
                seed: seed
            )

            let cycles = await engine.extractOscillationCycles(buckets: noisyBuckets)
            XCTAssertGreaterThanOrEqual(
                cycles.count,
                3,
                "Intervals must remain robustly detected under sensor noise (seed: \(seed))"
            )

            let classification = await engine.classifyRun(
                buckets: noisyBuckets,
                cv: 0.16,
                slope: -0.30,
                zone4: 0.60,
                durationMinutes: fixture.durationMinutes,
                cadenceCV: 0.045,
                averageHR: 156.0
            )
            XCTAssertEqual(classification, "Intervals", "Classification must remain Intervals under noise (seed: \(seed))")
        }
    }

    func testNoiseResilience_HillySteadyUnderSensorJitter() async {
        let fixture = GoldenTelemetryFixtures.hillySteadyAerobicRun
        let cleanBuckets = fixture.toBucketData()

        let noisyBuckets = TelemetryNoiseInjector.injectSensorJitter(
            to: cleanBuckets,
            cadenceNoiseRange: -2.0...2.0,
            hrNoiseRange: -2.0...2.0,
            paceNoiseRange: -4.0...4.0,
            seed: 777
        )

        let cycles = await engine.extractOscillationCycles(buckets: noisyBuckets)
        XCTAssertLessThan(
            cycles.count,
            3,
            "Sensor jitter on hilly terrain must not create phantom oscillation cycles"
        )
    }

    // MARK: - 3. Adversarial Mutation & Guardrail Sensitivity

    func testAdversarialMutation_FlattenedPaceSurges_FailsIntervalClassification() async {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let buckets = fixture.toBucketData()

        // Mutate: Keep high cadence, but flatten pace to steady 440 s/km (no pace surge)
        let mutatedBuckets = buckets.map { bucket in
            BucketData(
                startTime: bucket.startTime,
                distanceMeters: bucket.distanceMeters,
                durationSeconds: bucket.durationSeconds,
                meanPaceSecPerKm: 440.0, // flattened pace
                meanCadence: bucket.meanCadence,
                meanHR: bucket.meanHR
            )
        }

        let cycles = await engine.extractOscillationCycles(buckets: mutatedBuckets)
        XCTAssertLessThan(
            cycles.count,
            3,
            "Cadence variations without corroborated pace surges must fail cycle validation"
        )
    }

    func testAdversarialMutation_HighVarianceProgression_FailsProgressionGuardrail() async {
        let fixture = GoldenTelemetryFixtures.monotonicProgressionRun
        let buckets = fixture.toBucketData()

        // Accelerating quintiles are true, but pace variance is high (cv = 0.12 >= 0.09)
        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.12, // High variance violates continuous progression guardrail
            slope: -0.35,
            zone4: 0.35,
            durationMinutes: fixture.durationMinutes,
            cadenceCV: 0.040,
            averageHR: 152.0
        )

        XCTAssertNotEqual(
            classification,
            "Progression Run",
            "High pace variance (CV >= 0.09) must prevent misclassification as Progression Run"
        )
    }

    // MARK: - 4. Biomechanical Fatigue Sensitivity

    func testFatigueSensitivity_TurnoverDecayAndCardiacDrift() {
        let fixture = GoldenTelemetryFixtures.fadingCadenceFatigueRun
        let halfCount = fixture.samples.count / 2
        let firstHalf = Array(fixture.samples.prefix(halfCount))
        let secondHalf = Array(fixture.samples.suffix(halfCount))

        let avgCadence1 = firstHalf.reduce(0.0) { $0 + $1.meanCadence } / Double(firstHalf.count)
        let avgCadence2 = secondHalf.reduce(0.0) { $0 + $1.meanCadence } / Double(secondHalf.count)
        let cadenceDecay = avgCadence1 - avgCadence2

        let avgHR1 = firstHalf.reduce(0.0) { $0 + $1.meanHR } / Double(firstHalf.count)
        let avgHR2 = secondHalf.reduce(0.0) { $0 + $1.meanHR } / Double(secondHalf.count)
        let hrDrift = avgHR2 - avgHR1

        // Verify that the fading run fixture models genuine fatigue exceeding our tactical coach thresholds
        XCTAssertGreaterThanOrEqual(cadenceDecay, 3.5, "Fatigue fixture must exhibit turnover decay >= 3.5 SPM")
        XCTAssertGreaterThanOrEqual(hrDrift, 5.0, "Fatigue fixture must exhibit cardiac drift >= 5.0 BPM")
    }

    // MARK: - 5. JSON Serialization Round-Trip

    func testJSONRoundTripSerialization() throws {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let data = try fixture.toJSONData()

        let decoded = try WorkoutTelemetryFixture.fromJSONData(data)
        XCTAssertEqual(decoded.id, fixture.id)
        XCTAssertEqual(decoded.name, fixture.name)
        XCTAssertEqual(decoded.expectedClassification, fixture.expectedClassification)
        XCTAssertEqual(decoded.samples.count, fixture.samples.count)
        XCTAssertEqual(decoded.samples[0].meanCadence, fixture.samples[0].meanCadence, accuracy: 0.001)
    }
}
