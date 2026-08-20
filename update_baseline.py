import sys

file_path = "Runalyzer/Models/RunRecord.swift"

with open(file_path, "r") as f:
    contents = f.read()

# Add BaselineStats struct
stats_struct = """
struct BaselineStats: Sendable {
    let avgDistance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
}
"""
contents = contents + stats_struct

# Add thirtyDayBaseline static func to RunRecord
baseline_func = """
extension RunRecord {
    static func thirtyDayBaseline(from targetDate: Date, in context: ModelContext) -> BaselineStats? {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else { return nil }

        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        let minDistanceRaw = UserDefaults.standard.object(forKey: "minimumRunDistance") as? Double ?? 1.0
        let minDistanceInMeters = useMetricSystem ? (minDistanceRaw * 1000.0) : (minDistanceRaw * 1609.344)
        let minDistanceThreshold = minDistanceInMeters - 0.01

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.distance >= minDistanceThreshold }
        )

        guard let validRuns = try? context.fetch(descriptor), validRuns.count >= 3 else {
            return nil
        }

        let avgDistance = validRuns.map { $0.distance }.reduce(0, +) / Double(validRuns.count)
        let avgPace = validRuns.map { $0.avgPace }.reduce(0, +) / Double(validRuns.count)
        let avgHeartRate = validRuns.map { $0.avgHeartRate }.reduce(0, +) / validRuns.count
        let avgCadence = validRuns.map { $0.avgCadence }.reduce(0, +) / validRuns.count

        return BaselineStats(avgDistance: avgDistance, avgPace: avgPace, avgHeartRate: avgHeartRate, avgCadence: avgCadence)
    }
}
"""
contents = contents + baseline_func

# Remove old extension Array where Element == RunRecord
contents = contents.split("extension Array where Element == RunRecord")[0]

with open(file_path, "w") as f:
    f.write(contents)

print("Updated RunRecord.swift")
