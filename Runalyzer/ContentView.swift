import SwiftUI
import SwiftData
import HealthKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @Environment(\.modelContext) private var modelContext
    @Query private var existingRuns: [RunRecord]

    @State private var isSyncing = false
    @State private var syncError: String? = nil
    @State private var showError = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                DashboardView()
                    .task {
                        await syncData()
                    }
                    .alert("Sync Error", isPresented: $showError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(syncError ?? "An unknown error occurred while syncing.")
                    }
                    .overlay(alignment: .bottom) {
                        if isSyncing {
                            HStack {
                                ProgressView()
                                Text("Syncing Health Data & AI...")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Capsule().fill(Color(.systemBackground)))
                            .shadow(radius: 5)
                            .padding(.bottom, 20)
                        }
                    }
            } else {
                OnboardingView()
            }
        }
    }

    private func syncData() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            // 1. Fetch recent workouts from HealthKit
            let workouts = try await healthKitManager.fetchRecentRunningWorkouts()

            // 2. Cross-reference with SwiftData, extract and generate AI insight if new
            // We rate-limit processing to a maximum of 5 runs per sync to prevent overwhelming the device,
            // and we introduce a small delay between LLM calls.
            var processedCount = 0
            let maxRunsToProcess = 5

            for workout in workouts {
                if processedCount >= maxRunsToProcess {
                    break
                }

                // Check if RunRecord already exists
                if !existingRuns.contains(where: { $0.id == workout.uuid }) {
                    // Extract stats
                    let newRun = try await healthKitManager.extractRunRecord(from: workout)

                    // Insert into SwiftData context immediately so it appears on Dashboard
                    modelContext.insert(newRun)

                    // Generate AI insight locally
                    if #available(iOS 26.0, *) {
                        do {
                            if processedCount > 0 {
                                // 1-second delay between LLM invocations to prevent thermal throttling / memory spikes
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                            }

                            // Pass recent history for longitudinal analysis, sorting by date descending
                            let history = existingRuns.sorted(by: { $0.date > $1.date })
                            let insight = try await CoachingEngine.shared.generateInsight(for: newRun, history: history)
                            // Link the insight
                            newRun.insight = insight

                            processedCount += 1
                        } catch {
                            print("Failed to generate AI insight for run \(newRun.id): \(error)")
                            // Even if AI fails, we keep the run record.
                        }
                    } else {
                        print("AI insights require iOS 26.0+")
                        processedCount += 1
                    }
                }
            }

            // Context saves automatically in SwiftData on background threads or app exit,
            // but we can explicitly save if needed.
            try modelContext.save()

        } catch {
            print("Failed to sync data: \(error)")
            await MainActor.run {
                self.syncError = error.localizedDescription
                self.showError = true
            }
        }
    }
}

#Preview {
    let previewContainer: ModelContainer = {
        do {
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    ContentView()
        .modelContainer(previewContainer)
}
