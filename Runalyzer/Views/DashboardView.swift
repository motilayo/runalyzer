import SwiftUI
import SwiftData

/// The primary view of the Runalyzer application displaying the user's running metrics, AI insights, and run history.
///
/// `DashboardView` presents a summary of the most recent run, a grid of aggregate metrics over the last 30 days,
/// and a list of historical runs. It triggers data synchronization and handles the UI states for AI generation.
struct DashboardView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0

    // Epic 3: Progression Hub State
    @State private var selectedTimeFilter: TimeFilter = .thirtyDays
    @State private var sevenDayBaseline: BaselineStats?
    @State private var thirtyDayBaseline: BaselineStats?
    @State private var allTimeBaseline: BaselineStats?
    @State private var activeFatigueInsightHeadline: String?
    @State private var activeFatigueInsightObservation: String?
    @State private var activeFatigueInsightRecommendation: String?

    @AppStorage("lastFatigueInsightDate") private var lastFatigueInsightDate: Double = 0
    @AppStorage("cachedFatigueInsightData") private var cachedFatigueInsightData: Data = Data()

    @State private var isSyncing: Bool = true

    @Environment(\.modelContext) private var modelContext

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        return runRecords.filter { $0.distance >= (minDistanceInMeters - 0.01) }
    }

    private var activeDescriptor: FetchDescriptor<RunRecord> {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        // Subtracted 0.01 to avoid precision issues like 1000.0 >= 999.999
        let minDistanceFloat = minDistanceInMeters - 0.01

        let targetDate: Date?
        switch selectedTimeFilter {
        case .sevenDays:
            targetDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .thirtyDays:
            targetDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .allTime:
            targetDate = nil
        }

        var descriptor = FetchDescriptor<RunRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        if let targetDate = targetDate {
            descriptor.predicate = #Predicate { $0.distance >= minDistanceFloat && $0.date >= targetDate }
        } else {
            descriptor.predicate = #Predicate { $0.distance >= minDistanceFloat }
        }
        return descriptor
    }

    // 1. Get the most recent valid VO2 Max score
    var latestVO2Max: Double? {
        filteredRunRecords.first(where: { $0.vo2Max > 0 })?.vo2Max
    }

    // 2. Calculate the trend against the 30 days prior to that recent score
    var vo2MaxTrend: Double? {
        let validRuns = filteredRunRecords.filter { $0.vo2Max > 0 }

        // We need at least 2 valid readings to establish a trend
        guard validRuns.count >= 2 else { return nil }

        let currentRun = validRuns[0]
        let currentVO2 = currentRun.vo2Max

        // Calculate the 30-day window relative to the most recent valid run
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: currentRun.date) else { return nil }

        let baselineRuns = validRuns.dropFirst().filter { $0.date >= thirtyDaysAgo }

        guard !baselineRuns.isEmpty else { return nil }

        let baselineAvg = baselineRuns.map(\.vo2Max).reduce(0, +) / Double(baselineRuns.count)
        return currentVO2 - baselineAvg
    }

    // Dynamic Active Baseline Based on Segmented Picker
    private var activeBaseline: BaselineStats? {
        switch selectedTimeFilter {
        case .sevenDays: return sevenDayBaseline
        case .thirtyDays: return thirtyDayBaseline
        case .allTime: return allTimeBaseline
        }
    }

    var onSync: ((Bool) async -> Void)? = nil

    @ViewBuilder
    private var fitnessBaselineCard: some View {
        VStack(spacing: 12) {
            if let currentVO2 = latestVO2Max {
                // TOP ROW: Current VO2 Max & Trend
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.red)
                            .font(.title2)

                        Text("VO2 Max")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Text(String(format: "%.1f", currentVO2))
                        .font(.title2)
                        .bold()

                    if let trend = vo2MaxTrend {
                        let isPositive = trend >= 0
                        HStack(spacing: 2) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                                .bold()
                            Text(String(format: "%.1f", abs(trend)))
                                .font(.subheadline)
                                .bold()
                        }
                        .foregroundColor(isPositive ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isPositive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }

                // BOTTOM ROW: The 30-Day Baseline Stats
                Divider()
            }

            if let activeStats = activeBaseline {
                HStack {
                    // LEFT SIDE: Avg Cadence
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedTimeFilter.title) AVG CADENCE")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.semibold)
                        Text("\(activeStats.avgCadence) SPM")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    // RIGHT SIDE: Avg Pace
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selectedTimeFilter.title) AVG PACE")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.semibold)

                        Text(activeStats.avgPace.formattedPaceString)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var progressionFiltersView: some View {
        VStack(spacing: 12) {
            Picker("Time Filter", selection: $selectedTimeFilter) {
                Text("7 Days").tag(TimeFilter.sevenDays)
                Text("30 Days").tag(TimeFilter.thirtyDays)
                Text("All Time").tag(TimeFilter.allTime)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Text("Min Distance:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Slider(value: $minimumRunDistance, in: 0...(useMetricSystem ? 35 : 22), step: 1)
                    .sensoryFeedback(.selection, trigger: Int(minimumRunDistance))

                Text(String(format: "%.0f %@", minimumRunDistance, useMetricSystem ? "km" : "mi"))
                    .font(.subheadline)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var fatigueInsightCard: some View {
        if selectedTimeFilter == .sevenDays,
           let headline = activeFatigueInsightHeadline,
           let observation = activeFatigueInsightObservation,
           let recommendation = activeFatigueInsightRecommendation {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.heart.fill")
                        .foregroundColor(.purple)
                    Text("Fatigue Insight")
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
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    progressionFiltersView

                    // Global Fitness Pill (VO2 Max) & Macro Baseline
                    fitnessBaselineCard

                    fatigueInsightCard

                    if filteredRunRecords.isEmpty {
                        if isSyncing && runRecords.isEmpty {
                            AnimatedLoadingView(text: "Analyzing your running history...")
                                .padding(.top, 100)
                        } else {
                            ContentUnavailableView(
                                "No Runs Found",
                                systemImage: "figure.run.circle",
                                description: Text("Go for a run with your Apple Watch and it will appear here.")
                            )
                            .padding(.top, 60)
                        }
                    } else {
                        // List of filtered runs
                        Section(header: Text("Filtered Runs")
                                            .font(.title3.bold())
                                            .padding(.horizontal)
                                            .frame(maxWidth: .infinity, alignment: .leading)) {
                            RunListFilteredView(descriptor: activeDescriptor)
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
                Task {
                    await updateMacroAverages()
                }
            }
            .refreshable {
                if let onSync {
                    isSyncing = true
                    // Detach the sync operation from the refreshable task's strict lifecycle
                    // so it doesn't get cancelled when the view re-renders upon saving the first run.
                    let task = Task {
                        await onSync(false)
                    }
                    // Await its completion so the refresh indicator stays active
                    _ = await task.result
                    isSyncing = false
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

    private func updateMacroAverages() async {
        if #available(iOS 26.0, *) {
            let container = modelContext.container
            let engine = MacroQueryEngine(modelContainer: container)

            let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)

            // 1. Calculate Baselines in Background using the global filter distance
            sevenDayBaseline = try? await engine.calculateRollingAverages(days: 7, minimumDistance: minDistanceInMeters)
            thirtyDayBaseline = try? await engine.calculateRollingAverages(days: 30, minimumDistance: minDistanceInMeters)
            allTimeBaseline = try? await engine.calculateRollingAverages(days: 3650, minimumDistance: minDistanceInMeters) // roughly 10 years for "all time"

            struct SimpleFatigueData: Codable {
                var headline: String
                var observation: String
                var recommendation: String
            }

            // 2. Load Fatigue Insight Caching
            if let cachedData = try? JSONDecoder().decode(SimpleFatigueData.self, from: cachedFatigueInsightData) {
                activeFatigueInsightHeadline = cachedData.headline
                activeFatigueInsightObservation = cachedData.observation
                activeFatigueInsightRecommendation = cachedData.recommendation
            }

            let lastRunDate = runRecords.first?.date.timeIntervalSince1970 ?? 0

            // Only regenerate if the last run is newer than our cache timestamp
            if lastRunDate > lastFatigueInsightDate {
                if let newInsight = try? await engine.generateWeeklyFatigueInsight(minimumDistance: minDistanceInMeters) {
                    activeFatigueInsightHeadline = newInsight.headline
                    activeFatigueInsightObservation = newInsight.observation
                    activeFatigueInsightRecommendation = newInsight.recommendation
                    lastFatigueInsightDate = Date().timeIntervalSince1970

                    let simpleData = SimpleFatigueData(headline: newInsight.headline, observation: newInsight.observation, recommendation: newInsight.recommendation)
                    if let encoded = try? JSONEncoder().encode(simpleData) {
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

// MARK: - Subviews

/// A prominent card view displaying the most recent run's metrics and its associated AI Coaching Insight.
struct HeroCardView: View {
    var runRecord: RunRecord
    var isSyncing: Bool
    var allRuns: [RunRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: runRecord.duration) ?? ""
    }

    // Baseline calculations
    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return allRuns.filter { $0.date < runRecord.date && $0.date >= thirtyDaysAgo }
    }

    private var baselinePace: Double? {
        let runs = baselineRuns
        guard !runs.isEmpty else { return nil }
        return runs.map(\.avgPace).reduce(0, +) / Double(runs.count)
    }

    private var baselineHR: Double? {
        let runs = baselineRuns.filter { $0.avgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.avgHeartRate).reduce(0, +)) / Double(runs.count)
    }

    private var baselineCadence: Double? {
        let runs = baselineRuns.filter { $0.avgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.avgCadence).reduce(0, +)) / Double(runs.count)
    }

    private var baselineVertOsc: Double? {
        let runs = baselineRuns.filter { $0.verticalOscillation > 0 }
        guard !runs.isEmpty else { return nil }
        return runs.map(\.verticalOscillation).reduce(0, +) / Double(runs.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Metrics Row
            let columns = verticalSizeClass == .regular
                ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                MetricView(title: "Distance", value: String(format: "%.2f %@", distanceConverted, distanceUnit))
                MetricView(title: "Pace", value: runRecord.formattedPace, currentValue: runRecord.avgPace, baselineValue: baselinePace, polarity: .lowerIsBetter)
                MetricView(title: "Time", value: formattedDuration)
                MetricView(title: "HR", value: "\(runRecord.avgHeartRate) BPM", currentValue: Double(runRecord.avgHeartRate), baselineValue: baselineHR, polarity: .lowerIsBetter)
                MetricView(title: "Cadence", value: "\(runRecord.avgCadence) SPM", currentValue: Double(runRecord.avgCadence), baselineValue: baselineCadence, polarity: .higherIsBetter)
                MetricView(title: "Vert. Osc.", value: String(format: "%.1f cm", runRecord.verticalOscillation), currentValue: runRecord.verticalOscillation, baselineValue: baselineVertOsc, polarity: .lowerIsBetter)
            }

            Divider()

            // AI Insight & Drill
            if let insight = runRecord.insight {
                if !insight.headline.isEmpty {
                    Text(insight.headline)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .foregroundColor(.primary)
                }

                if !insight.longitudinalObservation.isEmpty {
                    Text(insight.longitudinalObservation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                // Drill Recommendation
                if (insight.drillRecommendations?.first ?? insight.drillRecommendation) != nil {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.purple)

                        Text("View Suggested Drills")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }

                aiDisclaimerFooter
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    AnimatedLoadingView(
                        text: "Analyzing your run...",
                        isHorizontal: true,
                        imageSize: 24,
                        textFont: .title2.bold(),
                        textColor: .primary,
                        iconColor: .primary,
                        spacing: 12
                    )
                }
                .frame(minHeight: 1)
                .task(id: runRecord.id) {
                    if #available(iOS 26.0, *) {
                        if !isSyncing && runRecord.insight == nil {
                            let container = modelContext.container
                            let runId = runRecord.persistentModelID

                            Task.detached {
                                let analyzer = RunAnalyzerActor(modelContainer: container)
                                await analyzer.generateAnalysis(for: runId)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 1)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(runRecord.insight != nil ? "Latest Insight. \(runRecord.insight!.headline)." : "Analyzing your run...")
    }

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))

                Text("AI-generated insights are for informational purposes only and do not replace professional medical or coaching advice. Always listen to your body.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.top, 4)
    }
}

enum MetricPolarity {
    case higherIsBetter
    case lowerIsBetter
}

/// A small, tappable view displaying a single metric title and its corresponding value.
/// Tapping the view displays an alert with a detailed definition of the metric.
struct MetricView: View {
    let title: String
    let value: String
    var currentValue: Double? = nil
    var baselineValue: Double? = nil
    var polarity: MetricPolarity? = nil

    @State private var showingInfo = false

    private var definition: String {
        switch title.lowercased() {
        case "distance":
            return "The total distance covered during your run."
        case "time":
            return "The total elapsed time of your run."
        case "pace":
            return "Your average speed, measured in minutes per distance unit (mile or kilometer)."
        case "hr":
            return "Your average heart rate during the run in Beats Per Minute (BPM)."
        case "cadence":
            return "Your average step rate, measured in Steps Per Minute (SPM). A higher cadence can reduce impact forces."
        case "vert. osc.":
            return "Vertical Oscillation measures how much your torso bounces up and down with each step. Lower values often indicate better efficiency and less energy wasted fighting gravity."
        default:
            return "A running metric tracked by HealthKit."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let current = currentValue, let baseline = baselineValue, let polarity = polarity {
                    let diff = current - baseline
                    // Add a small epsilon to avoid floating point precision issues showing 0 trend
                    if abs(diff) > 0.01 {
                        let isPositiveTrend = diff > 0
                        let isGood = (polarity == .higherIsBetter) ? isPositiveTrend : !isPositiveTrend

                        Image(systemName: isPositiveTrend ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(isGood ? .green : .red)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(definition)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
    }
}

/// A list row representing a single historical run, displaying its date, distance, pace, and an AI insight tag.
struct RunListRowView: View {
    var runRecord: RunRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(runRecord.date, style: .date)
                    .font(.headline)
                    .foregroundColor(.primary)

                let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                Text(String(format: "%.2f %@ • %@", distanceConverted, distanceUnit, runRecord.formattedPace))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let insight = runRecord.insight {
                let firstDrill = insight.drillRecommendations?.first ?? insight.drillRecommendation
                if let drillTitle = firstDrill?.drillTitle.lowercased() {
                    if drillTitle.contains("cadence") {
                        PillTagView(text: "Cadence", color: .red)
                    } else if drillTitle.contains("tempo") {
                        PillTagView(text: "Tempo", color: .orange)
                    } else if drillTitle.contains("rhythm") {
                        PillTagView(text: "Rhythm", color: .purple)
                    } else if drillTitle.contains("stride") {
                        PillTagView(text: "Form", color: .blue)
                    } else {
                        PillTagView(text: "Analyzed", color: .blue)
                    }
                } else {
                    PillTagView(text: "Analyzed", color: .blue)
                }
            } else {
                PillTagView(text: "Pending", color: .gray)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

/// A small, pill-shaped tag used to categorize runs based on their AI drill recommendations.
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
