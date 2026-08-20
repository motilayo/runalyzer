import SwiftUI
import SwiftData

@available(iOS 26.0, *)
struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @Environment(\.modelContext) private var modelContext
    @Query private var existingRuns: [RunRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Top: 2x2 Grid of Raw Stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                    let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit)

                    let minutes = Int(runRecord.duration) / 60
                    let seconds = Int(runRecord.duration) % 60
                    StatBox(title: "Total Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min")

                    StatBox(title: "Avg Pace", value: runRecord.formattedPace, unit: "")
                    StatBox(title: "Avg HR", value: "\(runRecord.avgHeartRate)", unit: "BPM")
                }
                .padding(.horizontal)

                if let insight = runRecord.insight {
                    // Middle: AI Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("AI Analysis")
                                .font(.subheadline.bold())
                                .foregroundColor(.purple)
                        }

                        if !insight.headline.isEmpty {
                            Text(insight.headline)
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                        }

                        if !insight.longitudinalObservation.isEmpty {
                            Text(insight.longitudinalObservation)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minHeight: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    // Bottom: Drill Card
                    if let drill = insight.drillRecommendation {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "figure.run")
                                    .foregroundColor(.blue)
                                Text("Suggested Drill")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                            }

                            if !drill.drillTitle.isEmpty {
                                Text(drill.drillTitle)
                                    .font(.headline)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                DrillRow(icon: "repeat", text: drill.drillReps)
                                DrillRow(icon: "lungs", text: drill.drillRecovery)
                                DrillRow(icon: "brain.head.profile", text: drill.drillCues)
                            }

                            if let target = drill.targetCadence, let prev = drill.previousCadence, !target.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cadence Goal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Current: \(prev) SPM → Target: \(target)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                }
                                .padding(.top, 4)
                            }

                            VStack(spacing: 0) {
                                Divider()
                            }
                            .padding(.vertical, 4)

                            Toggle(isOn: Bindable(drill).isCompleted) {
                                Text("Mark as Completed")
                                    .font(.subheadline.bold())
                            }
                            .tint(.blue)
                            .onChange(of: drill.isCompleted) { _, newValue in
                                if newValue {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                            }
                        }
                        .frame(minHeight: 1)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(20)
                        .padding(.horizontal)
                    }

                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Generating insights locally on your device...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minHeight: 1)
                    .padding(32)
                    .task {
                        if runRecord.insight == nil {
                            do {
                                let history = existingRuns.sorted(by: { $0.date > $1.date })
                                let insight = try await CoachingEngine.shared.generateInsight(for: runRecord, history: history)
                                runRecord.insight = insight
                                try modelContext.save()
                            } catch {
                                print("Failed to generate AI insight for run \(runRecord.id): \(error)")
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(runRecord.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatBox: View {
    var title: String
    var value: String
    var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit)")
    }
}

struct DrillRow: View {
    var icon: String
    var text: String

    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
