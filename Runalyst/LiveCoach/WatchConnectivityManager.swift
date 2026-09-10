import Foundation
import WatchConnectivity
import SwiftData

@available(iOS 17.0, watchOS 10.0, *)
public class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchConnectivityManager()

    // To handle SwiftData operations on main actor without being tied to view
    @MainActor public var sharedModelContext: ModelContext?

    override private init() {
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

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let runRecordData = message["completedRun"] as? Data {
            let decoder = JSONDecoder()
            if let dto = try? decoder.decode(WatchRunRecordDTO.self, from: runRecordData) {
                Task { @MainActor in
                    if let context = self.sharedModelContext {
                        _ = try? await saveRunRecord(from: dto, context: context)
                    }
                }
            }
        }
    }

    @MainActor
    @discardableResult
    func saveRunRecord(from dto: WatchRunRecordDTO, context: ModelContext) async throws -> RunRecord {
        let record = RunRecord(
            id: dto.id,
            hkWorkoutID: dto.id,
            date: dto.date,
            totalDistanceMeters: dto.distance,
            duration: dto.duration,
            rawAvgPace: dto.avgPace,
            rawAvgHeartRate: Double(dto.avgHeartRate),
            rawAvgCadence: Double(dto.avgCadence),
            workingAvgPace: dto.avgPace,
            workingAvgCadence: Double(dto.avgCadence),
            workingAvgHeartRate: Double(dto.avgHeartRate),
            workingAvgVerticalOscillation: dto.verticalOscillation,
            rawAvgVerticalOscillation: dto.verticalOscillation,
            paceCV: 0,
            paceSlope: 0,
            percentZone4: 0,
            detectedTypeRaw: "steady"
        )
        context.insert(record)
        try context.save()
        return record
    }
}
