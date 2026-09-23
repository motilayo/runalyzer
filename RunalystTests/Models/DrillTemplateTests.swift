import XCTest
@testable import Runalyst

final class DrillTemplateTests: XCTestCase {
    func testDrillTemplateBaselinesAndCueInterpolation() {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let thirtyDayCadence = 151
        let computedTarget = template.calculateTargetCadence(thirtyDayCadence)

        // Target should be calculated strictly from the 30-day baseline (151 * 1.05 = 158), returning a range 155-161
        XCTAssertEqual(computedTarget, "155-161")

        // Instructional cues provide prescriptive biomechanical focus
        let cue = template.generateInstructionalCue(computedTarget)
        XCTAssertFalse(cue.isEmpty, "Instructional cue should be present")
        XCTAssertFalse(cue.contains("151 SPM"), "Instructional cue must not repeat the raw baseline")
    }
}
