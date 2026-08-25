import SwiftUI
import SwiftData

/// A detailed view for a single `RunRecord`, displaying in-depth metrics and the full AI Coaching Insight.
///
/// This view includes a grid of physiological and biomechanical stats, followed by the AI-generated
/// observation and the specific actionable technique drill prescribed by the Foundation Model.
struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var existingRuns: [RunRecord]

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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Top: Responsive 6-Card Grid of Raw Stats
                let columns = verticalSizeClass == .regular
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

                LazyVGrid(columns: columns, spacing: 16) {
                    let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                    let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit)

                    let minutes = Int(runRecord.duration) / 60
                    let seconds = Int(runRecord.duration) % 60
                    StatBox(title: "Total Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min")

                    StatBox(title: "Avg Pace", value: runRecord.formattedPace, unit: "")
                    StatBox(title: "Avg HR", value: "\(runRecord.avgHeartRate)", unit: "BPM")
                    StatBox(title: "Avg Cadence", value: "\(runRecord.avgCadence)", unit: "SPM")
                    StatBox(title: "Vert. Osc.", value: String(format: "%.1f", runRecord.verticalOscillation), unit: "cm")
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

                        aiDisclaimerFooter
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
                                DrillRow(icon: "target", text: drill.drillPurpose ?? "")
                                DrillRow(icon: "repeat", text: drill.drillWork ?? "")
                                DrillRow(icon: "brain.head.profile", text: drill.drillCues ?? "")
                                DrillRow(icon: "bolt", text: drill.drillEffort ?? "")
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
                    VStack(spacing: 20) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                            .symbolEffect(.variableColor.iterative.reversing)
                        Text("Generating Coaching Insight...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minHeight: 1)
                    .padding(32)
                    .task(id: runRecord.persistentModelID) {
                        if #available(iOS 26.0, *) {
                            if runRecord.insight == nil {
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
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(runRecord.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A tappable statistic box displaying a specific metric for a run.
/// Tapping it presents an alert with a detailed definition of the metric.
struct StatBox: View {
    var title: String
    var value: String
    var unit: String

    @State private var showingInfo = false

    private var definition: String {
        switch title.lowercased() {
        case "distance":
            return "The total distance covered during your run."
        case "total time":
            return "The total elapsed time of your run."
        case "avg pace":
            return "Your average speed, measured in minutes per distance unit (mile or kilometer)."
        case "avg hr":
            return "Your average heart rate during the run in Beats Per Minute (BPM)."
        case "avg cadence":
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit). Double tap for definition.")
    }
}

/// A styled row within a drill recommendation card, combining a system icon with a descriptive text.
struct DrillRow: View {
    var icon: String
    var text: String

    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .top)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
