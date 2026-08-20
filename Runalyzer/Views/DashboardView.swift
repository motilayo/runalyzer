import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        return runRecords.filter { $0.distance >= (minDistanceInMeters - 0.01) }
    }

    var onSync: (() async -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if filteredRunRecords.isEmpty {
                        if runRecords.isEmpty {
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
                            NavigationLink(destination: RunDetailView(runRecord: latestRun)) {
                                HeroCardView(runRecord: latestRun)
                            }
                            .buttonStyle(.plain)
                        }

                        // List of past runs
                        if filteredRunRecords.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Past Runs")
                                    .font(.title3.bold())
                                    .padding(.horizontal)

                                let pastRuns = Array(filteredRunRecords.dropFirst())
                                ForEach(Array(pastRuns.enumerated()), id: \.offset) { index, run in
                                    NavigationLink(destination: RunDetailView(runRecord: run)) {
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
            .refreshable {
                if let onSync {
                    // Detach the sync operation from the refreshable task's strict lifecycle
                    // so it doesn't get cancelled when the view re-renders upon saving the first run.
                    let task = Task {
                        await onSync()
                    }
                    // Await its completion so the refresh indicator stays active
                    _ = await task.result
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(onForceSync: onSync)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct HeroCardView: View {
    var runRecord: RunRecord
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
            }

            // Metrics Row
            HStack(spacing: 20) {
                let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                MetricView(title: "Distance", value: String(format: "%.2f %@", distanceConverted, distanceUnit))
                MetricView(title: "Pace", value: runRecord.formattedPace)
                MetricView(title: "Time", value: formattedDuration)
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
                        if !drill.drillReps.isEmpty || !drill.drillRecovery.isEmpty {
                            Text("\(drill.drillReps) • \(drill.drillRecovery)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !drill.drillCues.isEmpty {
                            Text(drill.drillCues)
                                .font(.caption)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }
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
}

struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

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
                if insight.longitudinalObservation.lowercased().contains("cadence") {
                    PillTagView(text: "Cadence", color: .red)
                } else if insight.longitudinalObservation.lowercased().contains("heart") || insight.longitudinalObservation.lowercased().contains("aerobic") {
                    PillTagView(text: "HR", color: .green)
                } else {
                    PillTagView(text: "Analyzed", color: .blue)
                }
            } else {
                PillTagView(text: "Pending", color: .gray)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.tertiaryLabel)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
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
