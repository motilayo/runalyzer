import Foundation
import HealthKit

public protocol HKWorkoutSessionProtocol {
    var state: HKWorkoutSessionState { get }
    func startActivity(with date: Date?)
    func end()
}

extension HKWorkoutSession: HKWorkoutSessionProtocol {}

@available(iOS 17.0, watchOS 10.0, *)
public class WorkoutSessionManager {
    public var session: HKWorkoutSessionProtocol?
    public var builder: HKLiveWorkoutBuilder?

    private let healthStore = HKHealthStore()

    public init() {}


    #if os(watchOS)
    public func handleRemoteStart(configuration: HKWorkoutConfiguration, dto: DrillRecommendationDTO) throws {
        let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        self.session = newSession
        self.builder = newSession.associatedWorkoutBuilder()
        self.builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        self.startSession()

        // Setup live coach engine with dto...
    }
    #endif

    public func setupSession() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        self.session = newSession
        self.builder = newSession.associatedWorkoutBuilder()

        self.builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
    }

    public func startSession() {
        session?.startActivity(with: Date())
        builder?.beginCollection(withStart: Date()) { success, error in
            if let error = error {
                print("Failed to begin collection: \(error.localizedDescription)")
            }
        }
    }

    public func endSession() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { success, error in
            if let error = error {
                print("Failed to end collection: \(error.localizedDescription)")
            }
            self.builder?.finishWorkout { workout, error in
                if let error = error {
                    print("Failed to finish workout: \(error.localizedDescription)")
                }
            }
        }
    }
}
