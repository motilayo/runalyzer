import Foundation
import SwiftData

struct MacroQuery {
    static func rollingAverages(from records: [RunRecord], days: Int, currentDate: Date = Date()) -> (pace: Double, cadence: Double, heartRate: Double)? {
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -days, to: currentDate) else { return nil }

        let validRecords = records.filter { $0.date >= windowStart }
        guard !validRecords.isEmpty else { return nil }

        let avgPace = validRecords.map(\.avgPace).reduce(0, +) / Double(validRecords.count)
        let avgCadence = Double(validRecords.map(\.avgCadence).reduce(0, +)) / Double(validRecords.count)
        let avgHR = Double(validRecords.map(\.avgHeartRate).reduce(0, +)) / Double(validRecords.count)

        return (pace: avgPace, cadence: avgCadence, heartRate: avgHR)
    }
}
