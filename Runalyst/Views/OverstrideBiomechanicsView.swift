import SwiftUI

/// Mode selector for the biomechanics guide
enum BiomechanicsDiagramMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case goodStride = "Good Stride"
    case overstride = "Overstriding"

    var id: String { rawValue }
}

/// A biomechanical summary card representing either Good Stride or Overstriding.
struct BiomechanicalCardView: View {
    let isOverstride: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Badge
            HStack {
                Label(
                    isOverstride ? "Overstriding (Braking Force)" : "Good Stride (Spring Elasticity)",
                    systemImage: isOverstride ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
                )
                .font(.subheadline.bold())
                .foregroundColor(isOverstride ? .red : .teal)

                Spacer()

                Text(isOverstride ? "High Impact" : "Energy Efficient")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isOverstride ? Color.red : Color.teal).opacity(0.14))
                    .foregroundColor(isOverstride ? .red : .teal)
                    .clipShape(Capsule())
            }

            // Core Explainer Concept
            VStack(alignment: .leading, spacing: 6) {
                Text("Where Should Your Foot Land?")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text("Ideally, your foot should land beneath your center of mass rather than reaching out ahead of your body.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("While there is no single \"best\" foot strike, landing closer to your hips reduces braking forces so you can run comfortably, efficiently, and injury-free.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.vertical, 4)

            // Kinematic Point Checklist
            VStack(alignment: .leading, spacing: 6) {
                if isOverstride {
                    KinematicPointRow(
                        title: "Landing Ahead of Center of Mass (> 30 cm)",
                        subtitle: "Your foot reaches forward with an angled shin, producing heavy braking forces against the ground.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "Locked Knee on Landing",
                        subtitle: "A rigid, straightened knee cannot absorb shock like a spring, sending impact directly into your joints.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "High Braking & Vertical Bounce",
                        subtitle: "Each braking step halts forward momentum, redirecting your energy into a high vertical bounce (> 10 cm).",
                        isPositive: false
                    )
                } else {
                    KinematicPointRow(
                        title: "Landing Close to Center of Mass",
                        subtitle: "Your foot lands underneath your hips with a slight forward lean from the ankles, directing force horizontally.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Soft, Flexed Knee",
                        subtitle: "A bent knee cushions the landing naturally through muscle engagement and elastic recoil.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Near-Vertical Shin & Push-Off",
                        subtitle: "Landing with a nearly vertical shin lets you roll smoothly into a powerful push-off behind you.",
                        isPositive: true
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
}

/// Explanatory bullet row for kinematic behaviors
private struct KinematicPointRow: View {
    let title: String
    let subtitle: String
    let isPositive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isPositive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isPositive ? .teal : .red)
                .font(.caption)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Comparative Matrix comparing mechanical variables side-by-side
struct KinematicComparisonMatrixView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.and.right.square.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text("Kinematic Comparison Matrix")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ComparisonRowItem(
                    variable: "Landing Point",
                    good: "Under hips (< 10 cm)",
                    overstride: "Cast forward (> 30 cm)"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Knee Angle",
                    good: "Flexed (~25° bend)",
                    overstride: "Locked / Stiff (< 10°)"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Body Lean",
                    good: "Slight forward (6°–8°)",
                    overstride: "Upright or leaning back"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Primary Force",
                    good: "Horizontal propulsion",
                    overstride: "Braking & upward bounce"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Impact Absorption",
                    good: "Muscular spring recoil",
                    overstride: "Joint & shin impact"
                )
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(14)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
}

private struct ComparisonRowItem: View {
    let variable: String
    let good: String
    let overstride: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(variable)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.teal)
                        .font(.system(size: 10))
                    Text(good)
                        .font(.caption.bold())
                        .foregroundColor(.teal)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 10))
                    Text(overstride)
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Telemetry Bridge card linking lab biomechanics to wrist-based Apple Watch metrics
struct AppleWatchBiomechanicsBridgeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundColor(.purple)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How Apple Watch Detects This")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Translating wrist inertial sensors into foot-strike mechanics")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TelemetryComparisonRow(
                    metricName: "Vertical Oscillation",
                    goodRange: "6.0 – 9.0 cm",
                    overstrideRange: "> 10.0 cm",
                    explanation: "Landing on a stiff leg sends impact straight up, creating excess vertical bounce instead of forward speed."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Ground Contact Time",
                    goodRange: "200 – 240 ms",
                    overstrideRange: "> 260 ms",
                    explanation: "When your foot lands too far ahead, it stays on the ground longer as your body slowly rolls over the ankle before pushing off."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Cadence",
                    goodRange: "165 – 180 SPM",
                    overstrideRange: "< 155 SPM",
                    explanation: "A slower cadence gives your lead leg time to reach too far forward. Quicker steps naturally encourage your feet to land beneath your hips."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Vertical Ratio",
                    goodRange: "< 8.0%",
                    overstrideRange: "> 9.5%",
                    explanation: "This measures vertical bounce as a percentage of stride length. Lower percentages mean more of your energy propels you forward rather than upward."
                )
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(14)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
}

