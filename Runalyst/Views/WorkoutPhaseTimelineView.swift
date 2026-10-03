import SwiftUI

/// A minimalist, horizontally scrolling timeline UI representing the structured phases of a pre-run workout.
/// Translates complex WorkoutKit phase data into plain English and visual geometry using native SwiftUI shapes.
struct WorkoutPhaseTimelineView: View {
    let phases: [WorkoutPhase]
    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showHeader {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text("Breakdown")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(totalDurationString)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.85))
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text("Warm-up").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Work").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color(UIColor.systemGray4)).frame(width: 6, height: 6)
                        Text("Walk / Rest").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(totalDurationString)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(phases) { phase in
                        VStack(spacing: 4) {
                            // Visual phase block / spike
                            RoundedRectangle(cornerRadius: 4)
                                .fill(blockColor(for: phase.kind))
                                .frame(width: blockWidth(for: phase), height: blockHeight(for: phase.kind))

                            // Plain English phase title
                            Text(phase.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(1)

                            // Duration badge
                            Text(phase.formattedDuration)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemFill).opacity(0.6))
        .cornerRadius(12)
    }

    private var totalDurationString: String {
        let totalSec = phases.reduce(0) { $0 + $1.durationSeconds }
        let mins = totalSec / 60
        let secs = totalSec % 60
        if secs == 0 {
            return "\(mins) min total"
        } else {
            return "\(mins)m \(secs)s total"
        }
    }

    private func blockColor(for kind: WorkoutPhase.Kind) -> Color {
        switch kind {
        case .warmup:
            return Color.blue
        case .work:
            return Color.orange
        case .recovery:
            return Color(UIColor.systemGray4)
        case .cooldown:
            return Color.blue.opacity(0.7)
        case .steady:
            return Color.blue
        }
    }

    private func blockHeight(for kind: WorkoutPhase.Kind) -> CGFloat {
        switch kind {
        case .work:
            return 38 // Tall spike
        case .warmup, .cooldown:
            return 22 // Mid-height block
        case .recovery:
            return 14 // Flat block
        case .steady:
            return 26
        }
    }

    private func blockWidth(for phase: WorkoutPhase) -> CGFloat {
        switch phase.kind {
        case .warmup:
            return 64 // Long block
        case .cooldown:
            return 56
        case .steady:
            return 100
        case .work:
            return 28 // Short spike
        case .recovery:
            return 28 // Flat block
        }
    }
}
