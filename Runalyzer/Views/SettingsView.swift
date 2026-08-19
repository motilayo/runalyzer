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
    @State private var showingClearCacheDialog = false
    @State private var showingReSyncDialog = false

    var body: some View {
        Form {
            Section(header: Text("Preferences")) {
                Toggle("Use Metric System", isOn: $useMetricSystem)
                    .onChange(of: useMetricSystem) { _, _ in
                        clearAICache()

                        // Adjust slider bounds if switching systems
                        if useMetricSystem {
                            if minimumRunDistance < 0.5 { minimumRunDistance = 0.5 }
                            if minimumRunDistance > 10.0 { minimumRunDistance = 10.0 }
                        } else {
                            if minimumRunDistance < 0.3 { minimumRunDistance = 0.3 }
                            if minimumRunDistance > 6.0 { minimumRunDistance = 6.0 }
                        }
                    }

                VStack(alignment: .leading) {
                    Text("Minimum Workout Distance: \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
                    if useMetricSystem {
                        Slider(value: $minimumRunDistance, in: 0.5...10.0, step: 0.5)
                    } else {
                        Slider(value: $minimumRunDistance, in: 0.3...6.0, step: 0.1)
                    }
                }
            }

            Section(header: Text("Data Management")) {
                Button(action: {
                    showingReSyncDialog = true
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
                .confirmationDialog("Re-Sync Health Data?", isPresented: $showingReSyncDialog, titleVisibility: .visible) {
                    Button("Re-Sync Data", role: .destructive) {
                        forceReSync()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will clear local run records and re-fetch them from HealthKit.")
                }

                Button(action: {
                    showingClearCacheDialog = true
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
                .confirmationDialog("Clear AI Cache?", isPresented: $showingClearCacheDialog, titleVisibility: .visible) {
                    Button("Clear Cache", role: .destructive) {
                        clearAICache()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will remove all generated insights. They will be regenerated the next time you view each workout.")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func forceReSync() {
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
    }

    private func clearAICache() {
        isClearingCache = true
        for run in allRuns {
            run.insight = nil
        }
        try? modelContext.save()
        isClearingCache = false
    }
}
