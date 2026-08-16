import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    private var recentRunRecords: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return runRecords
        }
        return runRecords.filter { $0.date >= thirtyDaysAgo }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if recentRunRecords.isEmpty {
                        ContentUnavailableView(
                            "No Runs Found",
                            systemImage: "figure.run.circle",
                            description: Text("Go for a run with your Apple Watch and it will appear here.")
                        )
                        .padding(.top, 60)
                    } else {
                        // Hero Card for the latest run insight
                        if let latestRun = recentRunRecords.first {
                            NavigationLink(destination: RunDetailView(runRecord: latestRun)) {
                                HeroCardView(runRecord: latestRun)
                            }
                            .buttonStyle(.plain)
                        }

                        // List of past runs
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Past Runs")
                                .font(.title3.bold())
                                .padding(.horizontal)

                            ForEach(recentRunRecords.indices, id: \.self) { index in
                                let run = recentRunRecords[index]
                                NavigationLink(destination: RunDetailView(runRecord: run)) {
                                    RunListRowView(runRecord: run, isLatest: index == 0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
    }
}

// MARK: - Subviews

struct HeroCardView: View {
    var runRecord: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Insight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(runRecord.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let insight = runRecord.insight {
                Text(insight.headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .foregroundColor(.primary)

                Text(insight.longitudinalObservation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                Text("Analyzing your run...")
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(runRecord.insight != nil ? "Latest Insight. \(runRecord.insight!.headline)." : "Analyzing your run...")
    }
}

struct RunListRowView: View {
    var runRecord: RunRecord
    var isLatest: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(runRecord.date, style: .date)
                    .font(.headline)

                Text(String(format: "%.2f km • %@", runRecord.distance / 1000.0, runRecord.formattedPace))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Dynamic Pill Tag
            if isLatest {
                PillTagView(text: "Latest", color: .purple)
            } else if let insight = runRecord.insight {
                if insight.longitudinalObservation.lowercased().contains("cadence") {
                    PillTagView(text: "Cadence: \(runRecord.avgCadence)", color: .red)
                } else if insight.longitudinalObservation.lowercased().contains("heart") || insight.longitudinalObservation.lowercased().contains("aerobic") {
                    PillTagView(text: "HR: \(runRecord.avgHeartRate)", color: .green)
                } else {
                    PillTagView(text: "Analyzed", color: .blue)
                }
            } else {
                PillTagView(text: "Pending", color: .gray)
            }
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
