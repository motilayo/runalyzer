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
}
