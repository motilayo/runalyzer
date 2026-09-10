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
    @State private var syncError: String?
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
                .safeAreaInset(edge: VerticalEdge.bottom, spacing: 80) {
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
            let workouts = try await healthKitManager.fetchRunningWorkouts(filter: .allTime)

            // 2. Cross-reference with SwiftData to find new workouts
            let currentExistingRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
            let newWorkouts = workouts.filter { workout in
                !currentExistingRuns.contains(where: { $0.hkWorkoutID == workout.uuid })
            }

            let engine = FramboiseEngine()

            // Repair any existing runs in SwiftData that have missing/zero vertical oscillation or working distance/duration
            let runsNeedingRepair = currentExistingRuns.filter {
                ($0.rawAvgVerticalOscillation == nil || $0.rawAvgVerticalOscillation == 0) ||
                ($0.workingAvgVerticalOscillation == nil || $0.workingAvgVerticalOscillation == 0) ||
                ($0.workingDistanceMeters == nil || $0.workingDurationSeconds == nil)
            }
            for existingRun in runsNeedingRepair {
                if let workout = workouts.first(where: { $0.uuid == existingRun.hkWorkoutID }) {
                    if let dto = try? await healthKitManager.extractRunRecord(from: workout, engine: engine) {
                        existingRun.rawAvgVerticalOscillation = dto.rawAvgVerticalOscillation
                        existingRun.workingAvgVerticalOscillation = dto.workingAvgVerticalOscillation
                        existingRun.workingDistanceMeters = dto.workingDistanceMeters
                        existingRun.workingDurationSeconds = dto.workingDurationSeconds
                        existingRun.workingAvgPace = dto.workingAvgPace
                    }
                }
            }

            // 3. Extract and insert new runs
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate < $1.startDate }

            // Extract all records concurrently using TaskGroup
            let extractedRunsUnsorted = try await withThrowingTaskGroup(of: RunRecordDTO.self) { group in
                for workout in sortedNewWorkouts {
                    group.addTask {
                        try await healthKitManager.extractRunRecord(from: workout, engine: engine)
                    }
                }

                var results: [RunRecordDTO] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

            let extractedRuns = extractedRunsUnsorted.sorted { $0.date < $1.date }

            for dto in extractedRuns {
                let newRun = RunRecord(
                    hkWorkoutID: dto.hkWorkoutID,
                    date: dto.date,
                    totalDistanceMeters: dto.totalDistanceMeters,
                    duration: dto.duration,
                    rawAvgPace: dto.rawAvgPace,
                    rawAvgHeartRate: dto.rawAvgHeartRate,
                    rawAvgCadence: dto.rawAvgCadence,
                    workingAvgPace: dto.workingAvgPace,
                    workingAvgCadence: dto.workingAvgCadence,
                    workingAvgHeartRate: dto.workingAvgHeartRate,
                    workingAvgVerticalOscillation: dto.workingAvgVerticalOscillation,
                    rawAvgVerticalOscillation: dto.rawAvgVerticalOscillation,
                    workingDistanceMeters: dto.workingDistanceMeters,
                    workingDurationSeconds: dto.workingDurationSeconds,
                    paceCV: dto.paceCV,
                    paceSlope: dto.paceSlope,
                    percentZone4: dto.percentZone4,
                    detectedTypeRaw: dto.detectedTypeRaw,
                    framboiseTags: dto.framboiseTags
                )
                modelContext.insert(newRun)
            }
            try modelContext.save()

            // Preload AI analysis ONLY for runs within the last 7 days or past 5 runs
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])

            if let allRuns = try? modelContext.fetch(descriptor) {
                let runsToPreload = allRuns.enumerated().compactMap { index, run -> RunRecord? in
                    if run.date >= sevenDaysAgo || index < 5 {
                        return run
                    }
                    return nil
                }
                let container = modelContext.container

                for run in runsToPreload where run.insight == nil {
                    let runId = run.persistentModelID
                    if #available(iOS 26.0, *) {
                        Task.detached {
                            let analyzer = RunAnalyzerActor(modelContainer: container)
                            await analyzer.generateAnalysis(for: runId)
                        }
                    }

                    // Delay slightly to avoid overloading device resources
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                }
            }

        } catch is CancellationError {
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
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    ContentView()
        .modelContainer(previewContainer)
}
