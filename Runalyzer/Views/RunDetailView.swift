import SwiftUI
import SwiftData

/// A detailed view for a single `RunRecord`, displaying in-depth metrics and the full AI Coaching Insight.
///
/// This view includes a grid of physiological and biomechanical stats, followed by the AI-generated
/// observation and the specific actionable technique drill prescribed by the Foundation Model.
struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var existingRuns: [RunRecord]

    @AppStorage("useWorkingAverages") private var useWorkingAverages: Bool = true


    // Baseline calculations
    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return existingRuns.filter { $0.date < runRecord.date && $0.date >= thirtyDaysAgo }
    }

    private var baselinePace: Double? {
        let runs = baselineRuns
        guard !runs.isEmpty else { return nil }
        return runs.map(\.avgPace).reduce(0, +) / Double(runs.count)
    }

    private var baselineHR: Double? {
        let runs = baselineRuns.filter { $0.avgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.avgHeartRate).reduce(0, +)) / Double(runs.count)
    }

    private var baselineCadence: Double? {
        let runs = baselineRuns.filter { $0.avgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.avgCadence).reduce(0, +)) / Double(runs.count)
    }

    private var baselineVertOsc: Double? {
        let runs = baselineRuns.filter { $0.verticalOscillation > 0 }
        guard !runs.isEmpty else { return nil }
        return runs.map(\.verticalOscillation).reduce(0, +) / Double(runs.count)
    }

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))

                Text("AI-generated insights are for informational purposes only and do not replace professional medical or coaching advice. Always listen to your body.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.top, 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                VStack {
                    Toggle(useWorkingAverages ? "Working Averages" : "Raw Totals", isOn: $useWorkingAverages)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Top: Responsive 6-Card Grid of Raw Stats
                let columns = verticalSizeClass == .regular
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

                LazyVGrid(columns: columns, spacing: 16) {
                    let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                    let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit)

                    let minutes = Int(runRecord.duration) / 60
                    let seconds = Int(runRecord.duration) % 60
                    StatBox(title: "Total Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min")

                    let displayPace = (useWorkingAverages ? runRecord.workingAvgPace : nil) ?? runRecord.avgPace
                    let displayPaceStr = (useWorkingAverages ? runRecord.workingFormattedPace : nil) ?? runRecord.formattedPace
                    let displayHR = (useWorkingAverages ? runRecord.workingAvgHeartRate : nil) ?? runRecord.avgHeartRate
                    let displayCadence = (useWorkingAverages ? runRecord.workingAvgCadence : nil) ?? runRecord.avgCadence

                    StatBox(title: "Avg Pace", value: displayPaceStr, unit: "", currentValue: displayPace, baselineValue: baselinePace, polarity: .lowerIsBetter)
                    StatBox(title: "Avg HR", value: "\(displayHR)", unit: "BPM", currentValue: Double(displayHR), baselineValue: baselineHR, polarity: .lowerIsBetter)
                    StatBox(title: "Avg Cadence", value: "\(displayCadence)", unit: "SPM", currentValue: Double(displayCadence), baselineValue: baselineCadence, polarity: .higherIsBetter)
                    StatBox(title: "Vert. Osc.", value: String(format: "%.1f", runRecord.verticalOscillation), unit: "cm", currentValue: runRecord.verticalOscillation, baselineValue: baselineVertOsc, polarity: .lowerIsBetter)
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

                        if !insight.headline.isEmpty {
                            Text(insight.headline)
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                        }

                        if !insight.longitudinalObservation.isEmpty {
                            Text(insight.longitudinalObservation)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text("Detected Run Type:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Run Type", selection: $runRecord.runTypeRaw) {
                                Text("Steady").tag(Optional("steady"))
                                Text("Tempo").tag(Optional("tempo"))
                                Text("Progressive").tag(Optional("progressive"))
                                Text("Intervals").tag(Optional("intervals"))
                                Text("Urban Traffic").tag(Optional("urbanTraffic"))
                                Text("Unknown").tag(Optional("unknown"))
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: runRecord.runTypeRaw) { _, _ in
                                runRecord.insight = nil // Clear insight to trigger regeneration
                                if #available(iOS 26.0, *) {
                                    let container = modelContext.container
                                    let runId = runRecord.persistentModelID
                                    Task.detached {
                                        let analyzer = RunAnalyzerActor(modelContainer: container)
                                        await analyzer.generateAnalysis(for: runId)
                                    }
                                }
                            }
                        }

                        aiDisclaimerFooter
                    }
                    .frame(minHeight: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    // Bottom: Drill Card Deck
                    if let drills = insight.drillRecommendations, !drills.isEmpty {
                        DrillDeckView(drills: drills)
                            .padding(.top, 24)
                    } else if let drill = insight.drillRecommendation {
                        // Fallback for legacy single drill migrations
                        DrillDeckView(drills: [drill])
                            .padding(.top, 24)
                    }

                } else {
                    AnimatedLoadingView(
                        text: "Generating Coaching Insight...",
                        isHorizontal: false,
                        imageSize: 60,
                        textFont: .subheadline,
                        textColor: .secondary,
                        iconColor: .purple,
                        spacing: 20
                    )
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 1)
                    .padding(32)
                    .task(id: runRecord.id) {
                        if #available(iOS 26.0, *) {
                            if runRecord.insight == nil && runRecord.isAnalyzing != true {
                                let container = modelContext.container
                                let runId = runRecord.persistentModelID

                                Task.detached {
                                    let analyzer = RunAnalyzerActor(modelContainer: container)
                                    await analyzer.generateAnalysis(for: runId)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(runRecord.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A tappable statistic box displaying a specific metric for a run.
/// Tapping it presents an alert with a detailed definition of the metric.

struct StatBox: View {
    var title: String
    var value: String
    var unit: String
    var currentValue: Double? = nil
    var baselineValue: Double? = nil
    var polarity: MetricPolarity? = nil

    @State private var showingInfo = false

    private var definition: String {
        switch title.lowercased() {
        case "distance":
            return "The total distance covered during your run."
        case "total time":
            return "The total elapsed time of your run."
        case "avg pace":
            return "Your average speed, measured in minutes per distance unit (mile or kilometer)."
        case "avg hr":
            return "Your average heart rate during the run in Beats Per Minute (BPM)."
        case "avg cadence":
            return "Your average step rate, measured in Steps Per Minute (SPM). A higher cadence can reduce impact forces."
        case "vert. osc.":
            return "Vertical Oscillation measures how much your torso bounces up and down with each step. Lower values often indicate better efficiency and less energy wasted fighting gravity."
        default:
            return "A running metric tracked by HealthKit."
        }
    }

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

                if let current = currentValue, let baseline = baselineValue, let polarity = polarity {
                    let diff = current - baseline
                    if abs(diff) > 0.01 {
                        let isPositiveTrend = diff > 0
                        let isGood = (polarity == .higherIsBetter) ? isPositiveTrend : !isPositiveTrend

                        Image(systemName: isPositiveTrend ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(isGood ? .green : .red)
                            .padding(.leading, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture {
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(definition)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit). Double tap for definition.")
    }
}

/// A styled row within a drill recommendation card, combining a system icon with a descriptive text.
struct DrillRow: View {
    var icon: String
    var text: String

    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .top)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DrillDeckView: View {
    var drills: [DrillRecommendation]
    @State private var activeCardIndex: Int = 0
    @State private var offset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    private func updateDragOffset(_ translation: CGSize, isActive: Bool) {
        guard isActive else { return }
        offset = translation
    }

    private func finishDrag(isActive: Bool, totalDrills: Int) {
        guard isActive else { return }
        if offset.width < -100 && activeCardIndex < totalDrills - 1 {
            activeCardIndex += 1
        } else if offset.width > 100 && activeCardIndex > 0 {
            activeCardIndex -= 1
        }
        offset = CGSize.zero
    }

    private func deckCard(_ drill: DrillRecommendation, index: Int, totalDrills: Int) -> some View {
        let relativeIndex = index - activeCardIndex
        let rotationDegree = relativeIndex == 0 ? 0 : (relativeIndex % 2 == 1 ? -3.0 : 3.0)

        return DrillCardView(
            drill: drill,
            drillIndex: index,
            totalDrills: totalDrills,
            activeCardIndex: $activeCardIndex,
            dismiss: dismiss
        )
        .frame(maxWidth: .infinity, minHeight: 1)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(relativeIndex == 0 ? 0 : 0.3))
        }
        .shadow(color: Color.black.opacity(relativeIndex == 0 ? 0.15 : 0.05), radius: relativeIndex == 0 ? 12 : 8, x: 0, y: relativeIndex == 0 ? 8 : 4)
        .rotationEffect(.degrees(relativeIndex == 0 ? (Double(offset.width) / 20.0) : rotationDegree))
        .offset(x: relativeIndex == 0 ? offset.width : 0, y: relativeIndex == 0 ? offset.height : 0)
        .opacity(relativeIndex == 0 ? (2 - Double(abs(offset.width / 150))) : 1.0)
        .zIndex(Double(totalDrills - index))
        .padding(.horizontal)
        .padding(.bottom, 20)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    updateDragOffset(gesture.translation, isActive: relativeIndex == 0)
                }
                .onEnded { _ in
                    finishDrag(isActive: relativeIndex == 0, totalDrills: totalDrills)
                }
        )
    }

    var body: some View {
        let sortedDrills = drills.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }

        ZStack(alignment: .top) {
            ForEach(Array(sortedDrills.enumerated()), id: \.element.id) { index, currentDrill in
                let relativeIndex = index - activeCardIndex

                if relativeIndex >= 0 && relativeIndex < 3 {
                    deckCard(currentDrill, index: index, totalDrills: sortedDrills.count)
                }
            }
        }
        .padding(.bottom, 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offset)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeCardIndex)
    }
}

import WorkoutKit

private struct DrillCardView: View {
    @Bindable var drill: DrillRecommendation
    let drillIndex: Int
    let totalDrills: Int
    @Binding var activeCardIndex: Int
    let dismiss: DismissAction

    @State private var isSchedulingWorkout = false
    @State private var workoutHandoffError: String?
    @State private var workoutHandoffSucceeded = false

    private var deterministicTargetSPM: Int? {
        guard let previousCadence = drill.previousCadence, previousCadence > 0 else { return drill.targetSPM }
        return min(180, max(150, Int((Double(previousCadence) * 1.05).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    ForEach(0..<totalDrills, id: \.self) { barIndex in
                        Capsule()
                            .fill(barIndex == activeCardIndex ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 4)
                    }
                }

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Text("DRILL \(String(format: "%02d", drillIndex + 1))")
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundColor(.secondary)

            if !drill.drillTitle.isEmpty {
                Text(drill.drillTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 12) {
                DrillRow(icon: "target", text: drill.drillPurpose ?? "")
                DrillRow(icon: "repeat", text: drill.drillWork ?? "")
                DrillRow(icon: "brain.head.profile", text: drill.drillCues ?? "")
                DrillRow(icon: "bolt", text: drill.drillEffort ?? "")
                DrillRow(icon: "pause.circle", text: drill.drillRecovery ?? "")
            }

            if let target = deterministicTargetSPM, let prev = drill.previousCadence, target > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cadence Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Current: \(prev) SPM → Target: \(target) SPM")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 16)

            Button {
                if drill.isCompleted {
                    return
                }

                isSchedulingWorkout = true
                workoutHandoffError = nil
                workoutHandoffSucceeded = false
                Task {
                    guard WorkoutScheduler.isSupported else {
                        workoutHandoffError = "Workout scheduling is unavailable on this device."
                        isSchedulingWorkout = false
                        return
                    }

                    guard let targetSPM = deterministicTargetSPM,
                          let customWorkout = LiveCoachEngine().translate(prescription: drill.drillWork ?? "", targetSPM: targetSPM) else {
                        workoutHandoffError = "This drill does not contain a schedulable workout prescription."
                        isSchedulingWorkout = false
                        return
                    }

                    let plan = WorkoutPlan(.custom(customWorkout))
                    let authorizationState = await WorkoutScheduler.shared.requestAuthorization()
                    guard authorizationState == .authorized else {
                        workoutHandoffError = "WorkoutKit authorization is required to send this drill to Apple Watch."
                        isSchedulingWorkout = false
                        return
                    }

                    let scheduleDate = Calendar.current.dateComponents(
                        [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                        from: Date()
                    )
                    await WorkoutScheduler.shared.schedule(plan, at: scheduleDate)
                    drill.isCompleted = true
                    isSchedulingWorkout = false
                    workoutHandoffSucceeded = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSchedulingWorkout {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(workoutHandoffSucceeded ? "Scheduled on Apple Watch" : (isSchedulingWorkout ? "Sending to Apple Watch..." : (drill.isCompleted ? "Completed" : "Start Drill")))
                }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(workoutHandoffSucceeded || drill.isCompleted ? Color.green : Color.accentColor)
                    .clipShape(Capsule())
            }
            .disabled(drill.isCompleted || isSchedulingWorkout)
            .alert("Workout Handoff", isPresented: Binding(
                get: { workoutHandoffError != nil },
                set: { if !$0 { workoutHandoffError = nil } }
            )) {
                Button("OK", role: .cancel) { workoutHandoffError = nil }
            } message: {
                Text(workoutHandoffError ?? "")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 1)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
    }
}
