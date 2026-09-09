import SwiftUI
import SwiftData
import HealthKit
import WorkoutKit

struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @Environment(\.modelContext) private var modelContext
    @Query private var runRecords: [RunRecord]

    var onForceSync: ((Bool) async -> Void)?

    @State private var showSyncAlert = false
    @State private var showClearCacheAlert = false
    @State private var showResetModelAlert = false
    @State private var isSeeding = false
    @State private var seedingSuccess = false

    var body: some View {
        Form {
            // MARK: - Account
            Section(header: Text("Account")) {
                NavigationLink(destination: UserProfileView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("User Profile")
                            .font(.body)
                    }
                }
            }

            // MARK: - Preferences
            Section(header: Text("Preferences")) {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("Unit System")
                            .font(.body)
                    }
                    
                    Spacer()
                    
                    Picker("Unit System", selection: $useMetricSystem) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }

            // MARK: - Permissions & Sync
            Section(header: Text("Permissions & Sync")) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    Text("Apple Health Data")
                        .font(.body)
                    Spacer()
                    Text("Synced")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(red: 0.1, green: 0.6, blue: 0.6))
                }

                HStack(spacing: 12) {
                    Image(systemName: "applewatch")
                        .foregroundColor(.primary)
                        .font(.title3)
                    Text("WorkoutKit Handoff")
                        .font(.body)
                    Spacer()
                    Text("Granted")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(red: 0.1, green: 0.6, blue: 0.6))
                }
            }

            // MARK: - Data Management
            Section(
                header: Text("Data Management"),
                footer: Text("(Re-fetches recent workouts and rebuilds macro stats)")
            ) {
                Button(action: { showSyncAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("Resync Health Data")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .alert("Force Re-Sync", isPresented: $showSyncAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Re-Sync", role: .destructive) {
                        if let onForceSync = onForceSync {
                            Task { await onForceSync(true) }
                        }
                    }
                } message: {
                    Text("This will delete all locally saved run records and re-fetch them from Apple Health. This cannot be undone.")
                }

                #if DEBUG
                Button(action: {
                    isSeeding = true
                    Task {
                        await HealthKitSeeder.shared.seedCouchTo5K(context: modelContext)
                        if let onForceSync = onForceSync {
                            await onForceSync(false)
                        }
                        await MainActor.run {
                            isSeeding = false
                            seedingSuccess = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Seed Sample Health Data (Debug)")
                                .foregroundColor(.primary)
                            Text("Seeds 12 runs across all categories with full biometrics")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isSeeding {
                            ProgressView()
                        } else if seedingSuccess {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(isSeeding)
                #endif
            }

            // MARK: - Smart Coach (CoreML & AI)
            Section(
                header: Text("Smart Coach (CoreML & AI)"),
                footer: Text("Resetting the model deletes your local training queue and resets to baseline.")
            ) {
                Button(action: { showResetModelAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.pink)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset Personalization Model")
                                .foregroundColor(.primary)
                            Text("(Deletes local training queue and resets to baseline)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .alert("Reset Personalization Model", isPresented: $showResetModelAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        let descriptor = FetchDescriptor<TrainingCorrection>()
                        if let corrections = try? modelContext.fetch(descriptor) {
                            for item in corrections {
                                modelContext.delete(item)
                            }
                            try? modelContext.save()
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } message: {
                    Text("This resets the on-device runner classification queue back to baseline.")
                }

                Button(action: { showClearCacheAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear AI Insights Cache")
                                .foregroundColor(.primary)
                            Text("(Forces a fresh AI analysis on your next dashboard load)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .alert("Clear AI Cache", isPresented: $showClearCacheAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        for run in runRecords {
                            run.insight = nil
                        }
                        try? modelContext.save()
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_AllTime")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_AllTime")
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } message: {
                    Text("This clears all cached AI insights for your runs and dashboard. Fresh insights will generate automatically.")
                }
            }

            // MARK: - About
            Section {
                NavigationLink(destination: AboutRunalystView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("About Runalyst")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UserProfileView: View {
    var body: some View {
        Form {
            Section(header: Text("Runner Profile")) {
                HStack {
                    Text("Experience Level")
                    Spacer()
                    Text("Athlete / Competitor")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Weekly Target")
                    Spacer()
                    Text("25 - 40 km")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("User Profile")
    }
}

struct AboutRunalystView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Runalyst V2")
                    .font(.title.bold())
                
                Text("Runalyst is your proactive, AI-driven biomechanical coach designed to sit alongside your existing training schedule.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Key Pillars:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Pre-Run Biomechanical Primers", systemImage: "figure.run")
                    Label("Dynamic Rolling 30-Day Baselines", systemImage: "chart.xyaxis.line")
                    Label("On-Device Empathetic AI", systemImage: "sparkles")
                    Label("Reactive Form Correction", systemImage: "bolt.heart")
                    Label("Native Apple Watch WorkoutKit Handoff", systemImage: "applewatch")
                }
                .font(.subheadline)
                .foregroundColor(.primary)
                
                Divider()
                
                Text("AI-generated insights are for informational and training purposes only and do not replace professional medical or coaching advice.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("About Runalyst")
    }
}
