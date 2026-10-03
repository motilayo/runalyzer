import XCTest
import WorkoutKit
@testable import Runalyst

final class WorkoutPlanTests: XCTestCase {
    func testDrillWorkoutPlans() {
        for id in PreRunDrillId.allCases {
            let drill = PreRunDrill(id: id, previousCadence: 160)
            _ = drill.buildWorkoutPlan()
            print("Successfully built plan for \(id.rawValue)")
        }

        let alertThreshold = CadenceThresholdAlert.cadence(160.0)
        XCTAssertTrue(CustomWorkout.supportsAlert(alertThreshold, activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(3, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(2, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(1, .minutes), activity: .running, location: .outdoor))
        let hrZoneAlert = HeartRateZoneAlert(zone: 2)
        print("HR ZONE 2 SUPPORTS: \(CustomWorkout.supportsAlert(hrZoneAlert, activity: .running, location: .outdoor))")
    }

    func testZone2RunWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .zone2Run, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .zone2Run)
        XCTAssertEqual(template.title, "Zone 2 Run")
        XCTAssertEqual(template.defaultEffort, "Zone 2 Aerobic")
    }

    func testAerobicFlushWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .aerobicFlush, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .aerobicFlush)
        XCTAssertEqual(template.title, "Aerobic Flush")
        XCTAssertEqual(template.defaultEffort, "Zone 1 Active Recovery")
    }

    func testWorkoutPhaseTimelineGeneration() {
        // Strides 15 min: Warmup (5m) + 6 x (20s work + 60s walk) + Cooldown (2m)
        let stridesDrill = PreRunDrill(id: .strides, duration: .fifteenMinutes)
        let stridesPhases = stridesDrill.generatePhases()

        XCTAssertFalse(stridesPhases.isEmpty)
        XCTAssertEqual(stridesPhases.first?.kind, .warmup)
        XCTAssertEqual(stridesPhases.first?.durationSeconds, 300)
        XCTAssertEqual(stridesPhases.first?.formattedDuration, "5m")

        let workPhases = stridesPhases.filter { $0.kind == .work }
        let recPhases = stridesPhases.filter {
            if case .recovery = $0.kind { return true }
            return false
        }
        XCTAssertEqual(workPhases.count, 6)
        XCTAssertEqual(recPhases.count, 6)
        XCTAssertEqual(workPhases.first?.durationSeconds, 20)
        XCTAssertEqual(recPhases.first?.durationSeconds, 60)
        XCTAssertEqual(recPhases.first?.name, "Walk")

        XCTAssertEqual(stridesPhases.last?.kind, .cooldown)
        XCTAssertEqual(stridesPhases.last?.durationSeconds, 120)

        // All drill cases across durations generate non-empty phases
        for drillId in PreRunDrillId.allCases {
            for duration in DrillDuration.allCases {
                let drill = PreRunDrill(id: drillId, duration: duration)
                let phases = drill.generatePhases()
                XCTAssertFalse(phases.isEmpty, "Phases should not be empty for \(drillId) at \(duration)")
                XCTAssertTrue(phases.allSatisfy { $0.durationSeconds > 0 })
            }
        }
    }
}
