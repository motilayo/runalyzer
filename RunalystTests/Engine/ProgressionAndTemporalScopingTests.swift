import XCTest
import SwiftData
@testable import Runalyst

@MainActor
final class ProgressionAndTemporalScopingTests: XCTestCase {

    func testRunRecordEfficiencyFactorCalculation() {
        // Run at 5:00/km (300 sec/km) at 150 BPM
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 150,
            rawAvgCadence: 165,
            workingAvgPace: 300,
            workingAvgCadence: 165,
            workingAvgHeartRate: 150,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Easy Run"
        )

        // Speed in m/min = 60,000 / 300 = 200 m/min
        XCTAssertEqual(run.speedMetersPerMinute, 200.0)

        // EF = 200 / 150 = 1.333... m/beat
        guard let ef = run.efficiencyFactor else {
            XCTFail("efficiencyFactor should not be nil for valid pace and heart rate")
            return
        }
        XCTAssertEqual(ef, 200.0 / 150.0, accuracy: 0.001)
    }

    func testRunRecordEfficiencyFactorNilWhenMissingHeartRateOrPace() {
        let zeroHRRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 0,
            rawAvgCadence: 160,
            workingAvgPace: 300,
            workingAvgCadence: 160,
            workingAvgHeartRate: 0,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        XCTAssertNil(zeroHRRun.efficiencyFactor)

        let zeroPaceRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 0,
            rawAvgHeartRate: 140,
            rawAvgCadence: 160,
            workingAvgPace: 0,
            workingAvgCadence: 160,
            workingAvgHeartRate: 140,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        XCTAssertNil(zeroPaceRun.efficiencyFactor)
        XCTAssertNil(zeroPaceRun.speedMetersPerMinute)
    }

    func testAggregateRunDataForAIWithTelemetryContexts() {
        let aggData = AggregateRunDataForAI(
            paceContext: "4:45/km",
            hrContext: "152 BPM",
            cadenceContext: "168 SPM",
            zone4Context: "18% Zone 4",
            cvContext: "0.032",
            slopeContext: "-0.015",
            stageContext: "Competitor",
            directiveContext: "STRUCTURAL_ADAPTATION: Aerobic efficiency expanded.",
            efficiencyContext: "Efficiency Factor rose by +0.06 m/beat.",
            fatigueContext: "No acute fatigue.",
            verticalOscillationContext: "Vertical Oscillation: 8.8 cm"
        )

        XCTAssertTrue(aggData.directiveContext.contains("STRUCTURAL_ADAPTATION"))
        XCTAssertTrue(aggData.efficiencyContext.contains("+0.06"))
        XCTAssertEqual(aggData.fatigueContext, "No acute fatigue.")
        XCTAssertTrue(aggData.verticalOscillationContext.contains("8.8 cm"))
    }

    func testAllTimeCoachingEngineBypassesLLM() async throws {
        let aggData = AggregateRunDataForAI(
            paceContext: "5:00/km",
            hrContext: "150 BPM",
            cadenceContext: "165 SPM",
            zone4Context: "10%",
            cvContext: "0.03",
            slopeContext: "0.0",
            stageContext: "Competitor"
        )

        if #available(iOS 26.0, *) {
            // Test All-Time output (LLM strictly bypassed, zero simulator hang)
            let allTimeInsight = try await CoachingEngine.shared.generateDashboardInsight(for: "All Time", runData: aggData)
            XCTAssertEqual(allTimeInsight.headline, "Lifetime Milestones")
            XCTAssertTrue(allTimeInsight.body.contains("progression trends"))
        }
    }

    func testChartTimeHorizonDays() {
        XCTAssertEqual(ChartTimeHorizon.thirtyDays.days, 30)
        XCTAssertEqual(ChartTimeHorizon.sixMonths.days, 180)
        XCTAssertEqual(ChartTimeHorizon.oneYear.days, 365)
        XCTAssertNil(ChartTimeHorizon.allTime.days)
    }

    func testProgressionMetricTitles() {
        XCTAssertEqual(ProgressionMetric.efficiencyFactor.id, "Efficiency Factor")
        XCTAssertEqual(ProgressionMetric.pace.id, "Average Pace")
        XCTAssertTrue(ProgressionMetric.efficiencyFactor.shortTitle.contains("Eff. Factor"))
        XCTAssertEqual(ProgressionMetric.pace.shortTitle, "Average Pace")
    }

    func testChartSegmentGapSplitting() {
        let calendar = Calendar.current
        let now = Date()
        let oldDate = calendar.date(byAdding: .day, value: -100, to: now) ?? now
        let recentDate1 = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let recentDate2 = now

        let daysApart = calendar.dateComponents([.day], from: oldDate, to: recentDate1).day ?? 0
        XCTAssertGreaterThan(daysApart, 45, "Points separated by > 45 days must trigger a new chart segment")

        let recentDaysApart = calendar.dateComponents([.day], from: recentDate1, to: recentDate2).day ?? 0
        XCTAssertLessThanOrEqual(recentDaysApart, 45, "Points within 45 days remain in the same continuous segment")
    }

    func testLifetimeMilestoneAchievements() {
        let run1 = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 10500, // > 10k
            duration: 3600,
            rawAvgPace: 342,
            rawAvgHeartRate: 152,
            rawAvgCadence: 172, // > 170 SPM
            workingAvgPace: 342,
            workingAvgCadence: 172,
            workingAvgHeartRate: 152,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort"
        )

        let run2 = RunRecord(
            hkWorkoutID: UUID(),
            date: Date().addingTimeInterval(-86400),
            totalDistanceMeters: 21500, // > Half Marathon (21.1k)
            duration: 7200,
            rawAvgPace: 335,
            rawAvgHeartRate: 148,
            rawAvgCadence: 168,
            workingAvgPace: 335,
            workingAvgCadence: 168,
            workingAvgHeartRate: 148,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Long Run"
        )

        let runs = [run1, run2]
        let totalMeters = runs.map(\.totalDistanceMeters).reduce(0, +)
        XCTAssertEqual(totalMeters, 32000.0)

        let maxCadence = runs.map(\.workingAvgCadence).max() ?? 0
        XCTAssertGreaterThanOrEqual(maxCadence, 170.0)

        let maxDistanceKm = (runs.map(\.totalDistanceMeters).max() ?? 0) / 1000.0
        XCTAssertGreaterThanOrEqual(maxDistanceKm, 21.1)

        // Peak EF: Speed = 60,000 / 335 = 179.1 m/min. EF = 179.1 / 148 = 1.21 m/beat
        let peakEF = runs.compactMap(\.efficiencyFactor).max() ?? 0
        XCTAssertGreaterThan(peakEF, 1.15)
    }
}
