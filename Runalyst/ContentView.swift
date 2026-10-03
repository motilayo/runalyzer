import SwiftUI
import SwiftData
import HealthKit
import OSLog

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "Sync")

/// The root view of the application that manages the onboarding state and primary HealthKit synchronization loop.
///
/// `ContentView` determines whether to show `OnboardingView` or `DashboardView`. It also handles fetching new
/// running workouts from HealthKit, persisting them to SwiftData, and lazily invoking the background AI analysis.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var existingRuns: [RunRecord]

    @State private var isSyncing = false
    @State private var syncProgress: (current: Int, total: Int)?
    @State private var syncStatusMessage: String?
    @State private var syncError: String?
    @State private var showError = false

    private var previewScreen: String? {
        ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
    }

    @ViewBuilder
    private var drillReadoutPreview: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let baseCadence = 165
        let targetCadence: String? = template.calculateTargetCadence(baseCadence)
        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: baseCadence,
            targetCadence: targetCadence,
            duration: .tenMinutes,
            hapticMode: .on
        )
        let readout = DrillReadout.readout(
            for: .cadencePyramids,
            customTitle: template.title,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            customDuration: .tenMinutes
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            durationMinutes: DrillDuration.tenMinutes.rawValue,
            hapticMode: HapticFeedbackMode.on.rawValue
        )

        DrillInterstitialReadoutView(
            readout: readout,
            workoutPlan: plan,
            prescriptionDTO: dto,
            onCommitToWatch: nil
        )
    }

    var body: some View {
        Group {
            if let previewScreen {
                switch previewScreen {
                case "RUN_DETAIL":
                    if let run = existingRuns.first {
                        NavigationStack {
                            RunDetailView(runRecord: run)
                        }
                    } else {
                        DashboardView(onSync: nil)
                    }
                case "DRILLS":
                    NavigationStack {
                        DrillsLibraryView()
                    }
                case "DRILL_READOUT":
                    drillReadoutPreview
                case "SETTINGS":
                    NavigationStack {
                        SettingsView(onForceSync: nil)
                    }
                case "PROGRESSION":
                    NavigationStack {
                        ScrollView {
                            ProgressionChartView(allRuns: existingRuns, defaultHorizon: .allTime)
                                .padding()
                        }
                        .navigationTitle("Cadence Progression")
                    }
                case "AUTO_TOUR":
                    AppStoreTourView(existingRuns: existingRuns)
                default:
                    DashboardView(onSync: nil)
                }
            } else if hasCompletedOnboarding {
                DashboardView(onSync: { force in
                    await syncData(force: force)
                })
                .task {
                    guard NSClassFromString("XCTestCase") == nil else { return }
                    Task {
                        await syncData()
                    }

                    healthKitManager.onWorkoutsUpdated = {
                        Task {
                            await syncData()
                        }
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
                        if let progress = syncProgress, progress.total > 5 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                        .symbolEffect(.bounce.up, options: .repeating)

                                    Text(syncStatusMessage ?? "Calibrating History")
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)

                                    Spacer(minLength: 4)

                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption.bold())
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }

                                ProgressView(value: Double(progress.current), total: Double(max(1, progress.total)))
                                    .tint(.accentColor)

                                Text("Keep Runalyst open to complete baseline calibration")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            AnimatedLoadingView(
                                text: syncStatusMessage ?? "Syncing Health Data & AI...",
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
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSyncing)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: syncProgress?.current)
            } else {
                OnboardingView(
                    isSyncing: isSyncing,
                    syncProgress: syncProgress,
                    syncStatusMessage: syncStatusMessage,
                    onStartSync: {
                        Task {
                            await syncData()
                        }
                    },
                    onComplete: {
                        hasCompletedOnboarding = true
                    }
                )
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["RUNALYST_FORCE_SEED"] == "true" || (existingRuns.count < 30 && previewScreen != nil) {
                logger.info("Auto-seeding 38 mock runs for preview/video recording...")
                HealthKitSeeder.shared.seedDirectToSwiftData(context: modelContext)
            }
        }
    }

    @MainActor
    private func syncData(force: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
            syncStatusMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

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
            syncStatusMessage = "Connecting to Apple Health..."
            let workouts = try await healthKitManager.fetchRunningWorkouts(filter: .allTime)

            // 2. Cross-reference with SwiftData to find new workouts
            let currentExistingRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
            let existingWorkoutIDs = Set(currentExistingRuns.map(\.hkWorkoutID))
            let newWorkouts = workouts.filter { workout in
                !existingWorkoutIDs.contains(workout.uuid)
            }

            let engine = FramboiseEngine()

            var priorRunData: [HealthKitManager.RunBaselineData] = currentExistingRuns
                .filter { !$0.isDeleted && $0.modelContext != nil }
                .map {
                    HealthKitManager.RunBaselineData(
                        date: $0.date,
                        pace: $0.workingAvgPace > 0 ? $0.workingAvgPace : $0.rawAvgPace,
                        hr: $0.workingAvgHeartRate > 0 ? $0.workingAvgHeartRate : $0.rawAvgHeartRate,
                        cadence: $0.workingAvgCadence > 0 ? $0.workingAvgCadence : $0.rawAvgCadence,
                        duration: $0.duration,
                        isPrescribedDrill: $0.framboiseTags.contains("prescribedDrill")
                    )
                }

            // 3. Extract and insert new runs incrementally (newest first)
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate > $1.startDate }
            if !sortedNewWorkouts.isEmpty {
                logger.info("Found \(sortedNewWorkouts.count) new workouts to sync.")
                if sortedNewWorkouts.count > 5 {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                syncStatusMessage = "Calibrating Running History"
                syncProgress = (0, sortedNewWorkouts.count)

                for (index, workout) in sortedNewWorkouts.enumerated() {
                    if let dto = try? await healthKitManager.extractRunRecord(from: workout, engine: engine, priorRuns: priorRunData) {
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
                            rawAvgStrideLength: dto.rawAvgStrideLength,
                            workingAvgStrideLength: dto.workingAvgStrideLength,
                            workingDistanceMeters: dto.workingDistanceMeters,
                            workingDurationSeconds: dto.workingDurationSeconds,
                            paceCV: dto.paceCV,
                            paceSlope: dto.paceSlope,
                            percentZone4: dto.percentZone4,
                            detectedTypeRaw: dto.detectedTypeRaw,
                            framboiseTags: dto.framboiseTags
                        )
                        modelContext.insert(newRun)

                        if dto.framboiseTags.contains("prescribedDrill") {
                            // 1. Auto-complete matching uncompleted DrillRecommendations
                            let openDrillsDescriptor = FetchDescriptor<DrillRecommendation>(
                                predicate: #Predicate<DrillRecommendation> { drill in
                                    !drill.isCompleted
                                }
                            )
                            if let openDrills = try? modelContext.fetch(openDrillsDescriptor) {
                                for drill in openDrills {
                                    let matchesId = drill.preRunDrillId.map { dto.framboiseTags.contains($0) } ?? false
                                    let matchesTag = dto.framboiseTags.contains("drill:\(drill.drillTitle)")
                                    let matchesTitle = drill.drillTitle.localizedCaseInsensitiveCompare(dto.detectedTypeRaw) == .orderedSame
                                    if matchesTitle || matchesId || matchesTag {
                                        drill.isCompleted = true
                                        logger.info("Auto-completed prescribed drill recommendation: \(drill.drillTitle)")
                                    }
                                }
                            }

                            // 2. Generate ground-truth TrainingCorrection for CoreML personalization
                            let effectivePace = newRun.workingAvgPace > 0 ? newRun.workingAvgPace : newRun.rawAvgPace
                            let correction = TrainingCorrection(
                                runRecordID: newRun.id,
                                originalLabel: "Prescribed Drill",
                                correctedLabel: dto.detectedTypeRaw,
                                featureVector: [
                                    effectivePace,
                                    newRun.paceCV,
                                    newRun.paceSlope,
                                    newRun.percentZone4,
                                    newRun.duration / 60.0
                                ],
                                createdAt: dto.date,
                                isProcessed: false
                            )
                            modelContext.insert(correction)
                            logger.info("Inserted ground-truth TrainingCorrection for prescribed drill: \(dto.detectedTypeRaw)")
                        }

                        if (index + 1) % 25 == 0 || (index + 1) == sortedNewWorkouts.count {
                            try? modelContext.save()
                        }
                        priorRunData.append(
                            HealthKitManager.RunBaselineData(
                                date: dto.date,
                                pace: dto.workingAvgPace > 0 ? dto.workingAvgPace : dto.rawAvgPace,
                                hr: dto.workingAvgHeartRate > 0 ? dto.workingAvgHeartRate : dto.rawAvgHeartRate,
                                cadence: dto.workingAvgCadence > 0 ? dto.workingAvgCadence : dto.rawAvgCadence,
                                duration: dto.duration,
                                isPrescribedDrill: dto.framboiseTags.contains("prescribedDrill")
                            )
                        )
                        logger.info("Persisted run \(index + 1)/\(sortedNewWorkouts.count) (\(dto.date))")
                    }

                    syncProgress = (index + 1, sortedNewWorkouts.count)

                    // Yield briefly to keep the main runloop and UI responsive
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }

            // 4. Preload AI analysis ONLY for runs within the last 7 days or past 5 runs
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])

            if let allRuns = try? modelContext.fetch(descriptor) {
                let runsToPreload = allRuns.prefix(5).filter { run in
                    run.insight == nil &&
                    (run.workingAvgCadence > 0 || run.workingAvgHeartRate > 0) &&
                    (run.date >= sevenDaysAgo || (allRuns.firstIndex(where: { $0.id == run.id }) ?? 5) < 5)
                }
                let container = modelContext.container

                if !runsToPreload.isEmpty {
                    syncStatusMessage = "Generating AI Coaching..."
                    syncProgress = nil
                }

                for run in runsToPreload where run.insight == nil {
                    let runId = run.persistentModelID
                    if #available(iOS 26.0, *) {
                        logger.info("Generating AI insight sequentially for run \(run.date)")
                        let analyzer = RunAnalyzerActor(modelContainer: container)
                        await analyzer.generateAnalysis(for: runId)
                    }

                    // Throttle sequentially to avoid on-device model rate limits and thermal overload
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }

        } catch is CancellationError {
            logger.info("Sync data task cancelled.")
        } catch {
            logger.error("Failed to sync data: \(error.localizedDescription)")
            await MainActor.run {
                self.syncError = error.localizedDescription
                self.showError = true
            }
        }
    }
}

