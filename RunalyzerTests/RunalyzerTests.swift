import XCTest
@testable import Runalyzer

final class RunalyzerTests: XCTestCase {

    func testPaceCalculation() throws {
        // Distance: 5 km (5000 meters)
        // Duration: 25 minutes (1500 seconds)
        // Pace should be 5.00 min/km

        let duration: TimeInterval = 1500
        let distance: Double = 5000

        let pace = HealthKitManager.calculatePace(duration: duration, distance: distance)
        XCTAssertEqual(pace, 5.0, accuracy: 0.01)
    }

    func testCadenceCalculation() throws {
        // Duration: 25 minutes (1500 seconds)
        // Steps: 4000
        // Cadence should be 160 SPM

        let duration: TimeInterval = 1500
        let steps: Double = 4000

        let cadence = HealthKitManager.calculateCadence(duration: duration, steps: steps)
        XCTAssertEqual(cadence, 160)
    }
}
