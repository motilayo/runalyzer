import SwiftUI
import SwiftData

/// A subview that accepts a dynamic FetchDescriptor and renders the filtered list of runs.
/// This prevents SwiftUI re-rendering loops while enabling dynamic filtering based on parent state.
struct RunListFilteredView: View {
    @Query private var runRecords: [RunRecord]

    init(descriptor: FetchDescriptor<RunRecord>) {
        _runRecords = Query(descriptor)
    }

    var body: some View {
        if runRecords.isEmpty {
            ContentUnavailableView(
                "No Runs Match Filters",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try adjusting your distance or time filters.")
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(runRecords) { run in
                    NavigationLink(value: run) {
                        RunListRowView(runRecord: run)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
