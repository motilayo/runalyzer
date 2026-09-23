import XCTest
import SwiftData
@testable import Runalyst

@MainActor
final class CoachingEngineDataTests: XCTestCase {
    func testRunDataForAIInitialization() {
        let runData = RunDataForAI(
            workoutType: "Tempo Run",
            runnerGoal: "Sub-20 5K",
            directiveContext: "The runner is overstriding (low cadence).",
            paceContext: "Current: 5:00/km, Baseline: 5:15/km",
            hrContext: "Current: 155 BPM, Baseline: 150 BPM",
            cadenceContext: "Current: 148 SPM, Baseline: 156 SPM",
            zone4Context: "20% in Zone 4",
            cvContext: "0.045",
            slopeContext: "0.012",
            intervalCadence: "162",
            recoveryCadence: "150"
        )

        XCTAssertEqual(runData.workoutType, "Tempo Run")
        XCTAssertEqual(runData.runnerGoal, "Sub-20 5K")
        XCTAssertEqual(runData.intervalCadence, "162")
        XCTAssertEqual(runData.recoveryCadence, "150")
        XCTAssertTrue(runData.directiveContext.contains("overstriding"))
        XCTAssertTrue(runData.paceContext.contains("5:00/km"))
        XCTAssertTrue(runData.hrContext.contains("155 BPM"))
        XCTAssertTrue(runData.cadenceContext.contains("148 SPM"))
        XCTAssertTrue(runData.zone4Context.contains("20%"))
        XCTAssertTrue(runData.cvContext.contains("0.045"))
        XCTAssertTrue(runData.slopeContext.contains("0.012"))
    }

    func testAggregateRunDataForAIInitialization() {
        let aggData = AggregateRunDataForAI(
            paceContext: "5:10/km",
            hrContext: "148 BPM",
            cadenceContext: "162 SPM",
            zone4Context: "15%",
            cvContext: "0.035",
            slopeContext: "-0.010",
            stageContext: "Stage 2: Aerobic Expansion"
        )

        XCTAssertEqual(aggData.stageContext, "Stage 2: Aerobic Expansion")
    }

    func testBaselineStatsInitialization() {
        let stats = BaselineStats(avgPace: 300, avgCadence: 165, avgHR: 145, avgOscillation: 9.5)
        XCTAssertEqual(stats.avgPace, 300)
        XCTAssertEqual(stats.avgCadence, 165)
        XCTAssertEqual(stats.avgHR, 145)
        XCTAssertEqual(stats.avgOscillation, 9.5)
    }

    func testSparseRunBiometricGuardrail() async throws {
        if #available(iOS 26.0, *) {
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            let runId: PersistentIdentifier = {
                let context = container.mainContext
                let sparseRun = RunRecord(
                    hkWorkoutID: UUID(),
                    date: Date(),
                    totalDistanceMeters: 5000,
                    duration: 2700,
                    rawAvgPace: 540,
                    rawAvgHeartRate: 0,
                    rawAvgCadence: 0,
                    workingAvgPace: 540,
                    workingAvgCadence: 0,
                    workingAvgHeartRate: 0,
                    workingAvgVerticalOscillation: nil,
                    rawAvgVerticalOscillation: nil,
                    workingDistanceMeters: 5000,
                    workingDurationSeconds: 2700,
                    paceCV: 0.04,
                    paceSlope: 0.0,
                    percentZone4: 0.0,
                    detectedTypeRaw: "Easy Run",
                    framboiseTags: []
                )
                context.insert(sparseRun)
                try? context.save()
                return sparseRun.persistentModelID
            }()

            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId)

            let fetched = container.mainContext.model(for: runId) as? RunRecord
            XCTAssertNil(fetched?.insight, "Runs lacking cadence and heart rate should not generate an AI insight")
        }
    }
}
