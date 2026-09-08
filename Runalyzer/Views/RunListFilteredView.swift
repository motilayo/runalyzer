import SwiftUI
import SwiftData

/// A subview that accepts an array of filtered RunRecords and renders the list of runs.
/// This guarantees reactive updates when parent filter state changes.
struct RunListFilteredView: View {
    let runs: [RunRecord]

    init(runs: [RunRecord]) {
        self.runs = runs
    }

    init(descriptor: FetchDescriptor<RunRecord>) {
        self.runs = []
    }

    var body: some View {
        if runs.isEmpty {
            ContentUnavailableView(
                "No Runs Match Filters",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try adjusting your distance or time filters.")
            )
            .padding(.top, 40)
        } else {
            ForEach(runs) { run in
                NavigationLink(value: run) {
                    RunListRowView(runRecord: run)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