/// A comparison row showing good vs overstride telemetry
private struct TelemetryComparisonRow: View {
    let metricName: String
    let goodRange: String
    let overstrideRange: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metricName)
                    .font(.caption.bold())
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    Text(goodRange)
                        .font(.caption2.bold())
                        .foregroundColor(.teal)
                    Text("vs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(overstrideRange)
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                }
            }

            Text(explanation)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineSpacing(1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Visual Mental Cues section helping the athlete apply these corrections during runs
struct CorrectiveCuesCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "figure.mind.and.body")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Coaching Cues to Prevent Overstriding")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                CueItemRow(
                    cue: "“Quick off the ground”",
                    focus: "Focus on lifting your foot off the ground rather than stomping down. This naturally quickens your cadence and shortens ground contact."
                )
                CueItemRow(
                    cue: "“Run on ice”",
                    focus: "Encourages soft, quiet landings with bent knees to absorb impact smoothly and stay light on your feet."
                )
                CueItemRow(
                    cue: "“High knees, low ankles”",
                    focus: "Keeps your lower leg tucked comfortably beneath the knee, preventing your foot from casting out ahead."
                )
                CueItemRow(
                    cue: "“Drive through your glutes”",
                    focus: "Lengthens your stride behind you through full hip extension rather than overreaching out in front."
                )
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
}

private struct CueItemRow: View {
    let cue: String
    let focus: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(cue)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(focus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Complete standalone bottom-sheet modal or embeddable screen detailing overstriding biomechanics
struct OverstrideBiomechanicsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: BiomechanicsDiagramMode = .compare

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Segmented Mode Selector
                    Picker("Biomechanics View", selection: $mode) {
                        ForEach(BiomechanicsDiagramMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 4)

                    // Diagram Content
                    switch mode {
                    case .compare:
                        VStack(spacing: 14) {
                            KinematicComparisonMatrixView()
                            BiomechanicalCardView(isOverstride: false)
                            BiomechanicalCardView(isOverstride: true)
                        }
                        .padding(.horizontal)

                    case .goodStride:
                        BiomechanicalCardView(isOverstride: false)
                            .padding(.horizontal)

                    case .overstride:
                        BiomechanicalCardView(isOverstride: true)
                            .padding(.horizontal)
                    }

                    // Apple Watch Sensor Connection
                    AppleWatchBiomechanicsBridgeView()
                        .padding(.horizontal)

                    // Mental Cues
                    CorrectiveCuesCardView()
                        .padding(.horizontal)

                    // Standard AI & Medical Disclaimer
                    AIDisclaimerFooter()
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Running Biomechanics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                }
            }
        }
    }
}

#Preview {
    OverstrideBiomechanicsSheet()
}
