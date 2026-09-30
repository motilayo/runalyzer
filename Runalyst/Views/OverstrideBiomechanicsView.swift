import SwiftUI

/// Mode selector for the biomechanics vector diagram
enum BiomechanicsDiagramMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case goodStride = "Good Stride"
    case overstride = "Overstriding"

    var id: String { rawValue }
}

/// A native SwiftUI free-body diagram showing Center of Mass (COM) alignment,
/// landing distance, and ground reaction force vectors.
struct BiomechanicsForceDiagramView: View {
    let isOverstride: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Kinematic Vector Canvas
            ZStack(alignment: .topLeading) {
                // Background surface
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(UIColor.tertiarySystemFill).opacity(0.6))

                VStack(spacing: 0) {
                    // Top: Center of Mass & Body Lean Indicator
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Center of Mass (COM)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            Text(isOverstride ? "Upright Torso (0° Lean)" : "Forward Lean (6°–8° from ankles)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(isOverstride ? "Overstride (>30cm ahead)" : "Neutral Strike (<10cm)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((isOverstride ? Color.red : Color.teal).opacity(0.15))
                            .foregroundColor(isOverstride ? .red : .teal)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    Spacer(minLength: 16)

                    // Middle: Free-body alignment diagram
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let comX = w * 0.40
                        let groundY = h - 22.0
                        let strikeX = isOverstride ? (w * 0.82) : (w * 0.45)

                        ZStack {
                            // Ground Plane Line
                            Path { path in
                                path.move(to: CGPoint(x: 10, y: groundY))
                                path.addLine(to: CGPoint(x: w - 10, y: groundY))
                            }
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 2)

                            // COM Dotted Plumb Line (vertical gravity axis)
                            Path { path in
                                path.move(to: CGPoint(x: comX, y: 12))
                                path.addLine(to: CGPoint(x: comX, y: groundY))
                            }
                            .stroke(
                                Color.green.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                            )

                            // COM Pivot Indicator (Pelvis / Core)
                            Circle()
                                .fill(Color.green)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .position(x: comX, y: 12)

                            // Leg Angle Guideline (COM to Foot Strike)
                            Path { path in
                                path.move(to: CGPoint(x: comX, y: 12))
                                if isOverstride {
                                    // Straight, stiff leg
                                    path.addLine(to: CGPoint(x: strikeX, y: groundY))
                                } else {
                                    // Flexed knee spring joint
                                    let kneeX = (comX + strikeX) / 2 + 10
                                    let kneeY = (12 + groundY) / 2
                                    path.addLine(to: CGPoint(x: kneeX, y: kneeY))
                                    path.addLine(to: CGPoint(x: strikeX, y: groundY))
                                }
                            }
                            .stroke(
                                (isOverstride ? Color.red : Color.teal).opacity(0.7),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                            )

                            // Knee Joint Marker
                            if !isOverstride {
                                let kneeX = (comX + strikeX) / 2 + 10
                                let kneeY = (12 + groundY) / 2
                                Circle()
                                    .fill(Color.teal)
                                    .frame(width: 8, height: 8)
                                    .position(x: kneeX, y: kneeY)
                            }

                            // Horizontal Offset Bracket (between COM and Foot Strike)
                            if isOverstride {
                                Path { path in
                                    let bracketY = groundY + 10
                                    path.move(to: CGPoint(x: comX, y: bracketY - 3))
                                    path.addLine(to: CGPoint(x: comX, y: bracketY))
                                    path.addLine(to: CGPoint(x: strikeX, y: bracketY))
                                    path.addLine(to: CGPoint(x: strikeX, y: bracketY - 3))
                                }
                                .stroke(Color.red, lineWidth: 1.2)
                            }

                            // Foot Strike Point Marker
                            Circle()
                                .fill(isOverstride ? Color.red : Color.teal)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .position(x: strikeX, y: groundY)
                        }
                    }
                    .frame(height: 75)

                    // Bottom: Force Vector Legend
                    HStack(spacing: 12) {
                        if isOverstride {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                                Text("Braking Vector (Deceleration)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                                Text("High Vertical Shock")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.teal)
                                Text("Forward Propulsion (Elastic Recoil)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.teal)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "spring")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.teal)
                                Text("Bent-Knee Shock Dampening")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.teal)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .frame(height: 145)
        }
    }
}

/// A clean illustration card representing either Good Stride or Overstriding
/// using pure native SwiftUI vector graphics and kinematic checklists.
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

            // Native SwiftUI Biomechanical Free-Body Diagram
            BiomechanicsForceDiagramView(isOverstride: isOverstride)

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