struct AppStoreTourView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var queryRuns: [RunRecord]
    var existingRuns: [RunRecord]
    @State private var tourStep: Int = 0
    @State private var isPulsing: Bool = false

    private var allRuns: [RunRecord] {
        queryRuns.isEmpty ? existingRuns : queryRuns
    }

    private var targetRun: RunRecord? {
        allRuns.first { $0.workingAvgCadence > 0 } ?? allRuns.first
    }

    private var baseCadence: Int? {
        if let target = targetRun, target.workingAvgCadence > 0 {
            return Int(target.workingAvgCadence)
        }
        return 165
    }

    var body: some View {
        ZStack {
            switch tourStep {
            case 0:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            case 1:
                if let targetRun {
                    NavigationStack {
                        RunDetailView(runRecord: targetRun)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    DashboardView(onSync: nil)
                }
            case 2:
                NavigationStack {
                    DrillsLibraryView()
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 3:
                drillReadoutView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 4:
                NavigationStack {
                    ScrollView {
                        ProgressionChartView(allRuns: allRuns, defaultHorizon: .allTime)
                            .padding()
                    }
                    .navigationTitle("Cadence Progression")
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            default:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.blue.opacity(isPulsing ? 0.3 : 0.05))
                .frame(width: 4, height: 4)
                .padding(4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
        }
        .animation(.easeInOut(duration: 0.6), value: tourStep)
        .task {
            // Choreographed 24.5-second tour for App Store Preview (15-30s Apple requirement)
            try? await Task.sleep(nanoseconds: 4_500_000_000) // 4.5s on Dashboard
            withAnimation { tourStep = 1 }                    // 5.5s on Run Detail (Classification + Timeline + Biometrics)
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            withAnimation { tourStep = 2 }                    // 4.0s on Pre-Run Library
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { tourStep = 3 }                    // 5.0s on Drill Breakdown Modal (5-Point Readout + Timeline + Watch Export)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation { tourStep = 4 }                    // 5.5s on Cadence Progression Chart
            try? await Task.sleep(nanoseconds: 5_500_000_000)
        }
    }

    @ViewBuilder
    private var drillReadoutView: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let targetCadence: String? = baseCadence.map { template.calculateTargetCadence($0) }
        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: baseCadence,
            targetCadence: targetCadence,
            duration: .tenMinutes,
            hapticMode: .on
        )
        let readout = DrillReadout.readout(
            for: .cadencePyramids,
            customTitle: template.title,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            customDuration: .tenMinutes
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            durationMinutes: DrillDuration.tenMinutes.rawValue,
            hapticMode: HapticFeedbackMode.on.rawValue
        )

        DrillInterstitialReadoutView(
            readout: readout,
            workoutPlan: plan,
            prescriptionDTO: dto,
            onCommitToWatch: nil
        )
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
