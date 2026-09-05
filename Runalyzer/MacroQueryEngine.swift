import Foundation

public struct RollingAverages: Sendable {
    public let avgPace: Double
    public let avgCadence: Int
    public let avgHeartRate: Int

    public init(avgPace: Double, avgCadence: Int, avgHeartRate: Int) {
        self.avgPace = avgPace
        self.avgCadence = avgCadence
        self.avgHeartRate = avgHeartRate
    }
}

public class MacroQueryEngine {

    public init() {}

    public static func calculateRollingAverages(for records: [RunMetricsDTO], within days: Int) async -> RollingAverages {
        guard !records.isEmpty else { return RollingAverages(avgPace: 0, avgCadence: 0, avgHeartRate: 0) }

        let sortedRecords = records.sorted { $0.date > $1.date }
        guard let latestDate = sortedRecords.first?.date else { return RollingAverages(avgPace: 0, avgCadence: 0, avgHeartRate: 0) }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: latestDate) ?? Date()

        return await withTaskGroup(of: (Double, Int, Int).self) { group in
            var filteredRecords: [RunMetricsDTO] = []

            for record in records {
                if record.date >= cutoffDate && record.date <= latestDate {
                    filteredRecords.append(record)
                }
            }

            if filteredRecords.isEmpty {
                 return RollingAverages(avgPace: 0, avgCadence: 0, avgHeartRate: 0)
            }

            group.addTask {
                let paceSum = filteredRecords.map(\.avgPace).reduce(0, +)
                let hrSum = filteredRecords.map(\.avgHeartRate).reduce(0, +)
                let cadenceSum = filteredRecords.map(\.avgCadence).reduce(0, +)
                return (paceSum, cadenceSum, hrSum)
            }

            var totalPaceSum: Double = 0
            var totalCadenceSum: Int = 0
            var totalHRSum: Int = 0

            for await result in group {
                totalPaceSum += result.0
                totalCadenceSum += result.1
                totalHRSum += result.2
            }

            let avgPace = totalPaceSum / Double(filteredRecords.count)
            let avgHR = totalHRSum / filteredRecords.count
            let avgCadence = totalCadenceSum / filteredRecords.count

            return RollingAverages(avgPace: avgPace, avgCadence: avgCadence, avgHeartRate: avgHR)
        }
    }
}
