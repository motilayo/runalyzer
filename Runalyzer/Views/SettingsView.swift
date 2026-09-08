import SwiftUI
import SwiftData
import TipKit

struct WorkingAveragesTip: Tip {
    var title: Text {
        Text("Smart Core Engine")
    }
    var message: Text? {
        Text("Toggle between Working Averages (strips dead stops, warm-ups, and cool-downs) and Raw Apple Health Totals.")
    }
    var image: Image? {
        Image(systemName: "brain.head.profile")
    }
}


/// The settings and configuration view for the Runalyzer application.
///
/// `SettingsView` allows users to toggle metric/imperial units, adjust the minimum run distance filter,
/// force re-synchronization with HealthKit, and clear the AI insights cache.
struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0
    @AppStorage("useWorkingAverages") private var useWorkingAverages: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query private var runRecords: [RunRecord]

    var onForceSync: ((Bool) async -> Void)?

    @State private var showSyncAlert = false
    @State private var showClearCacheAlert = false

    var body: some View {
        Form {
            Section(header: Text("Smart Core")) {
                Toggle("Working Averages", isOn: $useWorkingAverages)
                    .popoverTip(WorkingAveragesTip())
            }

            Section(header: Text("Preferences"), footer: Text("Workouts shorter than this distance will be hidden from dashboard statistics and filtered run lists.")) {
                Toggle("Use Metric System", isOn: $useMetricSystem)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Minimum Workout Distance")
                        Spacer()
                        Text(String(format: "%.1f %@", minimumRunDistance, useMetricSystem ? "km" : "mi"))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $minimumRunDistance, in: useMetricSystem ? 0.0...10.0 : 0.0...6.0, step: 0.1)
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
                        // Trigger sync
                        if let onForceSync = onForceSync {
                            Task {
                                await onForceSync(true)
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
                        for run in runRecords where run.insight != nil {
                            run.insight = nil
                        }
                        try? modelContext.save()
                    }
                } message: {
                    Text("This will clear all generated AI insights for your saved runs. New insights will be generated upon next sync.")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
