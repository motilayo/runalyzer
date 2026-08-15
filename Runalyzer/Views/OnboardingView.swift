import SwiftUI
import HealthKit

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("Meet Your AI\nRunning Coach.")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(
                    iconName: "arrow.triangle.2.circlepath",
                    title: "Passive Sync",
                    description: "We read your HealthKit data. No live tracking needed."
                )

                FeatureRow(
                    iconName: "lock.shield",
                    title: "Private AI",
                    description: "Insights generated locally on your device. Zero cloud."
                )

                FeatureRow(
                    iconName: "figure.run",
                    title: "Actionable Drills",
                    description: "Get personalized technique drills to improve your form."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Button(action: {
                requestHealthAccess()
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Connect Apple Health")
                            .font(.headline)
                        Image(systemName: "heart.text.square")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 32)
            }
            .disabled(isLoading)

            Spacer().frame(height: 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func requestHealthAccess() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await healthKitManager.requestAuthorization()
                // Update AppStorage to transition away from Onboarding
                await MainActor.run {
                    self.hasCompletedOnboarding = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to access Health Data: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

struct FeatureRow: View {
    var iconName: String
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
