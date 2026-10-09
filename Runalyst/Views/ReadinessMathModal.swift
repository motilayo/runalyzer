import SwiftData
import SwiftUI

/// Modal sheet explicitly exposing the mathematical formulas and ACWR calculation behind adaptive targets.
struct ReadinessMathModal: View {
    @Environment(\.dismiss) private var dismiss

    let acuteLoad: Double
    let chronicWeeklyLoad: Double
    let acwr: Double?
    let targetAdjustmentNote: String

    init(
        acuteLoad: Double = 0,
        chronicWeeklyLoad: Double = 0,
        acwr: Double? = nil,
        targetAdjustmentNote: String = ""
    ) {
        if let profile = MacroProfile.load() {
            self.acuteLoad = profile.acuteLoad
            self.chronicWeeklyLoad = profile.chronicWeeklyLoad
            self.acwr = profile.acwr
            self.targetAdjustmentNote = targetAdjustmentNote.isEmpty
                ? "Adaptive Target Prescribed via Longitudinal Readiness"
                : targetAdjustmentNote
        } else {
            self.acuteLoad = acuteLoad
            self.chronicWeeklyLoad = chronicWeeklyLoad
            self.acwr = acwr
            self.targetAdjustmentNote = targetAdjustmentNote
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square")
                                .font(.title3.weight(.bold))
                                .foregroundColor(.teal)
                            Text("Training Load & Readiness")
                                .font(.headline)
                        }

                        Text("We compare your running effort this week against your past month to see if your body is ready to push or needs rest.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)

                    // Current Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current Training Balance")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if let acwr = acwr {
                                Text(String(format: "%.2f", acwr))
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundColor(acwrColor(acwr))

                                Text(acwrStatusText(acwr))
                                    .font(.subheadline.bold())
                                    .foregroundColor(acwrColor(acwr))
                            } else {
                                Text("Building Base")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.secondary)
                                Text("Requires at least 3 weeks of runs")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !targetAdjustmentNote.isEmpty {
                            Text(targetAdjustmentNote)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)

                    // Mathematical Formula Breakdown
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How It Works")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        formulaRow(
                            title: "Workout Stress",
                            formula: "Run Time × Heart Rate Effort",
                            description: "Harder, faster running adds more fatigue than easy jogging."
                        )

                        Divider()

                        formulaRow(
                            title: "This Week's Fatigue (7 Days)",
                            formula: "Total stress from runs over the last 7 days",
                            description: "Measures how tired your body is from recent workouts."
                        )

                        Divider()

                        formulaRow(
                            title: "Your Baseline Fitness (4 Weeks)",
                            formula: "Average weekly stress over the last 28 days",
                            description: "The regular training volume and effort your body is used to."
                        )

                        Divider()

                        formulaRow(
                            title: "Training Balance Ratio",
                            formula: "This Week's Fatigue ÷ Baseline Fitness",
                            description: "Shows whether you are in your training sweet spot or overloading."
                        )
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)

                    // Risk Bands Legend
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Readiness Zones")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        bandLegendRow(color: .orange, range: "< 0.80", label: "Below Normal (Good time to build gradually)")
                        bandLegendRow(color: .green, range: "0.80 – 1.30", label: "Sweet Spot (Safely building fitness)")
                        bandLegendRow(color: .yellow, range: "1.30 – 1.50", label: "Elevated Fatigue (Keep an eye on recovery)")
                        bandLegendRow(color: .red, range: "> 1.50", label: "High Fatigue (Time for an easy day or rest)")
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Training Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func formulaRow(title: String, formula: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)

            Text(formula)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.teal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func bandLegendRow(color: Color, range: String, label: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(range)
                .font(.caption.weight(.bold))
                .frame(width: 78, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func acwrColor(_ ratio: Double) -> Color {
        if ratio > 1.50 { return .red }
        if ratio > 1.30 { return .yellow }
        if ratio >= 0.80 { return .green }
        return .orange
    }

    private func acwrStatusText(_ ratio: Double) -> String {
        if ratio > 1.50 { return "High Fatigue" }
        if ratio > 1.30 { return "Elevated Fatigue" }
        if ratio >= 0.80 { return "Sweet Spot" }
        return "Below Normal"
    }
}

// MARK: - Training Load Status Bar

/// Shared color-coded status bar displaying the athlete's ACWR ratio and status, with tap-to-inspect readiness math.
struct TrainingLoadStatusBar: View {
    let acwr: Double?
    let acuteLoad: Double
    let chronicWeeklyLoad: Double
    @State private var showingReadinessMath = false

    init(acwr: Double?, acuteLoad: Double = 0, chronicWeeklyLoad: Double = 0) {
        self.acwr = acwr
        self.acuteLoad = acuteLoad
        self.chronicWeeklyLoad = chronicWeeklyLoad
    }

    init(runRecords: [RunRecord]) {
        let profile = MacroProfile.load()
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        self.acwr = profile?.acwr ?? readiness.acwr
        self.acuteLoad = profile?.acuteLoad ?? readiness.acuteLoad
        self.chronicWeeklyLoad = profile?.chronicWeeklyLoad ?? readiness.chronicWeeklyLoad
    }

    var body: some View {
        let status = Self.status(for: acwr)
        Button {
            showingReadinessMath = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)

                Text("Training Load:")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Text(status.displayText)
                    .font(.caption.bold())
                    .foregroundColor(status.color)

                Spacer()

                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(status.color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(status.color.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingReadinessMath) {
            ReadinessMathModal(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr
            )
        }
    }

    static func status(for ratio: Double?) -> (displayText: String, color: Color) {
        guard let ratio = ratio else {
            return ("Building Base", .blue)
        }
        if ratio > 1.50 { return ("Spike Risk (\(String(format: "%.2f", ratio)))", .red) }
        if ratio > 1.30 { return ("Elevated (\(String(format: "%.2f", ratio)))", .orange) }
        if ratio >= 0.80 { return ("Optimal (\(String(format: "%.2f", ratio)))", .green) }
        return ("Building Base (\(String(format: "%.2f", ratio)))", .blue)
    }
}
