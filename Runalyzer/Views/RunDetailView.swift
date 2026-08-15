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

                    StatBox(title: "Avg Pace", value: String(format: "%.2f", runRecord.avgPace), unit: "/km")
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

                        Text(insight.observation)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    // Bottom: Drill Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundColor(.blue)
                            Text("Suggested Drill")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                        }

                        Text(insight.drillTitle)
                            .font(.headline)

                        Text(insight.drillInstructions)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Toggle(isOn: Bindable(insight).isDrillCompleted) {
                            Text("Mark as Completed")
                                .font(.subheadline.bold())
                        }
                        .tint(.blue)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

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
    }
}
