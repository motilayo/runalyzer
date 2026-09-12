import SwiftUI
import SwiftData
import HealthKit
@preconcurrency import WorkoutKit

struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @Environment(\.modelContext) private var modelContext
    @Query private var runRecords: [RunRecord]

    var onForceSync: ((Bool) async -> Void)?

    @State private var showSyncAlert = false
    @State private var showResetModelAlert = false
    @State private var isSeeding = false
    @State private var seedingSuccess = false

    @State private var healthAuthStatus: String = "Checking..."
    @State private var workoutKitAuthStatus: String = "Checking..."
    @State private var canRequestHealth: Bool = false
    @State private var canRequestWorkoutKit: Bool = false
    @State private var showHealthSettingsAlert = false
    @State private var showWorkoutKitSettingsAlert = false

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
            Section(
                header: Text("Permissions & Sync"),
                footer: Text("Tap a permission to request access directly in the app.")
            ) {
                Button(action: {
                    Task {
                        let prevStatus = try? await HealthKitManager.shared.getRequestStatusForAuthorization()
                        do {
                            try await HealthKitManager.shared.requestAuthorization()
                            await updateHealthKitStatus()
                            if let onForceSync = onForceSync {
                                await onForceSync(false)
                            }
                        } catch {
                            print("Health authorization error: \(error.localizedDescription)")
                        }

                        if prevStatus == .unnecessary {
                            showHealthSettingsAlert = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                        Text("Apple Health Data")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(healthAuthStatus)
                            .font(.subheadline.bold())
                            .foregroundColor(healthAuthStatus == "Connected" ? Color(red: 0.1, green: 0.6, blue: 0.6) : (healthAuthStatus == "Not Connected" ? .orange : .secondary))
                    }
                }
                .alert("Apple Health Permissions", isPresented: $showHealthSettingsAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("HealthKit permissions are already configured. Runalyst has access to your workouts and running biometrics.")
                }

                Button(action: {
                    Task {
                        if #available(iOS 17.0, *) {
                            let prevState = await WorkoutScheduler.shared.authorizationState
                            _ = await WorkoutScheduler.shared.requestAuthorization()
                            await updateWorkoutKitStatus()
                            if prevState != .notDetermined {
                                showWorkoutKitSettingsAlert = true
                            }
                        } else {
                            showWorkoutKitSettingsAlert = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .foregroundColor(.primary)
                            .font(.title3)
                        Text("WorkoutKit Handoff")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(workoutKitAuthStatus)
                            .font(.subheadline.bold())
                            .foregroundColor(workoutKitAuthStatus == "Granted" ? Color(red: 0.1, green: 0.6, blue: 0.6) : (workoutKitAuthStatus == "Denied" ? .red : .secondary))
                    }
                }
                .alert("WorkoutKit Handoff", isPresented: $showWorkoutKitSettingsAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("WorkoutKit permission is already \(workoutKitAuthStatus.lowercased()) on this device.")
                }
            }

            // MARK: - Data Management
            Section(
                header: Text("Data Management"),
                footer: Text("Re-fetches recent workouts from Apple Health, wipes local records and cache, and regenerates fresh AI insights.")
            ) {
                Button(action: { showSyncAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("Resync Health Data & Rebuild AI Insights")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .alert("Resync & Rebuild Insights", isPresented: $showSyncAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Resync & Rebuild", role: .destructive) {
                        for run in runRecords {
                            modelContext.delete(run)
                        }
                        try? modelContext.save()
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_AllTime")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_AllTime")
                        if let onForceSync = onForceSync {
                            Task { await onForceSync(true) }
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } message: {
                    Text("This will delete all locally saved run records, clear cached AI insights, and re-fetch them from Apple Health. This cannot be undone.")
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
                            Text("Seeds 3 months of runs (38 runs) with beginner progression & aligned drills")
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
        .task {
            await refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshPermissions()
            }
        }
    }

    private func refreshPermissions() async {
        await updateHealthKitStatus()
        await updateWorkoutKitStatus()
    }

    private func updateHealthKitStatus() async {
        guard HealthKitManager.shared.isHealthDataAvailable() else {
            await MainActor.run {
                self.healthAuthStatus = "Unavailable"
                self.canRequestHealth = false
            }
            return
        }

        do {
            let status = try await HealthKitManager.shared.getRequestStatusForAuthorization()
            await MainActor.run {
                switch status {
                case .shouldRequest:
                    self.healthAuthStatus = "Not Connected"
                    self.canRequestHealth = true
                case .unnecessary:
                    self.healthAuthStatus = runRecords.isEmpty ? "Manage" : "Connected"
                    self.canRequestHealth = false
                case .unknown:
                    self.healthAuthStatus = "Manage"
                    self.canRequestHealth = false
                @unknown default:
                    self.healthAuthStatus = "Manage"
                    self.canRequestHealth = false
                }
            }
        } catch {
            await MainActor.run {
                self.healthAuthStatus = runRecords.isEmpty ? "Manage" : "Connected"
                self.canRequestHealth = false
            }
        }
    }

    private func updateWorkoutKitStatus() async {
        if #available(iOS 17.0, *) {
            let state = await WorkoutScheduler.shared.authorizationState
            await MainActor.run {
                switch state {
                case .authorized:
                    self.workoutKitAuthStatus = "Granted"
                    self.canRequestWorkoutKit = false
                case .denied, .restricted:
                    self.workoutKitAuthStatus = "Denied"
                    self.canRequestWorkoutKit = false
                case .notDetermined:
                    self.workoutKitAuthStatus = "Not Determined"
                    self.canRequestWorkoutKit = true
                @unknown default:
                    self.workoutKitAuthStatus = "Manage"
                    self.canRequestWorkoutKit = false
                }
            }
        } else {
            await MainActor.run {
                self.workoutKitAuthStatus = "Unavailable"
                self.canRequestWorkoutKit = false
            }
        }
    }
}

struct UserProfileView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = true
    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"

    let goalOptions = [
        "Base Building",
        "Injury Recovery",
        "5K Race",
        "10K Race",
        "Half Marathon",
        "Marathon",
        "Just for Fun"
    ]

    var body: some View {
        let metrics = calculateUserMetrics()

        Form {
            Section(header: Text("Runner Profile")) {
                Picker("Training Goal", selection: $trainingGoal) {
                    ForEach(goalOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                HStack {
                    Text("Experience Level")
                    Spacer()
                    Text(metrics.level)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Recent Weekly Volume")
                    Spacer()
                    Text(metrics.volume)
                        .foregroundColor(.secondary)
                }
            }

            Section(footer: Text("Runalyst automatically calculates your experience level and weekly volume based on your last 30 days of running data.")) {
                EmptyView()
            }
        }
        .navigationTitle("User Profile")
    }

    private func calculateUserMetrics() -> (level: String, volume: String) {
        guard !runRecords.isEmpty else {
            return ("Beginner / Novice", "0 \(useMetricSystem ? "km" : "mi")")
        }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo }

        let totalDistanceMeters = recentRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let weeklyAvgKm = totalDistanceKm / 4.28 // approx weeks in 30 days
        let runsPerWeek = Double(recentRuns.count) / 4.28

        let level: String
        if weeklyAvgKm > 60 {
            level = "Elite / Pro"
        } else if weeklyAvgKm > 35 {
            level = "Athlete / Competitor"
        } else if weeklyAvgKm > 15 || runsPerWeek >= 3 {
            level = "Intermediate / Enthusiast"
        } else {
            level = "Beginner / Novice"
        }

        let displayVolume: String
        if useMetricSystem {
            displayVolume = String(format: "%.1f km/wk", weeklyAvgKm)
        } else {
            displayVolume = String(format: "%.1f mi/wk", weeklyAvgKm * 0.621371)
        }

        return (level, displayVolume)
    }
}

struct AboutRunalystView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Hero
                VStack(spacing: 8) {
                    if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                       let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
                       let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                       let lastIcon = iconFiles.last,
                       let uiImage = UIImage(named: lastIcon) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    } else {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    Text("Runalyst")
                        .font(.largeTitle.bold())
                    Text("Your biomechanical running coach")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // MARK: - Philosophy
                VStack(alignment: .leading, spacing: 8) {
                    Text("Philosophy")
                        .font(.headline)
                    Text("Runalyst is built on a simple belief: every runner — from a first-time jogger to a seasoned competitor — deserves a coach that prioritizes long-term health over short-term speed. We focus on biomechanical efficiency, aerobic adaptation, and injury prevention so you can run better, not just faster.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)

                // MARK: - How It Works
                VStack(alignment: .leading, spacing: 16) {
                    Text("How It Works")
                        .font(.headline)

                    AboutFeatureRow(
                        icon: "waveform.path.ecg",
                        color: .red,
                        title: "Framboise Engine",
                        description: "Analyzes your runs minute-by-minute, filters out stops and pauses, and shows your true running pace, cadence, and heart rate."
                    )
                    AboutFeatureRow(
                        icon: "brain.head.profile",
                        color: .purple,
                        title: "On-Device AI Coaching",
                        description: "Apple Foundation Models coach your running form privately on your phone. Your workout data never leaves your device."
                    )
                    AboutFeatureRow(
                        icon: "chart.xyaxis.line",
                        color: .teal,
                        title: "Rolling Baselines",
                        description: "Every metric is compared against your own rolling baseline — not generic textbook averages. Drills and targets adapt as you improve."
                    )
                    AboutFeatureRow(
                        icon: "figure.run",
                        color: .orange,
                        title: "Pre-Run Primers",
                        description: "Warm-up drills designed to help your form, sent straight to your Apple Watch."
                    )
                    AboutFeatureRow(
                        icon: "cpu",
                        color: .indigo,
                        title: "Smart Run Classification",
                        description: "A smart on-device model labels each run (Easy, Tempo, Intervals, etc.) and learns from your adjustments over time."
                    )
                }

                // MARK: - Privacy
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text("Privacy First")
                            .font(.headline)
                    }
                    Text("All AI coaching, calculations, and analysis happen entirely on your device. Runalyst reads from Apple Health but never sends your data to external servers. Your running data stays with you.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)

                // MARK: - Footer
                VStack(spacing: 12) {
                    Divider()

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                        Text("AI-generated insights are for informational and training purposes only and do not replace professional medical or coaching advice. Always listen to your body.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Text("Made with ❤️ for runners everywhere")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("About Runalyst")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}
