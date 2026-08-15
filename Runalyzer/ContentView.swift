import SwiftUI
import SwiftData
import HealthKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @Environment(\.modelContext) private var modelContext
    @Query private var existingRuns: [RunRecord]

    @State private var isSyncing = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                DashboardView()
                    .task {
                        await syncData()
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
            // 1. Fetch the last 5 workouts from HealthKit
            let workouts = try await healthKitManager.fetchLastFiveRunningWorkouts()

            // 2. Cross-reference with SwiftData, extract and generate AI insight if new
            for workout in workouts {
                // Check if RunRecord already exists
                if !existingRuns.contains(where: { $0.id == workout.uuid }) {
                    // Extract stats
                    let newRun = try await healthKitManager.extractRunRecord(from: workout)

                    // Insert into SwiftData context immediately so it appears on Dashboard
                    modelContext.insert(newRun)

                    // Generate AI insight locally
                    if #available(iOS 26.0, *) {
                        do {
                            let insight = try await CoachingEngine.shared.generateInsight(for: newRun)
                            // Link the insight
                            newRun.insight = insight
                        } catch {
                            print("Failed to generate AI insight for run \(newRun.id): \(error)")
                            // Even if AI fails, we keep the run record.
                        }
                    } else {
                        print("AI insights require iOS 26.0+")
                    }
                }
            }

            // Context saves automatically in SwiftData on background threads or app exit,
            // but we can explicitly save if needed.
            try modelContext.save()

        } catch {
            print("Failed to sync data: \(error)")
        }
    }
}

#Preview {
    let previewContainer: ModelContainer = {
        do {
            let schema = Schema([RunRecord.self, CoachingInsight.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    ContentView()
        .modelContainer(previewContainer)
}
