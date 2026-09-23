import XCTest
@testable import Runalyst

final class CardiacGuardrailTests: XCTestCase {
    func testCardiacGuardrailHighHR() async {
        let framboise = FramboiseEngine()

        // High HR run (175 BPM, zone 4 = 0.5) must never be classified as Easy Run or Recovery Run
        let highHRClass = await framboise.classifyRun(cv: 0.04, slope: -0.1, zone4: 0.5, durationMinutes: 30, averageHR: 175)
        XCTAssertNotEqual(highHRClass, "Easy Run")
        XCTAssertNotEqual(highHRClass, "Recovery Run")
        XCTAssertTrue(highHRClass == "Tempo Run" || highHRClass == "Intervals" || highHRClass == "Progression Run" || highHRClass == "Steady Effort")

        // Low HR run (125 BPM, zone 4 = 0.04, duration 45 min) is Easy Run
        let lowHRClass = await framboise.classifyRun(cv: 0.04, slope: -0.1, zone4: 0.04, durationMinutes: 45, averageHR: 125)
        XCTAssertEqual(lowHRClass, "Easy Run")
    }
}
