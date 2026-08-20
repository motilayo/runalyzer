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
                DashboardView(onSync: {
                    await syncData()
                })
                .task {
                    await syncData()

                    healthKitManager.onWorkoutsUpdated = {
                        await syncData()
                    }
                    healthKitManager.startObservingWorkouts()
                }
                .alert("Sync Error", isPresented: $showError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(syncError ?? "An unknown error occurred while syncing.")
                }
                .safeAreaInset(edge: .bottom) {
                    if isSyncing {
                        HStack {
                            ProgressView()
                            Text("Syncing Health Data & AI...")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
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

            // 2. Cross-reference with SwiftData to find new workouts
            let newWorkouts = workouts.filter { workout in
                !existingRuns.contains(where: { $0.id == workout.uuid })
            }

            // 3. Extract and generate AI insight for new runs
            // We process them all but introduce a small delay between LLM calls to prevent overwhelming the device.
            // Additionally, we save the context after every 5 runs to ensure progress is persisted.
            var processedCount = 0

            for workout in newWorkouts {
                // Extract stats
                let newRun = try await healthKitManager.extractRunRecord(from: workout)

                // Insert into SwiftData context immediately so it appears on Dashboard
                modelContext.insert(newRun)

                // Generate AI insight locally
                if #available(iOS 26.0, *) {
                    do {
                        if processedCount > 0 {
                            // 1.5-second delay between LLM invocations to prevent thermal throttling / memory spikes
                            try await Task.sleep(nanoseconds: 1_500_000_000)
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
                        processedCount += 1
                    }
                } else {
                    print("AI insights require iOS 26.0+")
                    processedCount += 1
                }

                // Save progress periodically to handle large backlogs safely
                if processedCount % 5 == 0 {
                    try modelContext.save()
                    // Add a slightly longer breather between batches of 5
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }

            // Final save for any remaining records
            try modelContext.save()

        } catch is CancellationError {
            // Task was cancelled, likely due to a view refresh or termination.
            // We can safely ignore this and let the next sync handle the rest.
            print("Sync data task cancelled.")
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
