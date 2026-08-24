import SwiftUI
import SwiftData

/// The settings and configuration view for the Runalyzer application.
///
/// `SettingsView` allows users to toggle metric/imperial units, adjust the minimum run distance filter,
/// force re-synchronization with HealthKit, and clear the AI insights cache.
struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0

    @Environment(\.modelContext) private var modelContext
    @Query private var runRecords: [RunRecord]

    var onForceSync: (() async -> Void)?

    @State private var showSyncAlert = false
    @State private var showClearCacheAlert = false

    var body: some View {
        Form {
            Section(header: Text("Preferences")) {
                Toggle("Use Metric System", isOn: $useMetricSystem)
                    .onChange(of: useMetricSystem) { _, _ in
                        Task {
                            for run in runRecords {
                                run.insight = nil
                            }
                            try? modelContext.save()
                        }
                    }

                VStack(alignment: .leading) {
                    Text("Minimum Workout Distance: \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
                    Slider(value: $minimumRunDistance, in: useMetricSystem ? 0.5...10.0 : 0.3...6.0, step: 0.1)
                }
            }

            Section(header: Text("Data Management")) {
                Button(role: .destructive, action: {
                    showSyncAlert = true
                }) {
                    Text("Force Re-Sync Health Data")
                }
                .alert("Force Re-Sync", isPresented: $showSyncAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Re-Sync", role: .destructive) {
                        Task {
                            // Clear all runs
                            for run in runRecords {
                                modelContext.delete(run)
                            }
                            try? modelContext.save()

                            // Trigger sync
                            if let onForceSync = onForceSync {
                                await onForceSync()
                            }
                        }
                    }
                } message: {
                    Text("This will delete all locally saved run records and re-fetch them from Apple Health. This cannot be undone.")
                }

                Button(role: .destructive, action: {
                    showClearCacheAlert = true
                }) {
                    Text("Clear AI Insights Cache")
                }
                .alert("Clear AI Cache", isPresented: $showClearCacheAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        Task {
                            for run in runRecords {
                                run.insight = nil
                            }
                            try? modelContext.save()
                        }
                    }
                } message: {
                    Text("This will clear all generated AI insights for your saved runs. New insights will be generated upon next sync.")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
