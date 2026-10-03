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

                    // Primary Action Button: Bridge to WorkoutKit
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
                        .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var coachingTipFormattedText: AttributedString {
        var str = AttributedString("Tip: ")
        str.font = .footnote.bold()
        let tipBody = AttributedString(readout.coachingTip)
        str.append(tipBody)
        return str
    }

    private func commitAndStart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        onCommitToWatch?(workoutPlan, prescriptionDTO)
    }
}
