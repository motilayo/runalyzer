import SwiftUI
import SwiftData

/// The primary view of the Runalyzer application displaying filter controls, macro statistics,
/// cached AI fatigue insights, and the filtered run list.
struct DashboardView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0

    // Progression Hub Filter State
    @State private var selectedTimeFilter: TimeFilter = .thirtyDays
    @State private var activeBaseline: BaselineStats?
    @State private var activeTotalDistanceMeters: Double = 0.0

    // Cached Fatigue Insight State
    @State private var activeFatigueInsightHeadline: String?
    @State private var activeFatigueInsightObservation: String?
    @State private var activeFatigueInsightRecommendation: String?

    @AppStorage("lastProcessedRunDate") private var lastProcessedRunDate: Double = 0
    @AppStorage("cachedFatigueInsightData") private var cachedFatigueInsightData: Data = Data()

    @State private var isSyncing: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private var minDistanceInMeters: Double {
        useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
    }

    private var minDistanceFloat: Double {
        minDistanceInMeters - 0.01
    }

    private var filterStartDate: Date? {
        switch selectedTimeFilter {
        case .sevenDays:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .thirtyDays:
            return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .allTime:
            return nil
        }
    }

    /// Shared Predicate used by both the list view and macro calculations
    private var activeDescriptor: FetchDescriptor<RunRecord> {
        var descriptor = FetchDescriptor<RunRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let minDistance = minDistanceFloat
        if let targetDate = filterStartDate {
            descriptor.predicate = #Predicate<RunRecord> {
                $0.totalDistanceMeters >= minDistance && $0.date >= targetDate
            }
        } else {
            descriptor.predicate = #Predicate<RunRecord> {
                $0.totalDistanceMeters >= minDistance
            }
        }
        return descriptor
    }

    private var filteredRunRecords: [RunRecord] {
        let minDistance = minDistanceFloat
        let targetDate = filterStartDate
        return runRecords.filter { record in
            guard record.totalDistanceMeters >= minDistance else { return false }
            if let targetDate = targetDate {
                return record.date >= targetDate
            }
            return true
        }
    }

    var onSync: ((Bool) async -> Void)? = nil

    // MARK: - 1. Filter Controls View

    @ViewBuilder
    private var filterControlsView: some View {
        Picker("Time Filter", selection: $selectedTimeFilter) {
            Text("7 Days").tag(TimeFilter.sevenDays)
            Text("30 Days").tag(TimeFilter.thirtyDays)
            Text("All Time").tag(TimeFilter.allTime)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - 2. Macro Stats & Fatigue Block

    @ViewBuilder
    private var macroStatsAndFatigueBlock: some View {
        VStack(spacing: 12) {
            // Macro Stats 3-Box Grid: Avg Pace, Avg HR, Total Distance
            HStack(spacing: 12) {
                // Avg Pace
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg Pace")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    let avgPaceSec = activeBaseline?.avgPace ?? 0
                    Text(avgPaceSec > 0 ? formatPace(secondsPerKilometer: avgPaceSec) : "--:--")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(useMetricSystem ? "/km" : "/mi")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Avg HR
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg HR")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    let avgHR = activeBaseline?.avgHeartRate ?? 0
                    Text(avgHR > 0 ? "\(avgHR)" : "--")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("BPM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Total Distance
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    let convertedDist = useMetricSystem
                        ? (activeTotalDistanceMeters / 1000.0)
                        : (activeTotalDistanceMeters / 1609.344)
                    Text(String(format: "%.1f", convertedDist))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(useMetricSystem ? "km" : "mi")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)

            // AI Fatigue Insight (Cached)
            if let headline = activeFatigueInsightHeadline,
               let observation = activeFatigueInsightObservation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.heart.fill")
                            .foregroundColor(.purple)
                        Text("AI Fatigue Insight (Cached)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }

                    Text(headline)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(observation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let recommendation = activeFatigueInsightRecommendation, !recommendation.isEmpty {
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(recommendation)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Body View Hierarchy

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 1. Filter Controls
                    filterControlsView

                    // 2. Macro Stats & Fatigue Block
                    macroStatsAndFatigueBlock

                    // 3. Filtered Runs List
                    if filteredRunRecords.isEmpty {
                        if isSyncing && runRecords.isEmpty {
                            AnimatedLoadingView(text: "Analyzing your running history...")
                                .padding(.top, 80)
                        } else {
                            ContentUnavailableView(
                                "No Runs Found",
                                systemImage: "figure.run.circle",
                                description: Text("Runs matching your active filters will appear here.")
                            )
                            .padding(.top, 40)
                        }
                    } else {
                        Section(header: Text("Filtered Runs")
                                            .font(.title3.bold())
                                            .padding(.horizontal)
                                            .frame(maxWidth: .infinity, alignment: .leading)) {
                            RunListFilteredView(runs: filteredRunRecords)
                        }
                    }
                }
                .padding(.vertical)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }
            .navigationDestination(for: RunRecord.self) { runRecord in
                RunDetailView(runRecord: runRecord)
            }
            .task {
                do {
                    try await HealthKitManager.shared.requestAuthorization()
                } catch {
                    print("Error requesting HealthKit authorization on dashboard: \(error.localizedDescription)")
                }

                if let onSync {
                    await onSync(false)
                    isSyncing = false
                }

                await updateMacroAverages()
            }
            .onChange(of: minimumRunDistance) { _, _ in
                Task { await updateMacroAverages() }
            }
            .onChange(of: selectedTimeFilter) { _, _ in
                Task { await updateMacroAverages() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, let onSync else { return }
                Task {
                    await onSync(false)
                    await updateMacroAverages()
                }
            }
            .refreshable {
                if let onSync {
                    isSyncing = true
                    let task = Task {
                        await onSync(false)
                    }
                    _ = await task.result
                    isSyncing = false
                    await updateMacroAverages()
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Dashboard")
                            .font(.headline)
                        Spacer()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(onForceSync: onSync)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
        }
    }

    // MARK: - Macro Calculations & AI Caching

    private func updateMacroAverages() async {
        // Calculate total distance for the active filter
        activeTotalDistanceMeters = filteredRunRecords.map(\.totalDistanceMeters).reduce(0, +)

        if #available(iOS 26.0, *) {
            let container = modelContext.container
            let engine = MacroQueryEngine(modelContainer: container)

            let days: Int? = switch selectedTimeFilter {
            case .sevenDays: 7
            case .thirtyDays: 30
            case .allTime: nil
            }

            activeBaseline = try? await engine.calculateRollingAverages(days: days, minimumDistance: minDistanceInMeters)

            // Fatigue Insight Caching: Load from UserDefaults
            struct CachedFatiguePayload: Codable {
                var headline: String
                var observation: String
                var recommendation: String
            }

            if let cached = try? JSONDecoder().decode(CachedFatiguePayload.self, from: cachedFatigueInsightData) {
                activeFatigueInsightHeadline = cached.headline
                activeFatigueInsightObservation = cached.observation
                activeFatigueInsightRecommendation = cached.recommendation
            }

            // Only make an API call to the LLM if the database contains a RunRecord with a date strictly newer than lastProcessedRunDate
            let newestRunDate = runRecords.first?.date.timeIntervalSince1970 ?? 0
            if newestRunDate > lastProcessedRunDate {
                if let newInsight = try? await engine.generateWeeklyFatigueInsight(minimumDistance: minDistanceInMeters) {
                    activeFatigueInsightHeadline = newInsight.headline
                    activeFatigueInsightObservation = newInsight.observation
                    activeFatigueInsightRecommendation = newInsight.recommendation
                    lastProcessedRunDate = newestRunDate

                    let payload = CachedFatiguePayload(
                        headline: newInsight.headline,
                        observation: newInsight.observation,
                        recommendation: newInsight.recommendation
                    )
                    if let encoded = try? JSONEncoder().encode(payload) {
                        cachedFatigueInsightData = encoded
                    }
                }
            }
        }
    }
}

enum TimeFilter: Int {
    case sevenDays
    case thirtyDays
    case allTime

    var title: String {
        switch self {
        case .sevenDays: return "7-DAY"
        case .thirtyDays: return "30-DAY"
        case .allTime: return "ALL TIME"
        }
    }
}

// MARK: - Metric Definition & Row Subviews

enum MetricPolarity {
    case higherIsBetter
    case lowerIsBetter
}

/// A list row representing a single historical run, displaying its date, distance, pace, and classification pill tag.
struct RunListRowView: View {
    var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(runRecord.date, style: .date)
                    .font(.headline)
                    .foregroundColor(.primary)

                let distanceConverted = useMetricSystem
                    ? (runRecord.totalDistanceMeters / 1000.0)
                    : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"
                let paceStr = formatDisplayPace(secondsPerKilometer: runRecord.rawAvgPace)

                Text(String(format: "%.2f %@ • %@", distanceConverted, distanceUnit, paceStr))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Binds strictly to detectedType, falling back to "Unknown"
            PillTagView(text: runRecord.detectedType, color: runTypeColor(for: runRecord.detectedType))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

func runTypeColor(for detectedType: String) -> Color {
    switch detectedType {
    case "Steady": return .green
    case "Tempo": return .orange
    case "Progressive": return .yellow
    case "Intervals": return .red
    case "Urban Traffic": return .purple
    default: return .gray
    }
}

struct PillTagView: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
