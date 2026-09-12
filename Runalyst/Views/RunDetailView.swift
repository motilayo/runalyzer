import SwiftUI
import UIKit
import SwiftData
import WorkoutKit

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var existingRuns: [RunRecord]

    @State private var showRawMetrics: Bool = false
    @State private var isForceAnalyzing: Bool = false
    @State private var showingToggleInfo = false
    @State private var showingClassificationExplainer = false
    @State private var isGeneratingInsight = false

    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return existingRuns.filter { $0.date < runRecord.date && $0.date >= thirtyDaysAgo }
    }

    private var baselinePace: Double? {
        let runs = baselineRuns.filter { $0.workingAvgPace > 0 }
        guard !runs.isEmpty else { return nil }
        return runs.map(\.workingAvgPace).reduce(0, +) / Double(runs.count)
    }

    private var baselineHR: Double? {
        let runs = baselineRuns.filter { $0.workingAvgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.workingAvgHeartRate).reduce(0, +)) / Double(runs.count)
    }

    private var baselineCadence: Double? {
        let runs = baselineRuns.filter { $0.workingAvgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        return Double(runs.map(\.workingAvgCadence).reduce(0, +)) / Double(runs.count)
    }

    private var baselineOscillation: Double? {
        let runs = baselineRuns.compactMap { $0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation }.filter { $0 > 0 }
        guard !runs.isEmpty else { return nil }
        return runs.reduce(0, +) / Double(runs.count)
    }

    private var formattedRunDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy 'at' hh:mm a"
        return formatter.string(from: runRecord.date)
    }

    private let classificationOptions = [
        "Steady Effort", "Easy Run", "Tempo Run", "Intervals", "Pyramids",
        "Progression Run", "Recovery Run", "Cadence Run", "Hill Repeats",
        "Long Run", "Fartlek", "Urban Traffic"
    ]

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        AIDisclaimerFooter()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Formatted run date header
                HStack {
                    Text(formattedRunDate)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    if let isIndoor = runRecord.isIndoor {
                        Text(isIndoor ? "Indoor Run" : "Outdoor Run")
                            .font(.caption2.bold())
                            .foregroundColor(isIndoor ? .purple : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isIndoor ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                    .padding(.top, 4)

                // MARK: Run Classification
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 5) {
                            Text("Classification:")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingClassificationExplainer = true
                        }

                        Spacer()

                        Picker("Classification", selection: $runRecord.detectedTypeRaw) {
                            ForEach(classificationOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color(red: 0.05, green: 0.45, blue: 0.5))
                        .onChange(of: runRecord.detectedTypeRaw) { oldValue, newValue in
                            updateClassification(to: newValue, from: oldValue)
                        }
                    }

                    HStack(spacing: 4) {
                        Text("CoreML & Biometrics")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Button(action: { showingClassificationExplainer = true }) {
                            Text("How this is calculated")
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.05, green: 0.45, blue: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showingClassificationExplainer) {
                    RunClassificationExplainerSheet()
                }

                // MARK: AI Run Analysis
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("AI Run Analysis")
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                    }

                    if let insight = runRecord.insight {
                        if !insight.longitudinalObservation.isEmpty {
                            Text(insight.longitudinalObservation)
                                .font(.body)
                                .foregroundColor(.primary)
                        } else if !insight.headline.isEmpty {
                            Text(insight.headline)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    } else if isGeneratingInsight {
                        AnimatedLoadingView(
                            text: "Generating AI insight...",
                            isHorizontal: true,
                            imageSize: 14,
                            textFont: .body,
                            spacing: 8
                        )
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    } else {
                        Text("AI insight not available for this run.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    aiDisclaimerFooter
                }
                .frame(minHeight: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal)
                .task {
                    if runRecord.insight == nil {
                        isGeneratingInsight = true
                        let runId = runRecord.persistentModelID
                        let container = modelContext.container
                        if #available(iOS 26.0, *) {
                            Task.detached {
                                let analyzer = RunAnalyzerActor(modelContainer: container)
                                await analyzer.generateAnalysis(for: runId)
                                await MainActor.run {
                                    isGeneratingInsight = false
                                }
                            }
                        } else {
                            isGeneratingInsight = false
                        }
                    }
                }

                // MARK: Data Toggle
                HStack(spacing: 8) {
                    Picker("Metrics Type", selection: $showRawMetrics) {
                        Text("Working Stats").tag(false)
                        Text("Workout Stats").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Button(action: { showingToggleInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showingToggleInfo) {
                    let explainer = MetricDetailExplainer.explainer(for: showRawMetrics ? "Workout Stats" : "Working Stats", isWorkoutStats: showRawMetrics)
                    MetricExplainerSheet(
                        explainer: explainer,
                        mode: showRawMetrics ? "Workout Stats" : "Working Stats"
                    )
                }

                // MARK: Metrics Grid
                let columns = verticalSizeClass == .regular
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

                LazyVGrid(columns: columns, spacing: 16) {
                    let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                    let activeDistanceMeters = showRawMetrics ? runRecord.totalDistanceMeters : runRecord.effectiveWorkingDistanceMeters
                    let distanceConverted = useMetricSystem ? (activeDistanceMeters / 1000.0) : (activeDistanceMeters / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit, isWorkoutStats: showRawMetrics)

                    let activeDuration = showRawMetrics ? runRecord.duration : runRecord.effectiveWorkingDurationSeconds
                    let minutes = Int(activeDuration) / 60
                    let seconds = Int(activeDuration) % 60
                    StatBox(title: showRawMetrics ? "Total Time" : "Moving Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min", isWorkoutStats: showRawMetrics)

                    let currentPace: Double = {
                        if showRawMetrics {
                            let totalKm = runRecord.totalDistanceMeters / 1000.0
                            return totalKm > 0 ? (runRecord.duration / totalKm) : runRecord.rawAvgPace
                        } else {
                            let workingKm = runRecord.effectiveWorkingDistanceMeters / 1000.0
                            return workingKm > 0 ? (runRecord.effectiveWorkingDurationSeconds / workingKm) : runRecord.workingAvgPace
                        }
                    }()
                    let currentHR = showRawMetrics ? runRecord.rawAvgHeartRate : runRecord.workingAvgHeartRate
                    let currentCadence = showRawMetrics ? runRecord.rawAvgCadence : runRecord.workingAvgCadence

                    StatBox(title: "Avg Pace", value: PaceFormatter.formatPace(secondsPerKilometer: currentPace), unit: "", currentValue: currentPace, baselineValue: showRawMetrics ? nil : baselinePace, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)
                    StatBox(title: "Avg HR", value: "\(Int(round(currentHR)))", unit: "BPM", currentValue: currentHR, baselineValue: showRawMetrics ? nil : baselineHR, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)
                    StatBox(title: "Avg Cadence", value: "\(Int(currentCadence))", unit: "SPM", currentValue: currentCadence, baselineValue: showRawMetrics ? nil : baselineCadence, polarity: .higherIsBetter, isWorkoutStats: showRawMetrics)

                    let currentOscillation = showRawMetrics ? (runRecord.rawAvgVerticalOscillation ?? runRecord.workingAvgVerticalOscillation) : (runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation)
                    StatBox(
                        title: "Vert. Osc.",
                        value: currentOscillation.map { String(format: "%.1f", $0) } ?? "--",
                        unit: currentOscillation != nil ? "cm" : "",
                        currentValue: currentOscillation,
                        baselineValue: showRawMetrics ? nil : baselineOscillation,
                        polarity: .lowerIsBetter,
                        isWorkoutStats: showRawMetrics
                    )
                }
                .padding(.horizontal)

                // MARK: Drills Section
                let isOlderThan7Days = (Calendar.current.dateComponents([.day], from: runRecord.date, to: Date()).day ?? 0) > 7

                if isOlderThan7Days {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pre-Run Drills")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Drills Library")
                                        .font(.subheadline.bold())
                                    Text("Drill recommendations are tailored for recent runs. Explore all pre-run technique drills in the library.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            NavigationLink(destination: DrillsLibraryView()) {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                                    Text("View All Drills")
                                }
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(20)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                } else if let insight = runRecord.insight {
                    if let drills = insight.drillRecommendations, !drills.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recommended Drills")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                NavigationLink(destination: DrillsLibraryView()) {
                                    HStack(spacing: 2) {
                                        Text("All Drills")
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal)

                            DrillDeckView(drills: drills)
                        }
                        .padding(.top, 12)
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
                }
            }
            .padding(.vertical)

            .task(id: runRecord.id) {
                let needsOscRepair = (runRecord.rawAvgVerticalOscillation == nil || runRecord.rawAvgVerticalOscillation == 0) &&
                   (runRecord.workingAvgVerticalOscillation == nil || runRecord.workingAvgVerticalOscillation == 0)
                let needsWorkingRepair = runRecord.workingDistanceMeters == nil || runRecord.workingDurationSeconds == nil
                if needsOscRepair || needsWorkingRepair {
                    if let workout = try? await HealthKitManager.shared.fetchWorkout(with: runRecord.hkWorkoutID) {
                        let engine = FramboiseEngine()
                        if let dto = try? await HealthKitManager.shared.extractRunRecord(from: workout, engine: engine) {
                            runRecord.rawAvgVerticalOscillation = dto.rawAvgVerticalOscillation
                            runRecord.workingAvgVerticalOscillation = dto.workingAvgVerticalOscillation
                            runRecord.workingDistanceMeters = dto.workingDistanceMeters
                            runRecord.workingDurationSeconds = dto.workingDurationSeconds
                            runRecord.workingAvgPace = dto.workingAvgPace
                            try? modelContext.save()
                        }
                    }
                }

                if runRecord.insight == nil {
                    let container = modelContext.container
                    let runId = runRecord.persistentModelID
                    if #available(iOS 26.0, *) {
                        Task.detached {
                            let analyzer = RunAnalyzerActor(modelContainer: container)
                            await analyzer.generateAnalysis(for: runId)
                        }
                    }
                }
            }
        }
        .refreshable {
            if #available(iOS 26.0, *) {
                isGeneratingInsight = true
                if let oldInsight = runRecord.insight {
                    modelContext.delete(oldInsight)
                    runRecord.insight = nil
                    try? modelContext.save()
                }

                let runId = runRecord.persistentModelID
                let container = modelContext.container

                let task = Task.detached {
                    let analyzer = RunAnalyzerActor(modelContainer: container)
                    await analyzer.generateAnalysis(for: runId)
                    await MainActor.run {
                        isGeneratingInsight = false
                    }
                }
                _ = await task.result
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(runRecord.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateClassification(to newType: String, from oldType: String? = nil) {
        let previous = oldType ?? runRecord.detectedTypeRaw
        guard newType != previous else { return }
        let correction = TrainingCorrection(
            runRecordID: runRecord.id,
            originalLabel: previous,
            correctedLabel: newType,
            featureVector: [runRecord.workingAvgPace, runRecord.paceCV, runRecord.paceSlope, runRecord.percentZone4, runRecord.duration / 60.0]
        )
        modelContext.insert(correction)
        runRecord.detectedTypeRaw = newType
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct StatBox: View {
    var title: String
    var value: String
    var unit: String
    var currentValue: Double?
    var baselineValue: Double?
    var polarity: MetricPolarity?
    var isWorkoutStats: Bool = false

    @State private var showingInfo = false

    var body: some View {
        let explainer = MetricDetailExplainer.explainer(for: title, isWorkoutStats: isWorkoutStats)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

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
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture { showingInfo = true }
        .sheet(isPresented: $showingInfo) {
            MetricExplainerSheet(
                title: explainer.title,
                mode: isWorkoutStats ? "Workout Stats" : "Working Stats",
                overview: explainer.overview,
                modeContext: explainer.modeContext,
                whyItMatters: explainer.whyItMatters,
                targetRange: explainer.targetRange
            )
        }
    }
}

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
            activeCardIndex: $activeCardIndex
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(relativeIndex == 0 ? 0 : 0.3)))
        .shadow(color: Color.black.opacity(relativeIndex == 0 ? 0.15 : 0.05), radius: relativeIndex == 0 ? 12 : 8, x: 0, y: relativeIndex == 0 ? 8 : 4)
        .rotationEffect(.degrees(relativeIndex == 0 ? (Double(offset.width) / 20.0) : rotationDegree))
        .offset(x: relativeIndex == 0 ? offset.width : 0, y: relativeIndex == 0 ? offset.height : 0)
        .opacity(relativeIndex == 0 ? (2 - Double(abs(offset.width / 150))) : 1.0)
        .zIndex(Double(totalDrills - index))
        .padding(.horizontal)
        .padding(.bottom, 20)
        .gesture(
            DragGesture(minimumDistance: 15).onChanged { dragGesture in updateDragOffset(dragGesture.translation, isActive: relativeIndex == 0) }
            .onEnded { _ in finishDrag(isActive: relativeIndex == 0, totalDrills: totalDrills) }
        )
    }

    var body: some View {
        let sortedDrills = drills.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
        if sortedDrills.count == 1, let firstDrill = sortedDrills.first {
            DrillCardView(
                drill: firstDrill,
                drillIndex: 0,
                totalDrills: 1,
                activeCardIndex: $activeCardIndex
            )
            .padding(.horizontal)
            .padding(.bottom, 20)
        } else {
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
}

private struct DrillCardView: View {
    @Bindable var drill: DrillRecommendation
    let drillIndex: Int
    let totalDrills: Int
    @Binding var activeCardIndex: Int
    @State private var isShowingWorkoutPreview = false
    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .strides).buildWorkoutPlan()
    @State private var pendingWatchDrillDTO: DrillPrescriptionDTO?
    @State private var showingTargetExplainer = false
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""

    var body: some View {
        let preRunId = PreRunDrillId(rawValue: drill.preRunDrillId ?? "") ?? .strides
        let template = DrillTemplate.template(for: preRunId)
        let displayTitle = drill.drillTitle.isEmpty ? template.title : drill.drillTitle
        let work = (drill.drillWork?.isEmpty == false ? drill.drillWork : nil) ?? template.defaultWork
        let recovery = (drill.drillRecovery?.isEmpty == false ? drill.drillRecovery : nil) ?? template.defaultRecovery
        let effort = (drill.drillEffort?.isEmpty == false ? drill.drillEffort : nil) ?? template.defaultEffort
        let purpose = (drill.drillPurpose?.isEmpty == false ? drill.drillPurpose : nil) ?? template.defaultPurpose

        VStack(alignment: .leading, spacing: 12) {
            if totalDrills > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<totalDrills, id: \.self) { barIndex in
                        Capsule()
                            .fill(barIndex == activeCardIndex ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 4)
                    }
                }
                .padding(.bottom, 2)
            }

            let drillIcon = PreRunDrill.iconName(for: drill.preRunDrillId, title: displayTitle)
            let drillColor = PreRunDrill.iconColor(for: drill.preRunDrillId, title: displayTitle)

            HStack(spacing: 8) {
                Image(systemName: drillIcon)
                    .foregroundColor(drillColor)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    let drillId = PreRunDrillId(rawValue: drill.preRunDrillId ?? "") ?? .strides
                    Text("\(PreRunDrill(id: drillId).duration.title) drill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if !purpose.isEmpty {
                Text(purpose)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if !work.isEmpty {
                    Label(work, systemImage: "repeat")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                if !recovery.isEmpty {
                    Label(recovery, systemImage: "moon.zzz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !effort.isEmpty {
                    Label(effort, systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            let cue: String? = {
                if let cueText = drill.drillCues, !cueText.isEmpty, !cueText.localizedCaseInsensitiveContains("spm") {
                    return cueText
                }
                let targetInt = Int(drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)
                let generated = template.generateInstructionalCue(targetInt)
                return generated.isEmpty ? nil : generated
            }()

            if let cue = cue, !cue.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(cue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
            }

            let isZone1 = preRunId == .aerobicFlush || preRunId == .recoveryJog
            let isZone2 = preRunId == .aerobicBaseBuilder || preRunId == .zone2Run
            let targetText: String? = {
                if isZone1 {
                    return "Target: Zone 1 HR"
                }
                if isZone2 {
                    return "Target: Zone 2 HR"
                }
                if let target = drill.targetCadence, !target.isEmpty {
                    let formattedTarget = target.contains("SPM") ? target : "\(target) SPM"
                    if let prev = drill.previousCadence {
                        return "Target: \(formattedTarget) (Previous: \(prev) SPM)"
                    } else {
                        return "Target: \(formattedTarget)"
                    }
                }
                return nil
            }()

            if let targetString = targetText {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .foregroundColor(.orange)
                        .font(.caption.bold())

                    Text(targetString)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showingTargetExplainer = true
                }
                .sheet(isPresented: $showingTargetExplainer) {
                    let explainerTitle: String = {
                        if isZone1 { return "Zone 1 Heart Rate" }
                        if isZone2 { return "Zone 2 Heart Rate" }
                        return "Target Cadence"
                    }()
                    let explainer = MetricDetailExplainer.explainer(for: explainerTitle, isWorkoutStats: false)
                    MetricExplainerSheet(explainer: explainer, mode: "Working Stats")
                }
            }

            let targetInt = Int(drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)

            HStack(spacing: 12) {
                Button(action: {
                    let preRunDrill = PreRunDrill(id: preRunId, previousCadence: drill.previousCadence, targetCadence: targetInt)
                    activeWorkoutPlan = preRunDrill.buildWorkoutPlan()
                    pendingWatchDrillDTO = DrillPrescriptionDTO(
                        title: drill.drillTitle,
                        preRunDrillId: preRunId.rawValue,
                        purpose: drill.drillPurpose ?? "",
                        targetCadence: targetInt,
                        previousCadence: drill.previousCadence
                    )
                    isShowingWorkoutPreview = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(UIColor.tertiarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: {
                    drill.isCompleted.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: drill.isCompleted ? "checkmark.circle.fill" : "circle")
                        Text(drill.isCompleted ? "Completed ✓" : "Mark completed")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(drill.isCompleted ? Color.green.opacity(0.15) : Color.orange)
                    .foregroundColor(drill.isCompleted ? .green : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 1)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
        .onChange(of: isShowingWorkoutPreview) { oldValue, newValue in
            if oldValue && !newValue, let dto = pendingWatchDrillDTO {
                pendingWatchDrillDTO = nil
                scheduleToWatch(dto: dto)
            }
        }
    }

    private func scheduleToWatch(dto: DrillPrescriptionDTO) {
        Task {
            if #available(iOS 17.0, *) {
                do {
                    let bridge = WorkoutBridge()
                    try await bridge.scheduleDrill(dto: dto)
                    await MainActor.run {
                        self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                        self.lastExportedDrillId = dto.preRunDrillId ?? ""
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } catch {
                    print("[RunDetailView] Failed to schedule drill: \(error.localizedDescription)")
                }
            }
        }
    }
}
