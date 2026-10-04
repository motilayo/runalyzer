import SwiftUI
import WorkoutKit

/// An interstitial UX sheet bridging the static dashboard and an active WorkoutKit Apple Watch session.
/// Presented as a half-sheet modal (.presentationDetents([.medium, .large])) to mentally prepare
/// the runner before WorkoutKit takes over their wrist with haptics and timers.
struct DrillInterstitialReadoutView: View {
    let readout: DrillReadout
    let workoutPlan: WorkoutPlan
    let prescriptionDTO: DrillPrescriptionDTO
    var onCommitToWatch: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingReadinessInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Card
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(readout.drillId.iconColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: readout.drillId.iconName)
                                .foregroundColor(readout.drillId.iconColor)
                                .font(.title3.bold())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(readout.title)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(readout.subtitle)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let target = readout.targetCadence {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption2.bold())
                                Text(target)
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                        } else if let zone = readout.targetZone {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2.bold())
                                Text(zone)
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.bottom, 2)

                    // 0. Readiness Modifier (ACWR) — only when today's prescription was adapted
                    if readout.isReadinessAdjusted {
                        readinessCard
                    }

                    // 1. The Overview
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "flag.fill")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                            Text("The Overview")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                        }

                        Text(readout.overview)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }

                    // 2. The Breakdown with the Horizontal Timeline UI right below it
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.clipboard.fill")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                            Text("The Breakdown")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                        }

                        Text(readout.breakdown)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)

                        // Horizontally scrolling timeline UI right below the "Breakdown" text
                        WorkoutPhaseTimelineView(phases: readout.phases, showHeader: false)
                    }

                    // 3. The Coaching Tip
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            Text("The Coaching Tip")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                                .font(.body)
                            Text(coachingTipFormattedText)
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .lineSpacing(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    commitAndStart()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "applewatch")
                            .font(.headline)
                        Text("Send to Apple Watch")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var coachingTipFormattedText: AttributedString {
        var str = AttributedString("Tip: ")
        str.font = .footnote.bold()
        let tipBody = AttributedString(readout.coachingTip)
        str.append(tipBody)
        return str
    }

    // MARK: - Readiness Card

    private var readinessTint: Color {
        readout.readinessState == .deload ? .teal : .pink
    }

    private var readinessIcon: String {
        readout.readinessState == .deload ? "leaf.fill" : "battery.25percent"
    }

    @ViewBuilder
    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: readinessIcon)
                    .font(.caption.bold())
                    .foregroundColor(readinessTint)
                Text("Readiness Adjusted")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(readout.readinessState.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(readinessTint.opacity(0.15))
                    .foregroundColor(readinessTint)
                    .cornerRadius(6)
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showingReadinessInfo = true }

            VStack(alignment: .leading, spacing: 8) {
                if let target = readout.targetCadence {
                    readinessRow(
                        icon: "target",
                        label: "Target",
                        value: target,
                        detail: targetDetailText
                    )
                }
                if let adapted = readout.adaptedWork, let standard = readout.standardWork, adapted != standard {
                    readinessRow(icon: "repeat", label: "Volume", value: adapted, detail: "Reduced from \(standard)")
                }
                if let adapted = readout.adaptedRecovery, let standard = readout.standardRecovery, adapted != standard {
                    readinessRow(icon: "moon.zzz", label: "Recovery", value: adapted, detail: "Extended from \(standard)")
                }
            }

            if let context = readout.readinessContext {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach Context")
                        .font(.caption2.bold())
                        .foregroundColor(readinessTint)
                    Text("“\(context)”")
                        .font(.footnote)
                        .italic()
                        .foregroundColor(.primary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(readinessTint.opacity(0.08))
                .cornerRadius(10)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(readinessTint.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
        .alert("Readiness Modifier", isPresented: $showingReadinessInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Your drill targets come from your 30-day baseline (chronic load). Runalyst compares your last 7 days (acute load) against your 4-week average. A spike above 1.5×, back-to-back hard days, late-run cadence fade, or heart-rate drift relaxes turnover and trims reps. A 25%+ mileage drop at easy intensity is treated as a deload: intensity is held while reps are halved and recovery extended.")
        }
    }

    private var targetDetailText: String? {
        guard let standard = readout.standardTargetCadence else { return nil }
        if let current = readout.targetCadence, current != standard {
            return "Adjusted from your standard \(standard) target"
        }
        return readout.readinessState == .deload ? "Intensity held to keep your legs sharp" : nil
    }

    private func readinessRow(icon: String, label: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundColor(readinessTint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(label):")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(value)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }
                if let detail {
                    Text("(\(detail))")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func commitAndStart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        onCommitToWatch?(workoutPlan, prescriptionDTO)
    }
}
