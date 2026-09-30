import SwiftUI

/// Mode selector for the biomechanics vector diagram
enum BiomechanicsDiagramMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case goodStride = "Good Stride"
    case overstride = "Overstriding"

    var id: String { rawValue }
}

/// Key anatomical annotation points for biomechanical callouts
enum BiomechanicalFocusArea: String, CaseIterable, Identifiable {
    case com = "Center of Mass"
    case knee = "Knee Flexion"
    case shin = "Tibial Angle"
    case footstrike = "Foot Strike"
    case forces = "Impact & Braking Forces"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .com: return "scope"
        case .knee: return "figure.walk"
        case .shin: return "lines.measurement.horizontal"
        case .footstrike: return "shoeprints.fill"
        case .forces: return "bolt.shield.fill"
        }
    }
}

/// High-fidelity vector illustration of running kinematics accurately replicating
/// the sports-science silhouette and biomechanical force vectors.
struct OverstrideVectorCanvas: View {
    let isOverstride: Bool
    var activeFocus: BiomechanicalFocusArea?
    var showLabels: Bool = true

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Normalized ground line
            let groundY = h * 0.88

            // Center of Mass Anchor: Pelvis position
            // Shifted slightly left of center to leave ample space for forward leg/annotations
            let comX = isOverstride ? w * 0.38 : w * 0.36
            let comY = h * 0.44

