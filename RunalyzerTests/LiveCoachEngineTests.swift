import XCTest
import HealthKit
import WorkoutKit
import WatchConnectivity

@testable import Runalyzer

@available(iOS 17.0, watchOS 10.0, *)
class MockWorkoutSession: WorkoutSessionProtocol {
    var state: HKWorkoutSessionState = .notStarted

    func start() {
        state = .running
    }

    func pause() {
        state = .paused
    }

    func end() {
        state = .ended
    }
}

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
        XCTAssertTrue(sut.shouldTriggerCorrectiveHaptic(currentSPM: 152, targetSPM: targetSPM))
        XCTAssertFalse(sut.shouldTriggerCorrectiveHaptic(currentSPM: 160, targetSPM: targetSPM))
        XCTAssertFalse(sut.shouldTriggerCorrectiveHaptic(currentSPM: 165, targetSPM: targetSPM))
    }

    func testHapticEnforcement_SilentMode() {
        // Arrange
        sut.silentModeEnabled = true
        let currentSPM = 152
        let targetSPM = 160

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

    func testWCSession_PayloadDecoding() {
        // Arrange
        let payload: [String: Any] = [
            "title": "Cadence Pyramids",
            "workReps": 4,
            "workDistance": 400.0,
            "targetSPM": 165
        ]

        // Act
        let drill = sut.decodePayload(payload)

        // Assert
        XCTAssertNotNil(drill)
        XCTAssertEqual(drill?.title, "Cadence Pyramids")
        XCTAssertEqual(drill?.workReps, 4)
        XCTAssertEqual(drill?.workDistance, 400.0)
        XCTAssertEqual(drill?.targetSPM, 165)
        XCTAssertEqual(sut.decodedDrill, drill)
    }

    func testWorkoutSession_StateTransitions() {
        // Arrange
        let mockSession = MockWorkoutSession()
        sut.workoutSession = mockSession

        // Assert Initial State
        XCTAssertEqual(mockSession.state, .notStarted)

        // Act
        sut.startRun()

        // Assert Active State
        XCTAssertEqual(mockSession.state, .running)
    }
}
