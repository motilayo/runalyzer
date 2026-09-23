import SwiftUI
import HealthKit
import UIKit

/// A comprehensive first-install walkthrough and onboarding flow.
///
/// `OnboardingView` introduces Runalyst's core value propositions, highlights the ⓘ metric explainer system,
/// prompts for Apple Health connectivity, and immediately initiates background workout sync and baseline
/// calibration while the runner reads through the app philosophy and "About Runalyst" guide.
struct OnboardingView: View {
    var isReplay: Bool = false
    var isSyncing: Bool = false
    var syncProgress: (current: Int, total: Int)?
    var syncStatusMessage: String?
    var onStartSync: (() -> Void)?
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @State private var currentPage: Int = 0
    @State private var isRequestingAuth: Bool = false
    @State private var authErrorMessage: String?
    @State private var isHealthAuthorized: Bool = false
    @State private var previewExplainer: MetricExplainerInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    TabView(selection: $currentPage) {
                        welcomeStepView
                            .tag(0)

                        healthConnectionStepView
                            .tag(1)

                        aboutRunalystStepView
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentPage)

                    bottomControls
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isReplay {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            dismiss()
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(item: $previewExplainer) { info in
                MetricExplainerSheet(info: info)
            }
            .task {
                checkInitialAuthStatus()
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if currentPage > 0 {
                Button {
                    withAnimation {
                        currentPage -= 1
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            } else {
                Spacer().frame(width: 60)
            }

            Spacer()

            // Page Indicator Dots
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: currentPage == index ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            Spacer()

            if isReplay {
                Button("Done") {
                    dismiss()
                }
                .font(.subheadline.bold())
                .foregroundColor(.accentColor)
            } else if currentPage < 2 {
                Button("Skip") {
                    withAnimation {
                        currentPage = 2
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else {
                Spacer().frame(width: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Step 0: Welcome & Features + ⓘ Explainer Spotlight

    private var welcomeStepView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.teal, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.teal.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "figure.run")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    Text("Meet Your AI\nRunning Coach")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Precision biomechanical analysis, form-targeted drills, and 100% on-device private coaching.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Core Pillars
                VStack(spacing: 14) {
                    walkthroughFeatureCard(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .teal,
                        title: "Passive HealthKit Sync",
                        description: "No manual clocks or phone carrying. Runalyst automatically ingests and analyzes workouts logged on your Apple Watch."
                    )

                    walkthroughFeatureCard(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "100% Private On-Device AI",
                        description: "Apple Foundation Models coach your running form locally on your iPhone. Your workout metrics never leave your device."
                    )

                    walkthroughFeatureCard(
                        icon: "chart.xyaxis.line",
                        iconColor: .purple,
                        title: "Adaptive Rolling Baselines",
                        description: "Every metric is measured against your personal 30-day baseline — never against arbitrary, one-size-fits-all averages."
                    )
                }
                .padding(.horizontal, 16)

                // Spotlight on the ⓘ Explainer
                infoExplainerSpotlightCard
                    .padding(.horizontal, 16)

                Spacer().frame(height: 20)
            }
            .padding(.vertical, 12)
        }
    }

    private var infoExplainerSpotlightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)

                Text("Tap ⓘ Anywhere for Deep Dives")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("Try It")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }

            Text("Notice the ⓘ icons across the dashboard and workout views? Tap any ⓘ icon anytime for plain-English definitions, calculation methodology, and biomechanical coaching context.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                previewExplainer = MetricExplainerInfo(
                    explainer: MetricDetailExplainer.explainer(for: "Average Cadence", isWorkoutStats: false)
                )
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.teal)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Preview: Working Cadence")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Text("Tap to see a sample metric explanation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.headline)
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Step 1: Connect Apple Health

    private var healthConnectionStepView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink, Color.red.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.red.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    Text("Connect Apple Health")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Runalyst reads your historical runs to calibrate your baseline and personalize your AI coaching drills.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 14) {
                    walkthroughFeatureCard(
                        icon: "figure.run",
                        iconColor: .orange,
                        title: "Running Workouts",
                        description: "Distance, duration, active pace, and elevation profiles."
                    )

                    walkthroughFeatureCard(
                        icon: "waveform.path.ecg",
                        iconColor: .teal,
                        title: "Cadence & Form Biometrics",
                        description: "Step rate (SPM), vertical bounce (oscillation), and ground contact time."
                    )

                    walkthroughFeatureCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Heart Rate & VO2 Max",
                        description: "Aerobic stability, cardiovascular strain, and endurance tracking."
                    )
                }
                .padding(.horizontal, 16)

                // Health Connect Button / State
                VStack(spacing: 12) {
                    if isHealthAuthorized {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)

                            Text("Apple Health Connected")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundColor(.teal)
                                .font(.caption)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        Button(action: {
                            requestHealthAccess()
                        }) {
                            HStack(spacing: 10) {
                                if isRequestingAuth {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "heart.text.square")
                                        .font(.headline)
                                    Text("Connect Apple Health")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isRequestingAuth)
                    }

                    if let error = authErrorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    // Background sync status indicator if sync has begun
                    if isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(syncStatusMessage ?? "Syncing running workouts in the background...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 20)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Step 2: About Runalyst & Live Background Sync

    private var aboutRunalystStepView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live background sync calibration banner
                backgroundSyncStatusBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Embedded About Runalyst content from Settings
                AboutRunalystView(isEmbedded: true)
                    .padding(.horizontal, 16)

                Spacer().frame(height: 30)
            }
        }
    }

    @ViewBuilder
    private var backgroundSyncStatusBanner: some View {
        if isSyncing {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.bounce.up, options: .repeating)

                    Text(syncStatusMessage ?? "Calibrating History...")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    Spacer()

                    if let progress = syncProgress, progress.total > 0 {
                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }

                if let progress = syncProgress, progress.total > 0 {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .tint(.accentColor)
                }

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("Syncing & calibrating in the background. Take your time reading through our philosophy!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        } else if isHealthAuthorized {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Complete")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text("Your personal 30-day running baselines are ready.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Divider()

            HStack {
                if currentPage == 0 {
                    Button {
                        withAnimation {
                            currentPage = 1
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Text("Get Started")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                } else if currentPage == 1 {
                    Button {
                        withAnimation {
                            currentPage = 2
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Text(isHealthAuthorized ? "Next: About Runalyst" : "Continue to About Runalyst")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isHealthAuthorized ? Color.accentColor : Color.primary)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if isReplay {
                            dismiss()
                        } else {
                            onComplete?()
                        }
                    } label: {
                        HStack {
                            Text(isReplay ? "Done" : "Start Running with Runalyst")
                                .font(.headline)
                            Image(systemName: isReplay ? "checkmark" : "figure.run")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func walkthroughFeatureCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func requestHealthAccess() {
        isRequestingAuth = true
        authErrorMessage = nil

        Task {
            do {
                try await healthKitManager.requestAuthorization()
                await MainActor.run {
                    self.isHealthAuthorized = true
                    self.isRequestingAuth = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                // Initiate background sync immediately
                onStartSync?()

                // Transition smoothly to Step 2
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    withAnimation {
                        self.currentPage = 2
                    }
                }
            } catch {
                await MainActor.run {
                    self.authErrorMessage = "Health access error: \(error.localizedDescription)"
                    self.isRequestingAuth = false
                }
            }
        }
    }

    private func checkInitialAuthStatus() {
        guard healthKitManager.isHealthDataAvailable() else { return }
        let status = healthKitManager.healthStore?.authorizationStatus(for: HKObjectType.workoutType())
        if status == .sharingAuthorized {
            isHealthAuthorized = true
        }
    }
}

#Preview {
    OnboardingView()
}
