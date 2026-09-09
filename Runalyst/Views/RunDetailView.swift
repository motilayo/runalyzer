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
            VStack(spacing: 20) {
                // Formatted run date header
                Text(formattedRunDate)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)

                // MARK: CoreML Override
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Classification:")
                            .font(.subheadline)
                            .foregroundColor(.primary)

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

                    Text("< CoreML Override")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // MARK: AI Run Analysis
                if let insight = runRecord.insight {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("AI Run Analysis")
                                .font(.subheadline.bold())
                                .foregroundColor(.purple)
                        }

                        if !insight.longitudinalObservation.isEmpty {
                            Text(insight.longitudinalObservation)
                                .font(.body)
                                .foregroundColor(.primary)
                        } else if !insight.headline.isEmpty {
                            Text(insight.headline)
                                .font(.body)
                                .foregroundColor(.primary)
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
                }

                // MARK: Data Toggle
                Picker("Metrics Type", selection: $showRawMetrics) {
                    Text("Working Averages").tag(false)
                    Text("Raw Totals (HealthKit)").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // MARK: Metrics Grid
                let columns = verticalSizeClass == .regular
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

                LazyVGrid(columns: columns, spacing: 16) {
                    let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                    let activeDistanceMeters = showRawMetrics ? runRecord.totalDistanceMeters : runRecord.effectiveWorkingDistanceMeters
                    let distanceConverted = useMetricSystem ? (activeDistanceMeters / 1000.0) : (activeDistanceMeters / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit)

                    let activeDuration = showRawMetrics ? runRecord.duration : runRecord.effectiveWorkingDurationSeconds
                    let minutes = Int(activeDuration) / 60
                    let seconds = Int(activeDuration) % 60
                    StatBox(title: "Total Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min")

                    let currentPace: Double = {
                        if showRawMetrics {
                            return runRecord.rawAvgPace
                        } else {
                            let workingKm = runRecord.effectiveWorkingDistanceMeters / 1000.0
                            return workingKm > 0 ? (runRecord.effectiveWorkingDurationSeconds / workingKm) : runRecord.workingAvgPace
                        }
                    }()
                    let currentHR = showRawMetrics ? runRecord.rawAvgHeartRate : runRecord.workingAvgHeartRate
                    let currentCadence = showRawMetrics ? runRecord.rawAvgCadence : runRecord.workingAvgCadence

                    StatBox(title: "Avg Pace", value: PaceFormatter.formatPace(secondsPerKilometer: currentPace), unit: "", currentValue: currentPace, baselineValue: showRawMetrics ? nil : baselinePace, polarity: .lowerIsBetter)
                    StatBox(title: "Avg HR", value: "\(Int(currentHR))", unit: "BPM", currentValue: currentHR, baselineValue: showRawMetrics ? nil : baselineHR, polarity: .lowerIsBetter)
                    StatBox(title: "Avg Cadence", value: "\(Int(currentCadence))", unit: "SPM", currentValue: currentCadence, baselineValue: showRawMetrics ? nil : baselineCadence, polarity: .higherIsBetter)

                    let currentOscillation = showRawMetrics ? (runRecord.rawAvgVerticalOscillation ?? runRecord.workingAvgVerticalOscillation) : (runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation)
                    StatBox(
                        title: "Vert. Osc.",
                        value: currentOscillation != nil ? String(format: "%.1f", currentOscillation!) : "--",
                        unit: currentOscillation != nil ? "cm" : "",
                        currentValue: currentOscillation,
                        baselineValue: showRawMetrics ? nil : baselineOscillation,
                        polarity: .lowerIsBetter
                    )
                }
                .padding(.horizontal)

                // MARK: Recommended Pre-Run Corrective Drills
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended Pre-Run Corrective Drills")
                        .font(.headline)
                        .foregroundColor(.primary)

                    NavigationLink(destination: DrillsLibraryView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "stopwatch")
                                .foregroundColor(.secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                let drillTitle = runRecord.insight?.drillRecommendation?.drillTitle ?? "Cadence Correction Drill"
                                Text(drillTitle)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("10-12 min targeted neuromuscular primer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                }
                .padding(.horizontal)

                // MARK: Drill Generator
                let olderThan7Days = Calendar.current.dateComponents([.day], from: runRecord.date, to: Date()).day ?? 0 > 7

                if !olderThan7Days {
                    if let insight = runRecord.insight {
                        if let drills = insight.drillRecommendations, !drills.isEmpty {
                            DrillDeckView(drills: drills)
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
                }
            }
            .padding(.vertical)
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
    var currentValue: Double? = nil
    var baselineValue: Double? = nil
    var polarity: MetricPolarity? = nil

    @State private var showingInfo = false

    private var definition: String {
        switch title.lowercased() {
        case "distance": return "The total distance covered during your run."
        case "total time": return "The total elapsed time of your run."
        case "avg pace": return "Your working average speed, excluding dead stops."
        case "raw pace": return "Raw pace including dead stops."
        case "avg hr": return "Your working average heart rate."
        case "raw hr": return "Raw heart rate."
        case "avg cadence": return "Your working average step rate (SPM)."
        case "raw cadence": return "Raw step rate."
        case "pace cv": return "Pace Coefficient of Variation."
        default: return "A running metric."
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
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture { showingInfo = true }
        .sheet(isPresented: $showingInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text(definition).font(.subheadline).foregroundColor(.secondary)
            }
            .padding()
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
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
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(UIColor.secondarySystemGroupedBackground)))
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
            DragGesture().onChanged { g in updateDragOffset(g.translation, isActive: relativeIndex == 0) }
            .onEnded { _ in finishDrag(isActive: relativeIndex == 0, totalDrills: totalDrills) }
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

private struct DrillCardView: View {
    @Bindable var drill: DrillRecommendation
    let drillIndex: Int
    let totalDrills: Int
    @Binding var activeCardIndex: Int
    let dismiss: DismissAction
    
    @State private var isSchedulingWorkout = false
    @State private var workoutHandoffError: String?
    @State private var workoutHandoffSucceeded = false
    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .strides).buildWorkoutPlan()
    @State private var isShowingWorkoutPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    ForEach(0..<totalDrills, id: \.self) { barIndex in
                        Capsule().fill(barIndex == activeCardIndex ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 16, height: 4)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.secondary) }
            }

            Text("DRILL \(String(format: "%02d", drillIndex + 1))")
                .font(.caption).fontWeight(.bold).textCase(.uppercase).foregroundColor(.secondary)
            if !drill.drillTitle.isEmpty {
                Text(drill.drillTitle).font(.title).fontWeight(.bold).foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 12) {
                DrillRow(icon: "target", text: drill.drillPurpose ?? "")
                DrillRow(icon: "repeat", text: drill.drillWork ?? "")
                DrillRow(icon: "moon.zzz", text: drill.drillRecovery ?? "")
                DrillRow(icon: "brain.head.profile", text: drill.drillCues ?? "")
                DrillRow(icon: "bolt", text: drill.drillEffort ?? "")
            }

            if let target = drill.targetCadence, let prev = drill.previousCadence, !target.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cadence Goal").font(.caption).foregroundColor(.secondary)
                    Text("Current: \(prev) SPM → Target: \(target)").font(.subheadline.bold()).foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
            
            // WorkoutKit Buttons
            if #available(iOS 17.0, *) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: {
                            startDrill()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.white)
                                Text("Start Drill")
                                    .foregroundColor(.white)
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button(action: {
                            scheduleDrill()
                        }) {
                            HStack(spacing: 6) {
                                if isSchedulingWorkout {
                                    ProgressView()
                                        .tint(.white)
                                } else if workoutHandoffSucceeded {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                    Text("Sent")
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "applewatch")
                                        .foregroundColor(.white)
                                    Text("Send to Watch")
                                        .foregroundColor(.white)
                                }
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                workoutHandoffSucceeded ? Color.blue :
                                    (drill.isCompleted ? Color.secondary.opacity(0.3) : Color(red: 0.05, green: 0.45, blue: 0.5))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSchedulingWorkout || drill.isCompleted || workoutHandoffSucceeded)
                    }

                    if let error = workoutHandoffError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer(minLength: 16)

            HStack {
                if activeCardIndex > 0 {
                    Button("Back") { withAnimation(.spring()) { activeCardIndex -= 1 } }.font(.subheadline.bold()).foregroundColor(.secondary)
                } else {
                    Button("Skip") { withAnimation(.spring()) { if activeCardIndex < totalDrills - 1 { activeCardIndex += 1 } } }.font(.subheadline.bold()).foregroundColor(.secondary)
                }
                Spacer()
                if activeCardIndex < totalDrills - 1 {
                    Button(action: { withAnimation(.spring()) { activeCardIndex += 1 } }) {
                        Text("Next").font(.subheadline.bold()).foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 12).background(Color.accentColor).clipShape(Capsule())
                    }
                } else {
                    Button(action: {
                        drill.isCompleted = true
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    }) {
                        Text(drill.isCompleted ? "Completed" : "Mark Completed")
                            .font(.subheadline.bold()).foregroundColor(Color.white).padding(.horizontal, 24).padding(.vertical, 12).background(drill.isCompleted ? Color.green : Color.accentColor).clipShape(Capsule())
                    }
                }
            }
        }
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
        .frame(maxWidth: .infinity, minHeight: 1)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
    }
    
    private func startDrill() {
        let preRunId = PreRunDrillId(rawValue: drill.preRunDrillId ?? "") ?? .strides
        let targetCadence = Int(drill.targetCadence?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "") ?? nil
        let drillObj = PreRunDrill(id: preRunId, previousCadence: drill.previousCadence, targetCadence: targetCadence)
        activeWorkoutPlan = drillObj.buildWorkoutPlan()
        isShowingWorkoutPreview = true
    }
    
    private func scheduleDrill() {
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

            let authorizationState = await WorkoutScheduler.shared.requestAuthorization()
            guard authorizationState == .authorized else {
                workoutHandoffError = "WorkoutKit authorization is required to send this drill to Apple Watch."
                isSchedulingWorkout = false
                return
            }

            let dto = DrillPrescriptionDTO(
                title: drill.drillTitle,
                preRunDrillId: drill.preRunDrillId,
                purpose: drill.drillPurpose ?? "",
                targetCadence: Int(drill.targetCadence?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "") ?? nil,
                previousCadence: drill.previousCadence
            )
            do {
                let bridge = WorkoutBridge()
                try await bridge.scheduleDrill(dto: dto)

                drill.isCompleted = true
                isSchedulingWorkout = false
                workoutHandoffSucceeded = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                workoutHandoffError = "Failed to schedule workout: \(error.localizedDescription)"
                isSchedulingWorkout = false
            }
        }
    }
}
