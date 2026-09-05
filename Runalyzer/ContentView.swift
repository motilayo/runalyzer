import SwiftUI
import SwiftData
import HealthKit

/// The root view of the application that manages the onboarding state and primary HealthKit synchronization loop.
///
/// `ContentView` determines whether to show `OnboardingView` or `DashboardView`. It also handles fetching new
/// running workouts from HealthKit, persisting them to SwiftData, and lazily invoking the background AI analysis.
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
                DashboardView(onSync: { force in
                    await syncData(force: force)
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
                .safeAreaInset(edge: .bottom, spacing: 80) {
                    if isSyncing {
                        AnimatedLoadingView(
                            text: "Syncing Health Data & AI...",
                            isHorizontal: true,
                            imageSize: 16,
                            textFont: .caption,
                            spacing: 8
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        .padding(.bottom, 20)
                    }
                }
            } else {
                OnboardingView()
            }
        }
    }

    private func syncData(force: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            if force {
                // Clear the local workout table completely
                let allRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
                for run in allRuns {
                    modelContext.delete(run)
                }
                try modelContext.save()
            }

            // 1. Fetch recent workouts from HealthKit
            let workouts = try await healthKitManager.fetchRecentRunningWorkouts()

            // 2. Cross-reference with SwiftData to find new workouts
            // Re-fetch existing runs from DB to ensure we have the latest state (especially after force delete)
            let currentExistingRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
            let newWorkouts = workouts.filter { workout in
                !currentExistingRuns.contains(where: { $0.id == workout.uuid })
            }

            // 3. Extract and insert new runs
            // Sort new workouts ascending (oldest first) so we can insert them in order and calculate correct rolling baselines.
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate < $1.startDate }


            // Sequential extraction instead of TaskGroup to avoid Sendable issues with SwiftData model
            var extractedRunsUnsorted: [RunRecord] = []
            for workout in sortedNewWorkouts {
                let result = try await healthKitManager.extractRunRecord(from: workout)
                extractedRunsUnsorted.append(result)
            }

            // Sort again just in case (though sequential is already sorted if input is)
            let extractedRuns = extractedRunsUnsorted.sorted { $0.date < $1.date }

            // 4. Query the global standalone VO2 Max sample independently
            let globalVO2 = try? await healthKitManager.fetchLatestGlobalVO2Max()

            // Assign to the latest workout before saving to persistent storage
            if let mostRecentRun = extractedRuns.last {
                if let globalVO2 = globalVO2 {
                    mostRecentRun.vo2Max = globalVO2
                }
            } else if let latestDbRun = currentExistingRuns.sorted(by: { $0.date > $1.date }).first {
                // If there are no new workouts, update the latest existing one
                if let globalVO2 = globalVO2 {
                    latestDbRun.vo2Max = globalVO2
                    try modelContext.save()
                }
            }

            for newRun in extractedRuns {
                // Insert into SwiftData context
                modelContext.insert(newRun)
                // Save context so history is updated for subsequent runs
                try modelContext.save()
            }

            // Lazy load AI analysis for ONLY the 4 most recent runs (Hero card + Top 3)
            if #available(iOS 26.0, *) {
                let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                if let allRuns = try? modelContext.fetch(descriptor) {
                    let topRuns = allRuns.prefix(4)
                    let container = modelContext.container

                    for run in topRuns {
                        if run.insight == nil {
                            let runId = run.persistentModelID
                            await Task.detached {
                                let analyzer = RunAnalyzerActor(modelContainer: container)
                                await analyzer.generateAnalysis(for: runId)
                            }.value

                            // Delay slightly to avoid overloading device resources
                            try await Task.sleep(nanoseconds: 2_500_000_000)
                        }
                    }
                }
            }

        } catch is CancellationError {
            // Task was cancelled, likely due to a view refresh or termination.
            // We can safely ignore this and let the next sync handle the rest.
            print("Sync data task cancelled.")
        } catch {
            print("Failed to sync data: \(error.localizedDescription)")
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
