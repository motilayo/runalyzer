import XCTest
@testable import Runalyst

@MainActor
final class LiveCoachEngineTests: XCTestCase {
    var engine: LiveCoachEngine!

    override func setUp() async throws {
        engine = LiveCoachEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    func testTranslatePrescription_ValidPattern() {
        let workout = engine.translate(prescription: "4x400m intervals", targetSPM: 165)
        XCTAssertNotNil(workout)
        XCTAssertEqual(workout?.displayName, "AI Prescribed Workout")
        XCTAssertEqual(workout?.activity, .running)
        XCTAssertEqual(workout?.location, .outdoor)
        XCTAssertEqual(workout?.blocks.count, 1)
        XCTAssertEqual(workout?.blocks.first?.iterations, 4)
        XCTAssertEqual(workout?.blocks.first?.steps.count, 2)
    }

    func testTranslatePrescription_InvalidPattern_ReturnsNil() {
        let workout = engine.translate(prescription: "steady recovery jog", targetSPM: 150)
        XCTAssertNil(workout)
    }

    func testMetronome_StateAndSilentMode() {
        engine.silentModeEnabled = true
        engine.startMetronome(targetSPM: 160)
        engine.stopMetronome()
        XCTAssertTrue(engine.silentModeEnabled)

        engine.silentModeEnabled = false
        engine.startMetronome(targetSPM: 0)
        engine.stopMetronome()
    }
}
