import SwiftUI

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Top: 2x2 Grid of Raw Stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatBox(title: "Distance", value: String(format: "%.2f", runRecord.distance / 1000.0), unit: "km")

                    let minutes = Int(runRecord.duration) / 60
                    let seconds = Int(runRecord.duration) % 60
                    StatBox(title: "Total Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min")

                    StatBox(title: "Avg Pace", value: runRecord.formattedPace, unit: "/km")
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

                        Text(insight.headline)
                            .font(.title3.bold())
                            .foregroundColor(.primary)

                        Text(insight.longitudinalObservation)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
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

                            Text(drill.title)
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 12) {
                                DrillRow(icon: "repeat", text: drill.reps)
                                DrillRow(icon: "lungs", text: drill.recovery)
                                DrillRow(icon: "brain.head.profile", text: drill.cues)
                            }

                            if let target = drill.targetCadence, let prev = drill.previousCadence {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cadence Goal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Current: \(prev) SPM → Target: \(target) SPM")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                }
                                .padding(.top, 4)
                            }

                            Divider()

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
                    .padding(32)
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
