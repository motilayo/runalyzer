import XCTest
import HealthKit
@testable import Runalyzer

class MockHKWorkoutSession: HKWorkoutSessionProtocol {
    var state: HKWorkoutSessionState = .notStarted
    func startActivity(with date: Date?) {
        state = .running
    }
    func end() {
        state = .ended
    }
}

@available(iOS 17.0, watchOS 10.0, *)
final class WorkoutSessionTests: XCTestCase {

    func testWorkoutSession_StateTransitions() {
        let mockSession = MockHKWorkoutSession()
        let manager = WorkoutSessionManager()
        manager.session = mockSession

        XCTAssertEqual(mockSession.state, .notStarted)
        manager.startSession()
        XCTAssertEqual(mockSession.state, .running)
        manager.endSession()
        XCTAssertEqual(mockSession.state, .ended)
    }
}
