import XCTest
import HealthKit
import WorkoutKit

@testable import Runalyzer

@available(iOS 17.0, watchOS 10.0, *)
final class LiveCoachEngineTests: XCTestCase {

    var sut: LiveCoachEngine!

    override func setUp() {
        super.setUp()
        sut = LiveCoachEngine()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testWorkoutKit_IntervalTranslation() throws {
        // Arrange
        let prescription = "4x400m intervals"

        // Act
        let workout = try XCTUnwrap(sut.translate(prescription: prescription))

        // Assert
        // We should have 1 block with iterations = 4
        XCTAssertEqual(workout.blocks.count, 1)
        let block = workout.blocks[0]

        XCTAssertEqual(block.iterations, 4)
        XCTAssertEqual(block.steps.count, 2)

        let firstStep = block.steps[0]
        XCTAssertEqual(firstStep.purpose, .work)
        if case let .distance(dist, unit) = firstStep.step.goal {
            XCTAssertEqual(dist, 400.0)
            XCTAssertEqual(unit, .meter())
        } else {
            XCTFail("First step does not have a distance goal")
        }

        let secondStep = block.steps[1]
        XCTAssertEqual(secondStep.purpose, .recovery)
    }

    func testHapticEnforcement_TriggerLogic() {
        // Arrange
        let targetSPM = 160

        // Act & Assert
        // Current SPM is less than target, should trigger corrective haptic
        XCTAssertTrue(sut.shouldTriggerCorrectiveHaptic(currentSPM: 152, targetSPM: targetSPM))

        // Current SPM is equal to target, should not trigger
        XCTAssertFalse(sut.shouldTriggerCorrectiveHaptic(currentSPM: 160, targetSPM: targetSPM))

        // Current SPM is greater than target, should not trigger
        XCTAssertFalse(sut.shouldTriggerCorrectiveHaptic(currentSPM: 165, targetSPM: targetSPM))
    }

    func testHapticEnforcement_SilentMode() {
        // Arrange
        sut.silentModeEnabled = true
        let currentSPM = 152
        let targetSPM = 160 // Dropped cadence -> should haptic, but no audio

        // Act
        let cues = sut.triggerCues(currentSPM: currentSPM, targetSPM: targetSPM)

        // Assert
        XCTAssertFalse(cues.audio, "Audio should not be triggered when silent mode is enabled")
        XCTAssertTrue(cues.haptic, "Haptic should still be triggered in silent mode")
    }

    func testHapticEnforcement_NotSilentMode() {
        // Arrange
        sut.silentModeEnabled = false
        let currentSPM = 152
        let targetSPM = 160

        // Act
        let cues = sut.triggerCues(currentSPM: currentSPM, targetSPM: targetSPM)

        // Assert
        XCTAssertTrue(cues.audio, "Audio should be triggered when silent mode is disabled")
        XCTAssertTrue(cues.haptic, "Haptic should be triggered")
    }
}
