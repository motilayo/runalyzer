import XCTest
import HealthKit
@testable import Runalyst

final class SafeTargetCalculatorTests: XCTestCase {
    func testSafeCadenceTarget() {
        let unit = HKUnit.count().unitDivided(by: .minute())

        // Requested normal cadence
        let target1 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 165, previousCadence: 160)
        XCTAssertEqual(target1?.doubleValue(for: unit), 165)

        // Requested extremely high cadence (should be clamped to 185)
        let target2 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 200, previousCadence: 160)
        XCTAssertEqual(target2?.doubleValue(for: unit), 185)

        // Requested lower than previous cadence (should be clamped to floor of previous)
        let target3 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: 140, previousCadence: 160)
        XCTAssertEqual(target3?.doubleValue(for: unit), 160)

        // No requested cadence
        let target4 = SafeTargetCalculator.safeCadenceTarget(requestedCadence: nil, previousCadence: 160)
        XCTAssertNil(target4)
    }
}
