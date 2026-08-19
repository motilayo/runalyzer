import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("useMetricSystem") var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") var minimumRunDistance: Double = 1.0

    @Environment(\.modelContext) private var modelContext
    @Query private var allRuns: [RunRecord]

    var onForceSync: (() async -> Void)?

    @State private var isClearingCache = false
    @State private var isForceSyncing = false

    var body: some View {
        Form {
            Section(header: Text("Preferences")) {
                Toggle("Use Metric System", isOn: $useMetricSystem)

                VStack(alignment: .leading) {
                    Text("Minimum Workout Distance: \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
                    Slider(value: $minimumRunDistance, in: 0.5...10.0, step: 0.5)
                }
            }

            Section(header: Text("Data Management")) {
                Button(action: {
                    Task {
                        isForceSyncing = true
                        for run in allRuns {
                            modelContext.delete(run)
                        }
                        try? modelContext.save()

                        if let sync = onForceSync {
                            await sync()
                        }
                        isForceSyncing = false
                    }
                }) {
                    HStack {
                        Text("Force Re-Sync Health Data")
                        Spacer()
                        if isForceSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isForceSyncing || isClearingCache)

                Button(action: {
                    isClearingCache = true
                    for run in allRuns {
                        run.insight = nil
                    }
                    try? modelContext.save()
                    isClearingCache = false
                }) {
                    HStack {
                        Text("Clear AI Insights Cache")
                            .foregroundColor(.red)
                        Spacer()
                        if isClearingCache {
                            ProgressView()
                        }
                    }
                }
                .disabled(isForceSyncing || isClearingCache)
            }
        }
        .navigationTitle("Settings")
    }
}
