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

            // 3. Extract and insert new runs
            // Sort new workouts ascending (oldest first) so we can insert them in order and calculate correct rolling baselines.
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate < $1.startDate }

            for workout in sortedNewWorkouts {
                // Extract stats
                let newRun = try await healthKitManager.extractRunRecord(from: workout)

                // Insert into SwiftData context immediately so it appears on Dashboard
                modelContext.insert(newRun)

                // Save context so history is updated for subsequent runs
                try modelContext.save()
            }

            // 4. Update the most recent run with the global VO2 max
            if let latestRun = try? modelContext.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])).first {
                if let globalVO2 = try? await healthKitManager.fetchLatestGlobalVO2Max() {
                    latestRun.vo2Max = globalVO2
                    try modelContext.save()
                }
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
