import Foundation
import WatchConnectivity
import SwiftData
import HealthKit

@available(iOS 17.0, watchOS 10.0, *)
public class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchConnectivityManager()

    // To handle SwiftData operations on main actor without being tied to view


    @MainActor public var sharedModelContext: ModelContext?

    #if os(watchOS)
    public var stashedRemoteDrill: DrillRecommendationDTO?
    #endif


    public var isWatchAppInstalled: Bool {
        #if os(iOS)
        if WCSession.isSupported() {
            let session = WCSession.default
            return session.isPaired && session.isWatchAppInstalled
        }
        #endif
        return false
    }


    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif


    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let runRecordData = message["completedRun"] as? Data {
            let decoder = JSONDecoder()
            if let dto = try? decoder.decode(RunRecordDTO.self, from: runRecordData) {
                Task { @MainActor in
                    if let context = self.sharedModelContext {
                        _ = try? await saveRunRecord(from: dto, context: context)
                    }
                }
            }
        }

        #if os(watchOS)
        if let drillData = message["drillDTO"] as? Data {
            let decoder = JSONDecoder()
            if let dto = try? decoder.decode(DrillRecommendationDTO.self, from: drillData) {
                DispatchQueue.main.async {
                    // Stash the incoming drill globally to intercept when handle(_ workoutConfiguration) fires.
                    self.stashedRemoteDrill = dto
                }
            }
        }
        #endif
    }



    #if os(iOS)
    public func startRemoteDrill(from drill: DrillRecommendation) async {
        guard isWatchAppInstalled else { return }

        let dto = DrillRecommendationDTO(
            drillTitle: drill.drillTitle,
            drillPurpose: drill.drillPurpose,
            drillWork: drill.drillWork,
            drillCues: drill.drillCues,
            drillEffort: drill.drillEffort,
            drillRecovery: drill.drillRecovery,
            targetCadence: drill.targetCadence
        )

        if let data = try? JSONEncoder().encode(dto) {
            WCSession.default.sendMessage(["drillDTO": data], replyHandler: nil) { error in
                print("Error sending drill DTO: \(error.localizedDescription)")
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor

            do {
                try await HKHealthStore().startWatchApp(with: configuration)
            } catch {
                print("Failed to start watch app: \(error.localizedDescription)")
            }
        }
    }
    #endif

    @MainActor
    @discardableResult
    public func saveRunRecord(from dto: RunRecordDTO, context: ModelContext) async throws -> RunRecord {
        let record = RunRecord(
            id: dto.id,
            date: dto.date,
            distance: dto.distance,
            duration: dto.duration,
            avgPace: dto.avgPace,
            avgHeartRate: dto.avgHeartRate,
            avgCadence: dto.avgCadence,
            verticalOscillation: dto.verticalOscillation,
            groundContactTime: dto.groundContactTime,
            strideLength: dto.strideLength
        )
        context.insert(record)
        try context.save()
        return record
    }
}
