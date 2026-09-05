import Foundation
import SwiftData

struct FetchDescriptorBuilder {
    static func build(showLast30Days: Bool, minimumDistance: Double, useMetricSystem: Bool = true, currentDate: Date = Date()) -> FetchDescriptor<RunRecord> {
        let minDistanceMeters = useMetricSystem ? (minimumDistance * 1000.0) : (minimumDistance * 1609.344)

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: currentDate) ?? Date()

        if showLast30Days {
            return FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { run in
                    run.distance >= minDistanceMeters && run.date >= thirtyDaysAgo
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            return FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { run in
                    run.distance >= minDistanceMeters
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        }
    }
}
