import SwiftUI

/// Mode selector for the biomechanics vector diagram
enum BiomechanicsDiagramMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case goodStride = "Good Stride"
    case overstride = "Overstriding"

    var id: String { rawValue }
}

/// A native SwiftUI free-body diagram showing Center of Mass (COM) alignment,
/// athletic running stick figure kinematics, and ground reaction force vectors.
struct BiomechanicsForceDiagramView: View {
    let isOverstride: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(UIColor.tertiarySystemFill).opacity(0.6))

                VStack(spacing: 4) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isOverstride ? Color.red : Color.teal)
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

                    // Athletic Running Stick Figure Canvas
                    RunningStickFigureCanvas(isOverstride: isOverstride)
                        .padding(.horizontal, 8)

                    // Force Vector Legend
                    HStack(spacing: 12) {
                        if isOverstride {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                                Text("Braking Force")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                                Text("Vertical Shock Impact")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.teal)
                                Text("Forward Propulsion")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.teal)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "shield.fill")
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
        }
    }
}

/// Canvas rendering an athletic running stick figure with realistic joint angles
private struct RunningStickFigureCanvas: View {
    let isOverstride: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let groundY: CGFloat = 115.0

            // Baseline Ground Plane
            var ground = Path()
            ground.move(to: CGPoint(x: 10, y: groundY))
            ground.addLine(to: CGPoint(x: w - 10, y: groundY))
            context.stroke(
                ground,
                with: .color(Color.secondary.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )

            if isOverstride {
                drawOverstrideRunner(context: context, size: size, groundY: groundY)
            } else {
                drawGoodStrideRunner(context: context, size: size, groundY: groundY)
            }
        }
        .frame(height: 135)
    }

    private func drawGoodStrideRunner(context: GraphicsContext, size: CGSize, groundY: CGFloat) {
        let comX = size.width * 0.46
        let pelvisY: CGFloat = 58.0
        let shoulderX = comX + 10.0
        let shoulderY = pelvisY - 32.0

        // 1. Center of Mass Vertical Plumb Line
        var plumbLine = Path()
        plumbLine.move(to: CGPoint(x: comX, y: pelvisY))
        plumbLine.addLine(to: CGPoint(x: comX, y: groundY))
        context.stroke(
            plumbLine,
            with: .color(Color.teal.opacity(0.65)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )

        // 2. Trailing Arm (Driving backward)
        var backArm = Path()
        backArm.move(to: CGPoint(x: shoulderX, y: shoulderY))
        backArm.addLine(to: CGPoint(x: shoulderX - 14, y: shoulderY + 12))
        backArm.addLine(to: CGPoint(x: shoulderX - 24, y: shoulderY + 22))
        context.stroke(
            backArm,
            with: .color(Color.secondary.opacity(0.7)),
            style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
        )

        // 3. Trailing Leg (Full hip extension & glute push-off behind)
        var backLeg = Path()
        backLeg.move(to: CGPoint(x: comX, y: pelvisY))
        backLeg.addLine(to: CGPoint(x: comX - 22, y: pelvisY + 20))
        backLeg.addLine(to: CGPoint(x: comX - 44, y: pelvisY + 40))
        backLeg.addLine(to: CGPoint(x: comX - 52, y: pelvisY + 46))
        context.stroke(
            backLeg,
            with: .color(Color.secondary.opacity(0.75)),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        )

        // 4. Torso with Athletic Forward Lean (6°–8°)
        var torso = Path()
        torso.move(to: CGPoint(x: comX, y: pelvisY))
        torso.addLine(to: CGPoint(x: shoulderX, y: shoulderY))
        context.stroke(
            torso,
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
        )

        // 5. Head
        let headCenter = CGPoint(x: shoulderX + 4, y: shoulderY - 12)
        let headRect = CGRect(x: headCenter.x - 8, y: headCenter.y - 8, width: 16, height: 16)
        context.fill(Path(ellipseIn: headRect), with: .color(Color.white))

        // 6. Lead Arm (Bent ~90° swinging forward)
        var frontArm = Path()
        frontArm.move(to: CGPoint(x: shoulderX, y: shoulderY))
        frontArm.addLine(to: CGPoint(x: shoulderX + 16, y: shoulderY + 14))
        frontArm.addLine(to: CGPoint(x: shoulderX + 24, y: shoulderY + 4))
        context.stroke(
            frontArm,
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        )

        // 7. Lead Leg (Bent Knee Spring, Foot landing beneath COM)
        let leadKneeX = comX + 16.0
        let leadKneeY = pelvisY + 28.0
        let leadAnkleX = comX + 6.0 // Landing right under COM plumb line!
        let leadAnkleY = groundY - 2.0

        var leadLeg = Path()
        leadLeg.move(to: CGPoint(x: comX, y: pelvisY))
        leadLeg.addLine(to: CGPoint(x: leadKneeX, y: leadKneeY)) // flexed knee
        leadLeg.addLine(to: CGPoint(x: leadAnkleX, y: leadAnkleY)) // vertical lower leg
        leadLeg.addLine(to: CGPoint(x: leadAnkleX + 14, y: groundY)) // flat midfoot
        context.stroke(
            leadLeg,
            with: .color(Color.teal),
            style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        )

        // Knee joint indicator dot
        let kneeRect = CGRect(x: leadKneeX - 3.5, y: leadKneeY - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: kneeRect), with: .color(Color.teal))

        // 8. Pelvis / COM Marker
        let comRect = CGRect(x: comX - 5.5, y: pelvisY - 5.5, width: 11, height: 11)
        context.fill(Path(ellipseIn: comRect), with: .color(Color.teal))
        context.stroke(
            Path(ellipseIn: comRect),
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 1.8)
        )

        // 9. Forward Propulsion Vector Arrow at foot
        var arrow = Path()
        let arrowStartX = leadAnkleX + 18
        let arrowEndX = arrowStartX + 24
        arrow.move(to: CGPoint(x: arrowStartX, y: groundY))
        arrow.addLine(to: CGPoint(x: arrowEndX, y: groundY))
        arrow.move(to: CGPoint(x: arrowEndX - 5, y: groundY - 3.5))
        arrow.addLine(to: CGPoint(x: arrowEndX, y: groundY))
        arrow.addLine(to: CGPoint(x: arrowEndX - 5, y: groundY + 3.5))
        context.stroke(
            arrow,
            with: .color(Color.teal),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawOverstrideRunner(context: GraphicsContext, size: CGSize, groundY: CGFloat) {
        let comX = size.width * 0.36
        let pelvisY: CGFloat = 58.0
        let shoulderX = comX // Upright torso
        let shoulderY = pelvisY - 32.0

        // 1. Center of Mass Vertical Plumb Line
        var plumbLine = Path()
        plumbLine.move(to: CGPoint(x: comX, y: pelvisY))
        plumbLine.addLine(to: CGPoint(x: comX, y: groundY))
        context.stroke(
            plumbLine,
            with: .color(Color.red.opacity(0.65)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )

        // 2. Trailing Leg (Dragging close to body, poor push-off)
        var backLeg = Path()
        backLeg.move(to: CGPoint(x: comX, y: pelvisY))
        backLeg.addLine(to: CGPoint(x: comX - 14, y: pelvisY + 26))
        backLeg.addLine(to: CGPoint(x: comX - 20, y: groundY - 2))
        backLeg.addLine(to: CGPoint(x: comX - 12, y: groundY))
        context.stroke(
            backLeg,
            with: .color(Color.secondary.opacity(0.6)),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        )

        // 3. Trailing Arm (Stiff)
        var backArm = Path()
        backArm.move(to: CGPoint(x: shoulderX, y: shoulderY))
        backArm.addLine(to: CGPoint(x: shoulderX - 14, y: shoulderY + 12))
        backArm.addLine(to: CGPoint(x: shoulderX - 20, y: shoulderY + 22))
        context.stroke(
            backArm,
            with: .color(Color.secondary.opacity(0.6)),
            style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
        )

        // 4. Torso - Strictly Upright (0° Lean)
        var torso = Path()
        torso.move(to: CGPoint(x: comX, y: pelvisY))
        torso.addLine(to: CGPoint(x: shoulderX, y: shoulderY))
        context.stroke(
            torso,
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
        )

        // 5. Head
        let headCenter = CGPoint(x: shoulderX, y: shoulderY - 12)
        let headRect = CGRect(x: headCenter.x - 8, y: headCenter.y - 8, width: 16, height: 16)
        context.fill(Path(ellipseIn: headRect), with: .color(Color.white))

        // 6. Lead Arm
        var frontArm = Path()
        frontArm.move(to: CGPoint(x: shoulderX, y: shoulderY))
        frontArm.addLine(to: CGPoint(x: shoulderX + 14, y: shoulderY + 12))
        frontArm.addLine(to: CGPoint(x: shoulderX + 24, y: shoulderY + 6))
        context.stroke(
            frontArm,
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        )

        // 7. Lead Leg - REACHING AHEAD, LOCKED KNEE
        let strikeX = comX + 62.0 // Planted far ahead of COM!
        let kneeX = (comX + strikeX) / 2.0
        let kneeY = (pelvisY + groundY) / 2.0

        var leadLeg = Path()
        leadLeg.move(to: CGPoint(x: comX, y: pelvisY))
        leadLeg.addLine(to: CGPoint(x: kneeX, y: kneeY)) // locked straight knee
        leadLeg.addLine(to: CGPoint(x: strikeX, y: groundY - 2))
        context.stroke(
            leadLeg,
            with: .color(Color.red),
            style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        )

        // Dorsiflexed Heel Strike Foot (heel down, toes pulled up in air)
        var foot = Path()
        foot.move(to: CGPoint(x: strikeX, y: groundY))
        foot.addLine(to: CGPoint(x: strikeX + 15, y: groundY - 9))
        context.stroke(
            foot,
            with: .color(Color.red),
            style: StrokeStyle(lineWidth: 4.0, lineCap: .round)
        )

        // Locked Knee joint marker
        let kneeRect = CGRect(x: kneeX - 3.5, y: kneeY - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: kneeRect), with: .color(Color.red))

        // 8. Pelvis / COM Marker
        let comRect = CGRect(x: comX - 5.5, y: pelvisY - 5.5, width: 11, height: 11)
        context.fill(Path(ellipseIn: comRect), with: .color(Color.red))
        context.stroke(
            Path(ellipseIn: comRect),
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 1.8)
        )

        // 9. Ground Offset Distance Bracket (>30cm ahead)
        var bracket = Path()
        let bracketY = groundY + 8.0
        bracket.move(to: CGPoint(x: comX, y: bracketY - 3))
        bracket.addLine(to: CGPoint(x: comX, y: bracketY))
        bracket.addLine(to: CGPoint(x: strikeX, y: bracketY))
        bracket.addLine(to: CGPoint(x: strikeX, y: bracketY - 3))
        context.stroke(
            bracket,
            with: .color(Color.red),
            style: StrokeStyle(lineWidth: 1.2)
        )

        // 10. Braking Force Vector (Reverse arrow at heel)
        var brakeArrow = Path()
        let brakeStartX = strikeX - 4
        let brakeEndX = brakeStartX - 24
        brakeArrow.move(to: CGPoint(x: brakeStartX, y: groundY))
        brakeArrow.addLine(to: CGPoint(x: brakeEndX, y: groundY))
        brakeArrow.move(to: CGPoint(x: brakeEndX + 5, y: groundY - 3.5))
        brakeArrow.addLine(to: CGPoint(x: brakeEndX, y: groundY))
        brakeArrow.addLine(to: CGPoint(x: brakeEndX + 5, y: groundY + 3.5))
        context.stroke(
            brakeArrow,
            with: .color(Color.red),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )

        // 11. Vertical Impact Shock Vector (Upward arrow at heel)
        var impactArrow = Path()
        let impactY = groundY - 4
        let impactTopY = impactY - 22
        impactArrow.move(to: CGPoint(x: strikeX + 2, y: impactY))
        impactArrow.addLine(to: CGPoint(x: strikeX + 2, y: impactTopY))
        impactArrow.move(to: CGPoint(x: strikeX - 2, y: impactTopY + 4))
        impactArrow.addLine(to: CGPoint(x: strikeX + 2, y: impactTopY))
        impactArrow.addLine(to: CGPoint(x: strikeX + 6, y: impactTopY + 4))
        context.stroke(
            impactArrow,
            with: .color(Color.orange),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )
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
