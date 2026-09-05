import Foundation
import HealthKit
#if os(watchOS)
import WatchKit

@available(watchOS 10.0, *)
public class ExtensionDelegate: NSObject, WKExtensionDelegate {

    public var sessionManager = WorkoutSessionManager()

    public func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let dto = WatchConnectivityManager.shared.stashedRemoteDrill ??
                  DrillRecommendationDTO(drillTitle: "Remote Session", drillPurpose: nil, drillWork: nil, drillCues: nil, drillEffort: nil, drillRecovery: nil, targetCadence: nil)

        do {
            try sessionManager.handleRemoteStart(configuration: workoutConfiguration, dto: dto)
        } catch {
            print("Failed to start remote workout session: \\(error.localizedDescription)")
        }
    }
}
#endif
