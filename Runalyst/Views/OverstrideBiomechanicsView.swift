import SwiftUI

/// Mode selector for the biomechanics vector diagram
enum BiomechanicsDiagramMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case goodStride = "Good Stride"
    case overstride = "Overstriding"

    var id: String { rawValue }
}

/// A clean illustration card representing either Good Stride or Overstriding
/// using high-resolution sports-science biomechanical graphics.
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

            // High-Resolution Sports-Science Biomechanical Illustration
            Image(isOverstride ? "OverstrideIllustration" : "GoodStrideIllustration")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke((isOverstride ? Color.red : Color.teal).opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)

            // Kinematic Point Checklist
            VStack(alignment: .leading, spacing: 6) {
                if isOverstride {
                    KinematicPointRow(
                        title: "Foot Strike Ahead of COM (>30cm)",
                        subtitle: "Foot lands with large forward tibial angle, producing heavy braking forces.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "Reduced Knee Flexion",
                        subtitle: "Straightened knee cannot act as a spring, sending vertical impact up into joints.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "High Braking & Vertical Impact",
                        subtitle: "Braking force redirects horizontal speed into high vertical bounce (>10 cm).",
                        isPositive: false
                    )
                } else {
                    KinematicPointRow(
                        title: "Foot Strike Close to COM",
                        subtitle: "Foot lands under pelvis with forward body lean, directing force horizontally.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Good Knee Flexion",
                        subtitle: "Flexed knee absorbs landing load naturally through the quadriceps and elastic recoil.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Small Tibial Angle & Push-Off",
                        subtitle: "Nearly vertical shin on landing unlocks rearward glute push-off.",
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
                    good: "Under pelvis (<10cm)",
                    overstride: "Cast ahead (>30cm)"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Knee Angle",
                    good: "Flexed (~25° bend)",
                    overstride: "Locked / Stiff (<10°)"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Body Lean",
                    good: "Slight forward (6°–8°)",
                    overstride: "Upright / Backward"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Primary Force",
                    good: "Horizontal Propulsion",
                    overstride: "Braking & Vertical Bounce"
                )
                Divider()
                ComparisonRowItem(
                    variable: "Joint Load",
                    good: "Muscular absorption",
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
                    explanation: "Landing stiff-legged sends kinetic impact straight up, creating high bounce instead of forward speed."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Ground Contact Time",
                    goodRange: "200 – 240 ms",
                    overstrideRange: "> 260 ms",
                    explanation: "A braking foot must stay glued to the asphalt while your center of mass slowly rolls over the ankle."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Cadence Turnover",
                    goodRange: "165 – 180 SPM",
                    overstrideRange: "< 155 SPM",
                    explanation: "Slow turnover gives the lead leg time to cast forward; quick steps force feet to land under the hips."
                )

                Divider()

                TelemetryComparisonRow(
                    metricName: "Vertical Ratio",
                    goodRange: "< 8.0 %",
                    overstrideRange: "> 9.5 %",
                    explanation: "Ratio of vertical bounce to stride length. Lower means energy propels forward rather than upward."
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
                    cue: "“Get feet off the ground quickly”",
                    focus: "Focus on pulling your foot up off the tarmac rather than pushing down. Naturally quickens cadence."
                )
                CueItemRow(
                    cue: "“Run on ice”",
                    focus: "Promotes delicate, quiet footfalls with bent knees to dampen impact shock."
                )
                CueItemRow(
                    cue: "“High knees and low ankles”",
                    focus: "Keeps your lower leg tucked under the knee, preventing the foot from reaching forward."
                )
                CueItemRow(
                    cue: "“Push through your glutes behind you”",
                    focus: "Lengthens your stride behind your body with full hip extension without reaching ahead."
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