            // 1. Ground Plane
            var ground = Path()
            ground.move(to: CGPoint(x: w * 0.04, y: groundY))
            ground.addLine(to: CGPoint(x: w * 0.96, y: groundY))
            context.stroke(
                ground,
                with: .color(Color.secondary.opacity(0.35)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // 2. Center of Mass Plumb Line (dashed vertical from COM to ground)
            var plumbLine = Path()
            plumbLine.move(to: CGPoint(x: comX, y: comY))
            plumbLine.addLine(to: CGPoint(x: comX, y: groundY))
            context.stroke(
                plumbLine,
                with: .color(Color.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )

            // 3. Body Lean Axis Line
            var leanLine = Path()
            if isOverstride {
                // Low body lean: straight vertical through torso
                leanLine.move(to: CGPoint(x: comX, y: h * 0.12))
                leanLine.addLine(to: CGPoint(x: comX, y: comY + 15))
            } else {
                // Good body lean: forward inclined line from ankle/pelvis through shoulder
                leanLine.move(to: CGPoint(x: comX + 24, y: h * 0.10))
                leanLine.addLine(to: CGPoint(x: comX - 6, y: groundY))
            }
            context.stroke(
                leanLine,
                with: .color(isOverstride ? Color.white.opacity(0.6) : Color.green.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )

            // -------------------------------------------------------------
            // RUNNER SILHOUETTE
            // -------------------------------------------------------------
            let runnerColor = Color.primary.opacity(0.92)
            let rearLimbColor = Color.primary.opacity(0.55)

            // A. REAR LEG (drawn behind body)
            var rearLeg = Path()
            if isOverstride {
                // Reduced hip extension; leg hangs lower
                let rearKnee = CGPoint(x: comX - (w * 0.14), y: comY + (h * 0.18))
                let rearAnkle = CGPoint(x: comX - (w * 0.24), y: comY + (h * 0.28))
                let rearToe = CGPoint(x: comX - (w * 0.30), y: comY + (h * 0.26))

                rearLeg.move(to: CGPoint(x: comX - 4, y: comY + 6))
                rearLeg.addQuadCurve(to: rearKnee, control: CGPoint(x: comX - (w * 0.08), y: comY + (h * 0.08)))
                rearLeg.addQuadCurve(to: rearAnkle, control: CGPoint(x: comX - (w * 0.18), y: comY + (h * 0.24)))
                rearLeg.addLine(to: rearToe)
                rearLeg.addLine(to: CGPoint(x: rearToe.x + 8, y: rearToe.y + 4))
                rearLeg.addLine(to: CGPoint(x: rearAnkle.x + 6, y: rearAnkle.y + 4))
                rearLeg.closeSubpath()
            } else {
                // Powerful hip extension behind the runner
                let rearKnee = CGPoint(x: comX - (w * 0.18), y: comY + (h * 0.12))
                let rearAnkle = CGPoint(x: comX - (w * 0.32), y: comY + (h * 0.24))
                let rearToe = CGPoint(x: comX - (w * 0.40), y: comY + (h * 0.20))

                rearLeg.move(to: CGPoint(x: comX - 6, y: comY + 4))
                rearLeg.addQuadCurve(to: rearKnee, control: CGPoint(x: comX - (w * 0.10), y: comY + (h * 0.04)))
                rearLeg.addQuadCurve(to: rearAnkle, control: CGPoint(x: comX - (w * 0.24), y: comY + (h * 0.18)))
                rearLeg.addLine(to: rearToe)
                rearLeg.addLine(to: CGPoint(x: rearToe.x + 8, y: rearToe.y + 4))
                rearLeg.addLine(to: CGPoint(x: rearAnkle.x + 8, y: rearAnkle.y + 2))
                rearLeg.closeSubpath()
            }
            context.fill(rearLeg, with: .color(rearLimbColor))

            // B. TORSO & HEAD
            var torso = Path()
            let neckPoint: CGPoint
            let chestPoint: CGPoint
            let headCenter: CGPoint
            let shoulderPoint: CGPoint

            if isOverstride {
                neckPoint = CGPoint(x: comX, y: h * 0.22)
                chestPoint = CGPoint(x: comX + 12, y: h * 0.28)
                shoulderPoint = CGPoint(x: comX + 2, y: h * 0.26)
                headCenter = CGPoint(x: comX + 2, y: h * 0.14)

                torso.move(to: CGPoint(x: comX - 10, y: comY + 8))
                torso.addLine(to: CGPoint(x: comX - 8, y: h * 0.30)) // back
                torso.addLine(to: neckPoint)
                torso.addLine(to: chestPoint) // chest
                torso.addLine(to: CGPoint(x: comX + 8, y: comY + 8)) // waist/pelvis
                torso.closeSubpath()
            } else {
                neckPoint = CGPoint(x: comX + 14, y: h * 0.22)
                chestPoint = CGPoint(x: comX + 26, y: h * 0.28)
                shoulderPoint = CGPoint(x: comX + 16, y: h * 0.26)
                headCenter = CGPoint(x: comX + 16, y: h * 0.14)

                torso.move(to: CGPoint(x: comX - 10, y: comY + 8))
                torso.addLine(to: CGPoint(x: comX + 4, y: h * 0.30)) // back lean
                torso.addLine(to: neckPoint)
                torso.addLine(to: chestPoint) // chest lean
                torso.addLine(to: CGPoint(x: comX + 14, y: comY + 8))
                torso.closeSubpath()
            }
            context.fill(torso, with: .color(runnerColor))

            // Head silhouette
            var head = Path()
            head.addEllipse(in: CGRect(x: headCenter.x - 12, y: headCenter.y - 12, width: 24, height: 24))
            context.fill(head, with: .color(runnerColor))

            // Ponytail
            var hair = Path()
            let hairStart = CGPoint(x: headCenter.x - 10, y: headCenter.y + 2)
            let hairEnd = CGPoint(x: headCenter.x - 26, y: headCenter.y + (isOverstride ? 16 : 8))
            hair.move(to: hairStart)
            hair.addQuadCurve(to: hairEnd, control: CGPoint(x: headCenter.x - 20, y: headCenter.y - 2))
            hair.addQuadCurve(to: CGPoint(x: hairStart.x, y: hairStart.y + 6), control: CGPoint(x: headCenter.x - 18, y: headCenter.y + 10))
            hair.closeSubpath()
            context.fill(hair, with: .color(runnerColor))

            // C. ARMS
            var leadArm = Path()
            var rearArm = Path()
            if isOverstride {
                let leadElbow = CGPoint(x: shoulderPoint.x + 16, y: shoulderPoint.y + 18)
                let leadHand = CGPoint(x: shoulderPoint.x + 28, y: shoulderPoint.y + 12)
                leadArm.move(to: shoulderPoint)
                leadArm.addLine(to: leadElbow)
                leadArm.addLine(to: leadHand)

                let rearElbow = CGPoint(x: shoulderPoint.x - 14, y: shoulderPoint.y + 14)
                let rearHand = CGPoint(x: shoulderPoint.x - 20, y: shoulderPoint.y + 24)
                rearArm.move(to: shoulderPoint)
                rearArm.addLine(to: rearElbow)
                rearArm.addLine(to: rearHand)
            } else {
                let leadElbow = CGPoint(x: shoulderPoint.x + 22, y: shoulderPoint.y + 16)
                let leadHand = CGPoint(x: shoulderPoint.x + 32, y: shoulderPoint.y + 8)
                leadArm.move(to: shoulderPoint)
                leadArm.addLine(to: leadElbow)
                leadArm.addLine(to: leadHand)

                let rearElbow = CGPoint(x: shoulderPoint.x - 18, y: shoulderPoint.y + 12)
                let rearHand = CGPoint(x: shoulderPoint.x - 26, y: shoulderPoint.y + 22)
                rearArm.move(to: shoulderPoint)
                rearArm.addLine(to: rearElbow)
                rearArm.addLine(to: rearHand)
            }
            context.stroke(rearArm, with: .color(rearLimbColor), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
            context.stroke(leadArm, with: .color(runnerColor), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

            // D. LEAD STANCE LEG
            let kneePoint: CGPoint
            let anklePoint: CGPoint
            let heelPoint: CGPoint
            let toePoint: CGPoint

            if isOverstride {
                // Straight locked knee casting forward, dorsiflexed heel landing >30cm ahead
                kneePoint = CGPoint(x: comX + (w * 0.22), y: comY + (h * 0.22))
                anklePoint = CGPoint(x: comX + (w * 0.40), y: groundY - 14)
                heelPoint = CGPoint(x: comX + (w * 0.38), y: groundY)
                toePoint = CGPoint(x: comX + (w * 0.48), y: groundY - 16) // tilted upward
            } else {
                // Bent knee (~35 deg), small tibial angle, midfoot landing close under COM
                kneePoint = CGPoint(x: comX + (w * 0.14), y: comY + (h * 0.20))
                anklePoint = CGPoint(x: comX + (w * 0.10), y: groundY - 10)
                heelPoint = CGPoint(x: comX + (w * 0.05), y: groundY)
                toePoint = CGPoint(x: comX + (w * 0.18), y: groundY) // flat on ground
            }

            var stanceThigh = Path()
            stanceThigh.move(to: CGPoint(x: comX - 4, y: comY + 6))
            stanceThigh.addLine(to: CGPoint(x: kneePoint.x - 4, y: kneePoint.y))
            stanceThigh.addLine(to: CGPoint(x: kneePoint.x + 8, y: kneePoint.y))
            stanceThigh.addLine(to: CGPoint(x: comX + 12, y: comY + 6))
            stanceThigh.closeSubpath()
            context.fill(stanceThigh, with: .color(runnerColor))

            var stanceShin = Path()
            stanceShin.move(to: CGPoint(x: kneePoint.x - 5, y: kneePoint.y + 2))
            stanceShin.addLine(to: CGPoint(x: anklePoint.x - 4, y: anklePoint.y))
            stanceShin.addLine(to: CGPoint(x: anklePoint.x + 6, y: anklePoint.y))
            stanceShin.addLine(to: CGPoint(x: kneePoint.x + 7, y: kneePoint.y + 2))
            stanceShin.closeSubpath()
            context.fill(stanceShin, with: .color(runnerColor))

            // Running Shoe Silhouette
            var shoe = Path()
            if isOverstride {
                // Dorsiflexed heel plant
                shoe.move(to: heelPoint)
                shoe.addLine(to: CGPoint(x: heelPoint.x + 4, y: groundY))
                shoe.addLine(to: toePoint)
                shoe.addLine(to: CGPoint(x: toePoint.x - 4, y: toePoint.y - 6))
                shoe.addLine(to: anklePoint)
                shoe.addLine(to: CGPoint(x: heelPoint.x - 2, y: groundY - 8))
                shoe.closeSubpath()
            } else {
                // Flat midfoot plant
                shoe.move(to: heelPoint)
                shoe.addLine(to: toePoint)
                shoe.addLine(to: CGPoint(x: toePoint.x - 2, y: toePoint.y - 8))
                shoe.addLine(to: anklePoint)
                shoe.addLine(to: CGPoint(x: heelPoint.x - 2, y: heelPoint.y - 6))
                shoe.closeSubpath()
            }
            context.fill(shoe, with: .color(runnerColor))

            // -------------------------------------------------------------
            // SPORTS SCIENCE ANNOTATION OVERLAYS (EXACT LAB GRAPHICS)
            // -------------------------------------------------------------

            // 1. Center of Mass Dot (Glowing Green Pelvis Anchor)
            var comRing = Path()
            comRing.addEllipse(in: CGRect(x: comX - 7, y: comY - 7, width: 14, height: 14))
            context.fill(comRing, with: .color(Color.green.opacity(0.35)))

            var comDot = Path()
            comDot.addEllipse(in: CGRect(x: comX - 4.5, y: comY - 4.5, width: 9, height: 9))
            context.fill(comDot, with: .color(Color.green))
            context.stroke(comDot, with: .color(Color.white), style: StrokeStyle(lineWidth: 1.5))

            // 2. Knee Flexion Disc Highlight (Translucent Green)
            var kneeDisc = Path()
            kneeDisc.addEllipse(in: CGRect(x: kneePoint.x - 14, y: kneePoint.y - 14, width: 28, height: 28))
            context.fill(kneeDisc, with: .color(Color.green.opacity(0.40)))

            // 3. Foot Strike Dimension Bracket & Distance
            if isOverstride {
                // Overstriding: Horizontal bracket from COM plumb line to Heel Strike (>30cm)
                let strikeY = groundY + 10
                var bracket = Path()
                bracket.move(to: CGPoint(x: comX, y: groundY + 2))
                bracket.addLine(to: CGPoint(x: comX, y: strikeY))
                bracket.addLine(to: CGPoint(x: heelPoint.x, y: strikeY))
                bracket.addLine(to: CGPoint(x: heelPoint.x, y: groundY + 2))
                context.stroke(bracket, with: .color(Color.red), style: StrokeStyle(lineWidth: 1.5))

                // Foot strike drop line
                var dropLine = Path()
                dropLine.move(to: CGPoint(x: heelPoint.x, y: h * 0.46))
                dropLine.addLine(to: CGPoint(x: heelPoint.x, y: groundY))
                context.stroke(dropLine, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Dimension line between plumb and drop line
                var dimLine = Path()
                dimLine.move(to: CGPoint(x: comX, y: h * 0.46))
                dimLine.addLine(to: CGPoint(x: heelPoint.x, y: h * 0.46))
                context.stroke(dimLine, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                // High Braking Force Arrow (red, pointing backward / left)
                var brakeArrow = Path()
                let arrowY = groundY - 2
                brakeArrow.move(to: CGPoint(x: heelPoint.x + 36, y: arrowY))
                brakeArrow.addLine(to: CGPoint(x: heelPoint.x + 8, y: arrowY))
                brakeArrow.addLine(to: CGPoint(x: heelPoint.x + 16, y: arrowY - 6))
                brakeArrow.move(to: CGPoint(x: heelPoint.x + 8, y: arrowY))
                brakeArrow.addLine(to: CGPoint(x: heelPoint.x + 16, y: arrowY + 6))
                context.stroke(brakeArrow, with: .color(Color.red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // High Vertical Impact on Strike Arrow (orange, pointing upward)
                var impactArrow = Path()
                let arrowX = heelPoint.x + 14
                impactArrow.move(to: CGPoint(x: arrowX, y: groundY + 16))
                impactArrow.addLine(to: CGPoint(x: arrowX, y: groundY - 14))
                impactArrow.addLine(to: CGPoint(x: arrowX - 5, y: groundY - 7))
                impactArrow.move(to: CGPoint(x: arrowX, y: groundY - 14))
                impactArrow.addLine(to: CGPoint(x: arrowX + 5, y: groundY - 7))
                context.stroke(impactArrow, with: .color(Color.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            } else {
                // Good Stride: Foot strike drop line near COM
                let strikeY = groundY + 10
                var bracket = Path()
                bracket.move(to: CGPoint(x: comX, y: groundY + 2))
                bracket.addLine(to: CGPoint(x: comX, y: strikeY))
                bracket.addLine(to: CGPoint(x: heelPoint.x + 14, y: strikeY))
                bracket.addLine(to: CGPoint(x: heelPoint.x + 14, y: groundY + 2))
                context.stroke(bracket, with: .color(Color.teal), style: StrokeStyle(lineWidth: 1.5))

                // Dimension guide
                var dropLine = Path()
                dropLine.move(to: CGPoint(x: heelPoint.x + 14, y: h * 0.46))
                dropLine.addLine(to: CGPoint(x: heelPoint.x + 14, y: groundY))
                context.stroke(dropLine, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                var dimLine = Path()
                dimLine.move(to: CGPoint(x: comX, y: h * 0.46))
                dimLine.addLine(to: CGPoint(x: heelPoint.x + 14, y: h * 0.46))
                context.stroke(dimLine, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                // Forward Propulsive Force Arrow (teal, pointing forward / right)
                var propulsiveArrow = Path()
                let arrowY = groundY - 2
                propulsiveArrow.move(to: CGPoint(x: toePoint.x - 28, y: arrowY))
                propulsiveArrow.addLine(to: CGPoint(x: toePoint.x + 18, y: arrowY))
                propulsiveArrow.addLine(to: CGPoint(x: toePoint.x + 10, y: arrowY - 5))
                propulsiveArrow.move(to: CGPoint(x: toePoint.x + 18, y: arrowY))
                propulsiveArrow.addLine(to: CGPoint(x: toePoint.x + 10, y: arrowY + 5))
                context.stroke(propulsiveArrow, with: .color(Color.teal), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// A clean annotated illustration card representing either Good Stride or Overstriding
struct BiomechanicalCardView: View {
    let isOverstride: Bool
    @State private var selectedArea: BiomechanicalFocusArea?

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

            // Vector Graphic Frame
            ZStack {
                // Background Tinted Canvas Box
                RoundedRectangle(cornerRadius: 16)
                    .fill(isOverstride ? Color.red.opacity(0.06) : Color.teal.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke((isOverstride ? Color.red : Color.teal).opacity(0.2), lineWidth: 1)
                    )

                OverstrideVectorCanvas(isOverstride: isOverstride, activeFocus: selectedArea)
                    .frame(height: 240)
                    .padding(.vertical, 6)

                // Sports-science annotations accurately positioned around the perimeter
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height

                    if isOverstride {
                        // Top label: Low Body Lean
                        LeaderAnnotationText(text: "Low Body Lean", color: .primary, alignment: .center)
                            .position(x: w * 0.38, y: h * 0.08)

                        // Left label: Centre of Mass
                        LeaderAnnotationText(text: "Centre of Mass\n(COM)", color: .green, alignment: .trailing)
                            .position(x: w * 0.16, y: h * 0.44)

                        // Right label: Foot strike too far from COM (>30cm)
                        LeaderAnnotationText(text: "Foot strike too far\nfrom COM (>30cm)", color: .red, alignment: .leading)
                            .position(x: w * 0.76, y: h * 0.40)

                        // Knee label: Reduced Knee Flexion
                        LeaderAnnotationText(text: "Reduced Knee\nFlexion", color: .primary, alignment: .trailing)
                            .position(x: w * 0.46, y: h * 0.72)

                        // Shin label: Large Tibial Inclination Angle
                        LeaderAnnotationText(text: "Large Tibial Angle", color: .primary, alignment: .leading)
                            .position(x: w * 0.78, y: h * 0.68)

                        // Impact Forces: High Braking Force & High Vertical Impact
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("High Braking Force")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                            Text("High Vertical Impact")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .position(x: w * 0.78, y: h * 0.88)

                    } else {
                        // Top label: Good Body Lean
                        LeaderAnnotationText(text: "Good Body Lean", color: .green, alignment: .center)
                            .position(x: w * 0.48, y: h * 0.08)

                        // Left label: Centre of Mass
                        LeaderAnnotationText(text: "Centre of Mass\n(COM)", color: .green, alignment: .trailing)
                            .position(x: w * 0.15, y: h * 0.44)

                        // Right label: Foot strike under COM
                        LeaderAnnotationText(text: "Foot strike close\nto COM", color: .teal, alignment: .leading)
                            .position(x: w * 0.72, y: h * 0.40)

                        // Knee label: Good Knee Flexion
                        LeaderAnnotationText(text: "Good Knee\nFlexion", color: .green, alignment: .trailing)
                            .position(x: w * 0.38, y: h * 0.72)

                        // Shin label: Small Tibial Inclination Angle
                        LeaderAnnotationText(text: "Small Tibial Angle", color: .teal, alignment: .leading)
                            .position(x: w * 0.72, y: h * 0.68)

                        // Propulsion: Forward Propulsive Force
                        Text("Forward Propulsion")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.teal)
                            .position(x: w * 0.70, y: h * 0.88)
                    }
                }
            }

            // Kinematic Point Checklist
            VStack(alignment: .leading, spacing: 6) {
                if isOverstride {
                    KinematicPointRow(
                        title: "Foot Strike Ahead of COM",
                        subtitle: "Foot plants with large forward tibial angle, producing counter-productive braking forces.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "Locked Knee Shock Transfer",
                        subtitle: "Straightened knee cannot act as a spring, sending vertical impact up into joints.",
                        isPositive: false
                    )
                    KinematicPointRow(
                        title: "Wasted Vertical Bounce",
                        subtitle: "Braking force redirects horizontal speed into high vertical oscillation.",
                        isPositive: false
                    )
                } else {
                    KinematicPointRow(
                        title: "Foot Strike Under Pelvis",
                        subtitle: "Foot descends underneath center of mass, directing ground forces directly forward.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Spring Knee Flexion",
                        subtitle: "Flexed knee absorbs landing load naturally through the quadriceps and calf elastic recoil.",
                        isPositive: true
                    )
                    KinematicPointRow(
                        title: "Rear Glute Push-Off",
                        subtitle: "Stride length is unlocked behind the runner, maintaining forward momentum.",
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

/// Small clean annotation text for sports science diagram
private struct LeaderAnnotationText: View {
    let text: String
    let color: Color
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .multilineTextAlignment(alignment)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(Color(UIColor.systemBackground).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
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
        }
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

            VStack(spacing: 10) {
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

            VStack(spacing: 8) {
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
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(cue)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(focus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
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
                        VStack(spacing: 16) {
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
