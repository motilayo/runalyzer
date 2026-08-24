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

    @State private var isSyncing: Bool = true

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        return runRecords.filter { $0.distance >= (minDistanceInMeters - 0.01) }
    }

    // 1. Get the most recent valid VO2 Max score
    var latestVO2Max: Double? {
        runRecords.first(where: { $0.vo2Max > 0 })?.vo2Max
    }

    // 2. Calculate the trend against the 30 days prior to that recent score
    var vo2MaxTrend: Double? {
        let validRuns = runRecords.filter { $0.vo2Max > 0 }

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

    // 1. The 30-Day Average Cadence (SPM)
    var baselineCadence: Int? {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }

        // Filter for runs in the last 30 days that have a valid cadence
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.avgCadence > 0 }
        guard !recentRuns.isEmpty else { return nil }

        // Calculate the average
        let totalCadence = recentRuns.map(\.avgCadence).reduce(0, +)
        return totalCadence / recentRuns.count
    }

    // 2. The 30-Day Average Pace (Optional, but great for a baseline card)
    var baselinePace: Double? {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo }
        guard !recentRuns.isEmpty else { return nil }

        return recentRuns.map(\.avgPace).reduce(0, +) / Double(recentRuns.count)
    }

    var onSync: (() async -> Void)? = nil

    @ViewBuilder
    private var fitnessBaselineCard: some View {
        if let currentVO2 = latestVO2Max {
            VStack(spacing: 12) {
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

                HStack {
                    // LEFT SIDE: 30-Day Avg Cadence
                    if let avgCadence = baselineCadence {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("30-DAY AVG CADENCE")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)
                            Text("\(avgCadence) SPM")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }

                    Spacer()

                    // RIGHT SIDE: 30-Day Avg Pace
                    if let avgPace = baselinePace {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("30-DAY AVG PACE")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)

                            // Format the Double (minutes) into a M:SS string
                            let minutes = Int(avgPace)
                            let seconds = Int((avgPace - Double(minutes)) * 60)
                            Text(String(format: "%d:%02d/km", minutes, seconds))
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
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Global Fitness Pill (VO2 Max)
                    fitnessBaselineCard

                    if filteredRunRecords.isEmpty {
                        if isSyncing && runRecords.isEmpty {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Analyzing your running history...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
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
                        // Hero Card for the latest run insight
                        if let latestRun = filteredRunRecords.first {
                            NavigationLink(value: latestRun) {
                                HeroCardView(runRecord: latestRun, isSyncing: isSyncing)
                            }
                            .buttonStyle(.plain)
                        }

                        // List of past runs
                        if filteredRunRecords.count > 1 {
                            Section(header: Text("Past Runs")
                                                .font(.title3.bold())
                                                .padding(.horizontal)
                                                .frame(maxWidth: .infinity, alignment: .leading)) {
                                let pastRuns = Array(filteredRunRecords.dropFirst())
                                ForEach(pastRuns) { run in
                                    NavigationLink(value: run) {
                                        RunListRowView(runRecord: run)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
                    await onSync()
                    isSyncing = false
                }
            }
            .refreshable {
                if let onSync {
                    isSyncing = true
                    // Detach the sync operation from the refreshable task's strict lifecycle
                    // so it doesn't get cancelled when the view re-renders upon saving the first run.
                    let task = Task {
                        await onSync()
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
}

// MARK: - Subviews

/// A prominent card view displaying the most recent run's metrics and its associated AI Coaching Insight.
struct HeroCardView: View {
    var runRecord: RunRecord
    var isSyncing: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: runRecord.duration) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Latest Run
            HStack {
                Text("Latest Run Insight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(runRecord.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }

            // Metrics Row
            let columns = verticalSizeClass == .regular
                ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                MetricView(title: "Distance", value: String(format: "%.2f %@", distanceConverted, distanceUnit))
                MetricView(title: "Pace", value: runRecord.formattedPace)
                MetricView(title: "Time", value: formattedDuration)
                MetricView(title: "HR", value: "\(runRecord.avgHeartRate) BPM")
                MetricView(title: "Cadence", value: "\(runRecord.avgCadence) SPM")
                MetricView(title: "Vert. Osc.", value: String(format: "%.1f cm", runRecord.verticalOscillation))
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
                if let drill = insight.drillRecommendation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundColor(.purple)
                            Text("Recommended Drill")
                                .font(.headline)
                                .foregroundColor(.purple)
                        }

                        if !drill.drillTitle.isEmpty {
                            Text(drill.drillTitle)
                                .font(.subheadline.bold())
                        }
                        if let work = drill.drillWork, !work.isEmpty {
                            Text(work)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let cues = drill.drillCues, !cues.isEmpty {
                            Text(cues)
                                .font(.caption)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }

                aiDisclaimerFooter
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing your run...")
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    ProgressView()
                        .padding(.top, 4)
                }
                .frame(minHeight: 1)

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

/// A small, tappable view displaying a single metric title and its corresponding value.
/// Tapping the view displays an alert with a detailed definition of the metric.
struct MetricView: View {
    let title: String
    let value: String

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
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingInfo = true
        }
        .alert(title, isPresented: $showingInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(definition)
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
                if let drillTitle = insight.drillRecommendation?.drillTitle.lowercased() {
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
