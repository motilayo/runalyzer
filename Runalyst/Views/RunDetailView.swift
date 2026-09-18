import SwiftUI
import UIKit
import SwiftData
import WorkoutKit

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var existingRuns: [RunRecord]

    @State private var showRawMetrics: Bool = false
    @State private var isForceAnalyzing: Bool = false
    @State private var showingToggleInfo = false
    @State private var showingClassificationExplainer = false
    @State private var showingDrillExplainer = false
    @State private var isGeneratingInsight = false

    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return existingRuns.filter {
            $0.date < runRecord.date &&
            $0.date >= thirtyDaysAgo
        }
    }

    private var baselinePace: Double? {
        let runs = baselineRuns.filter { $0.workingAvgPace > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.workingAvgPace).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineHR: Double? {
        let runs = baselineRuns.filter { $0.workingAvgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Double(runs.map(\.workingAvgHeartRate).reduce(0, +)) / Double(runs.count)
        }
        return runs.map { Double($0.workingAvgHeartRate) * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineCadence: Double? {
        let runs = baselineRuns.filter { $0.workingAvgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Double(runs.map(\.workingAvgCadence).reduce(0, +)) / Double(runs.count)
        }
        return runs.map { Double($0.workingAvgCadence) * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineOscillation: Double? {
        let runs = baselineRuns.compactMap { run -> (val: Double, dur: Double)? in
            guard let osc = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation, osc > 0 else { return nil }
            return (osc, run.duration)
        }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.dur).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.val).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.val * $0.dur }.reduce(0, +) / totalDuration
    }

    private var formattedRunDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d, yyyy 'at' hh:mm a"
        return formatter.string(from: runRecord.date)
    }

    private let classificationOptions = [
        "Steady Effort", "Easy Run", "Tempo Run", "Intervals", "Pyramids",
        "Progression Run", "Recovery Run", "Hill Repeats",
        "Long Run", "Fartlek", "Urban Traffic"
    ]

    private var prescribedDrillName: String? {
        // 1. Explicit tag "drill:<title>"
        if let tag = runRecord.framboiseTags.first(where: { $0.hasPrefix("drill:") }) {
            let candidate = String(tag.dropFirst(6))
            if let canonical = PreRunDrillId.canonicalDrillTitle(for: candidate) {
                return canonical
            }
            return candidate.replacingOccurrences(of: "_", with: " ").capitalized
        }
        // 2. PreRunDrillId rawValue in framboiseTags
        if let drill = PreRunDrillId.allCases.first(where: { runRecord.framboiseTags.contains($0.rawValue) }) {
            return drill.title
        }
        // 3. PreRunDrillId title in framboiseTags
        if let drill = PreRunDrillId.allCases.first(where: { runRecord.framboiseTags.contains($0.title) }) {
            return drill.title
        }
        // 4. If detectedTypeRaw is itself a legacy specific drill title (e.g. "Rhythm Intervals")
        if let canonical = PreRunDrillId.canonicalDrillTitle(for: runRecord.detectedTypeRaw) {
            return canonical
        }
        // 5. Associated completed drill recommendation from insight
        if let rec = runRecord.insight?.drillRecommendations?.first(where: { $0.isCompleted }),
           let canonical = PreRunDrillId.canonicalDrillTitle(for: rec.drillTitle) {
            return canonical
        }
        return nil
    }

    private var drillPillText: String {
        if let name = prescribedDrillName {
            return "Drill: \(name)"
        }
        return "Prescribed Drill"
    }

    private func normalizeDrillClassification() {
        // Clean up any invalid drill tags on runs that are not genuine drills
        cleanUpInvalidDrillTagsIfNeeded()

        // Only normalize if detectedTypeRaw is an ACTUAL drill title (e.g. "Rhythm Intervals"), never a standard classification like "Intervals"
        guard let canonicalDrill = PreRunDrillId.canonicalDrillTitle(for: runRecord.detectedTypeRaw),
              let parentClass = PreRunDrillId.correspondingClassification(for: runRecord.detectedTypeRaw) else {
            return
        }

        if !runRecord.framboiseTags.contains("prescribedDrill") {
            runRecord.framboiseTags.append("prescribedDrill")
        }
        let drillTag = "drill:\(canonicalDrill)"
        if !runRecord.framboiseTags.contains(drillTag) {
            runRecord.framboiseTags.append(drillTag)
        }
        if runRecord.detectedTypeRaw != parentClass {
            runRecord.detectedTypeRaw = parentClass
            try? modelContext.save()
        }
    }

    private func cleanUpInvalidDrillTagsIfNeeded() {
        // A run is only a prescribed drill if it has a confirmed authentic drill name
        if runRecord.framboiseTags.contains("prescribedDrill") && prescribedDrillName == nil {
            runRecord.framboiseTags.removeAll { tag in
                tag == "prescribedDrill" || tag.hasPrefix("drill:")
            }
            try? modelContext.save()
        }
    }

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        AIDisclaimerFooter()
    }

    @ViewBuilder
    private var drillControl: some View {
        if let drillName = prescribedDrillName {
            Menu {
                Menu {
                    ForEach(PreRunDrillId.allCases, id: \.self) { drill in
                        Button {
                            WorkoutBridge.linkDrill(to: runRecord, drillId: drill)
                            try? modelContext.save()
                        } label: {
                            if drill.title == drillName {
                                Label(drill.title, systemImage: "checkmark")
                            } else {
                                Label(drill.title, systemImage: drill.iconName)
                            }
                        }
                    }
                } label: {
                    Label("Change Drill", systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()

                Button(role: .destructive) {
                    WorkoutBridge.unlinkDrill(from: runRecord)
                    try? modelContext.save()
                } label: {
                    Label("Unlink Drill", systemImage: "xmark.circle")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(drillName)
                        .font(.caption.bold())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .opacity(0.8)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
            }
        } else {
            Menu {
                ForEach(PreRunDrillId.allCases, id: \.self) { drill in
                    Button {
                        WorkoutBridge.linkDrill(to: runRecord, drillId: drill)
                        try? modelContext.save()
                    } label: {
                        Label(drill.title, systemImage: drill.iconName)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.caption2.bold())
                    Text("Link Drill")
                        .font(.caption.bold())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .opacity(0.7)
                }
                .foregroundColor(Color(red: 0.05, green: 0.45, blue: 0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.05, green: 0.45, blue: 0.5).opacity(0.1))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(red: 0.05, green: 0.45, blue: 0.5).opacity(0.25), lineWidth: 1)
                )
            }
        }
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

                // MARK: Run Classification & Drill
                VStack(alignment: .leading, spacing: 8) {
                    // Row 1: Classification
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

                    // Row 2: Drill
                    HStack {
                        HStack(spacing: 5) {
                            Text("Drill:")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingDrillExplainer = true
                        }

                        Spacer()

                        drillControl
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showingClassificationExplainer) {
                    RunClassificationExplainerSheet()
                }
                .alert("Drill Tracking", isPresented: $showingDrillExplainer) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Link this workout to a drill (like Cadence Pyramids, Strides, or Zone 2 Run) to track your form adherence against coaching targets in Drill Performance.")
                }

                // MARK: Drill Scorecard
                if let drillName = prescribedDrillName, let drillId = PreRunDrillId.allCases.first(where: { $0.title == drillName || $0.rawValue == drillName }) {
                    DrillExecutionScorecard(runRecord: runRecord, drillId: drillId, baselineCadence: baselineCadence, baselineOscillation: baselineOscillation)
                        .padding(.horizontal)
                }

                let hasBiometrics = runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0

                // MARK: AI Run Analysis
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(hasBiometrics ? .purple : .secondary)
                        Text(hasBiometrics ? "AI Run Analysis" : "Sensor Data Limited")
                            .font(.subheadline.bold())
                            .foregroundColor(hasBiometrics ? .purple : .secondary)
                    }

                    if !hasBiometrics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Biometric Analysis Unavailable")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("This workout was recorded without an Apple Watch and has no cadence or heart rate sensor data. Runalyst requires continuous biometric telemetry to analyze form, cadence rhythm, and cardiac strain without hallucinating.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                        .padding(.vertical, 2)
                    } else if let insight = runRecord.insight {
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

                    if hasBiometrics {
                        aiDisclaimerFooter
                    }
                }
                .frame(minHeight: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal)
                .task {
                    if !hasBiometrics, let oldInsight = runRecord.insight {
                        modelContext.delete(oldInsight)
                        runRecord.insight = nil
                        try? modelContext.save()
                    } else if hasBiometrics && runRecord.insight == nil {
                        isGeneratingInsight = true
                        if #available(iOS 26.0, *) {
                            await CoachingEngine.shared.requestAnalysis(for: runRecord)
                            isGeneratingInsight = false
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

                    StatBox(title: "Avg Pace", value: PaceFormatter.formatPace(secondsPerKilometer: currentPace), unit: "", currentValue: currentPace > 0 ? currentPace : nil, baselineValue: (showRawMetrics || currentPace <= 0) ? nil : baselinePace, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)
                    StatBox(title: "Avg HR", value: currentHR > 0 ? "\(Int(round(currentHR)))" : "--", unit: currentHR > 0 ? "BPM" : "", currentValue: currentHR > 0 ? currentHR : nil, baselineValue: (showRawMetrics || currentHR <= 0) ? nil : baselineHR, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)
                    StatBox(title: "Avg Cadence", value: currentCadence > 0 ? "\(Int(currentCadence))" : "--", unit: currentCadence > 0 ? "SPM" : "", currentValue: currentCadence > 0 ? currentCadence : nil, baselineValue: (showRawMetrics || currentCadence <= 0) ? nil : baselineCadence, polarity: .higherIsBetter, isWorkoutStats: showRawMetrics)

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
                // Auto-resolve or reconcile drill recognition against authentic HealthKit workout metadata / scheduled intent
                if let workout = try? await HealthKitManager.shared.fetchWorkout(with: runRecord.hkWorkoutID) {
                    let matched = WorkoutBridge.matchDrill(workout: workout, durationSeconds: runRecord.duration)
                    if let matched = matched {
                        let drillTag = "drill:\(matched.drillTitle)"
                        if !runRecord.framboiseTags.contains(drillTag) {
                            runRecord.framboiseTags.removeAll { $0.hasPrefix("drill:") || PreRunDrillId.allCases.map(\.rawValue).contains($0) }
                            if !runRecord.framboiseTags.contains("prescribedDrill") {
                                runRecord.framboiseTags.append("prescribedDrill")
                            }
                            if let preRunId = matched.preRunDrillId {
                                runRecord.framboiseTags.append(preRunId)
                            }
                            runRecord.framboiseTags.append(drillTag)
                        }
                        if let parentClass = PreRunDrillId.correspondingClassification(for: matched.drillTitle),
                           runRecord.detectedTypeRaw != parentClass {
                            runRecord.detectedTypeRaw = parentClass
                        }
                        try? modelContext.save()
                    }
                }

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
                    if #available(iOS 26.0, *) {
                        await CoachingEngine.shared.requestAnalysis(for: runRecord)
                    }
                }
            }
        }
        .refreshable {
            if #available(iOS 26.0, *) {
                isGeneratingInsight = true
                await CoachingEngine.shared.requestAnalysis(for: runRecord, force: true)
                isGeneratingInsight = false
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeDrillClassification()
        }
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
        return DrillCardView(
            drill: drill,
            drillIndex: index,
            totalDrills: totalDrills,
            activeCardIndex: $activeCardIndex
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(relativeIndex == 0 ? 0 : 0.3)))
        .shadow(color: Color.black.opacity(relativeIndex == 0 ? 0.15 : 0.05), radius: relativeIndex == 0 ? 12 : 8, x: 0, y: relativeIndex == 0 ? 8 : 4)
        .rotationEffect(.degrees(relativeIndex == 0 ? (Double(offset.width) / 20.0) : 0))
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
        let preRunId = PreRunDrillId(rawValue: drill.preRunDrillId ?? "")
            ?? PreRunDrillId.allCases.first(where: {
                $0.title.localizedCaseInsensitiveCompare(drill.drillTitle) == .orderedSame ||
                $0.rawValue.localizedCaseInsensitiveCompare(drill.drillTitle) == .orderedSame ||
                $0.title.localizedCaseInsensitiveCompare(drill.drillTitle.replacingOccurrences(of: "_", with: " ")) == .orderedSame
            })
            ?? .strides
        let template = DrillTemplate.template(for: preRunId)
        let displayTitle = drill.formattedTitle.isEmpty ? template.title : drill.formattedTitle
        let work = (drill.drillWork?.isEmpty == false ? drill.drillWork : nil) ?? template.defaultWork
        let recovery = (drill.drillRecovery?.isEmpty == false ? drill.drillRecovery : nil) ?? template.defaultRecovery
        let effort = (drill.drillEffort?.isEmpty == false ? drill.drillEffort : nil) ?? template.defaultEffort
        let purpose = (drill.drillPurpose?.isEmpty == false ? drill.drillPurpose : nil) ?? template.defaultPurpose

        VStack(alignment: .leading, spacing: 12) {
            if totalDrills > 1 {
                HStack {
                    HStack(spacing: 4) {
                        ForEach(0..<totalDrills, id: \.self) { barIndex in
                            Capsule()
                                .fill(barIndex == activeCardIndex ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: 16, height: 4)
                        }
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if activeCardIndex > 0 { activeCardIndex -= 1 }
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(activeCardIndex > 0 ? .primary : .secondary.opacity(0.3))
                        }
                        .disabled(activeCardIndex == 0)

                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if activeCardIndex < totalDrills - 1 { activeCardIndex += 1 }
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(activeCardIndex < totalDrills - 1 ? .primary : .secondary.opacity(0.3))
                        }
                        .disabled(activeCardIndex == totalDrills - 1)
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
                let targetInt = drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)
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
            let isZone2 = preRunId == .zone2Run
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

            let targetInt = drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)

            HStack(spacing: 12) {
                Button(action: {
                    let preRunDrill = PreRunDrill(id: preRunId, previousCadence: drill.previousCadence, targetCadence: targetInt)
                    activeWorkoutPlan = preRunDrill.buildWorkoutPlan()
                    pendingWatchDrillDTO = DrillPrescriptionDTO(
                        title: displayTitle,
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
                    try? drill.modelContext?.save()
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

enum DrillAdherenceTier {
    case exceeded
    case met
    case partiallyMet
    case notMet

    var badgeText: String {
        switch self {
        case .exceeded: return "Exceeded"
        case .met: return "Met"
        case .partiallyMet: return "Partially Met"
        case .notMet: return "Not Met"
        }
    }

    var badgeIcon: String {
        switch self {
        case .exceeded: return "star.fill"
        case .met: return "checkmark"
        case .partiallyMet: return "minus"
        case .notMet: return "xmark"
        }
    }

    var tintColor: Color {
        switch self {
        case .exceeded: return Color(red: 0.0, green: 0.75, blue: 0.65)
        case .met: return .green
        case .partiallyMet: return .orange
        case .notMet: return .red
        }
    }
}

struct DrillExecutionScorecard: View {
    let runRecord: RunRecord
    let drillId: PreRunDrillId
    let baselineCadence: Double?
    let baselineOscillation: Double?

    var body: some View {
        let template = DrillTemplate.template(for: drillId)
        let thirtyDayCadence = Int(baselineCadence ?? (runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : 155))
        let targetCadence = template.calculateTargetCadence(thirtyDayCadence)
        let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
        let actualCadence = Int(runRecord.workingAvgCadence)
        let actualHR = Int(runRecord.workingAvgHeartRate)

        let isHRTarget = drillId.isHeartRateTargeted
        let isDualTarget = (drillId == .tempoSurges)
        let targetCadenceStr = drillObj.computedCadence ?? "Steady"

        let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation ?? 9.5
        let baseOsc = baselineOscillation ?? 9.5
        let oscDelta = currentOsc - baseOsc

        // Attempt to parse stored interval-by-interval results from framboiseTags
        let intervalSummary: DrillIntervalSummary? = {
            if let parsed = DrillIntervalSummary.from(tags: runRecord.framboiseTags, drillId: drillId) {
                return parsed
            }
            if !isHRTarget && !drillId.isAerobicContinuous {
                // Synthesize baseline interval evaluation if not yet tagged
                return DrillIntervalEvaluator.evaluate(
                    buckets: [],
                    drillId: drillId,
                    baselineCadence: thirtyDayCadence,
                    workoutDuration: runRecord.duration,
                    oscDelta: oscDelta
                )
            }
            return nil
        }()

        let isIntervalDrill = (intervalSummary?.totalIntervals ?? 0) > 1

        let tier: DrillAdherenceTier
        let tierDescription: String

        if let summary = intervalSummary, isIntervalDrill {
            tier = summary.tier
            tierDescription = summary.verdict
        } else if isDualTarget {
            // Tempo Surges: Cadence + Zone 4 Threshold
            let cadenceExact: Bool = {
                if let range = drillObj.effectiveTargetCadence {
                    return range.contains(actualCadence)
                }
                return true
            }()
            let cadenceClose: Bool = {
                if let range = drillObj.effectiveTargetCadence {
                    return actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2
                }
                return true
            }()
            let zone4Percent = runRecord.percentZone4

            if cadenceExact && zone4Percent >= 0.35 {
                tier = .exceeded
                tierDescription = "Held target turnover with high threshold capacity (≥35% Zone 4)."
            } else if (cadenceExact || cadenceClose) && zone4Percent >= 0.20 {
                tier = .met
                tierDescription = "Landed in target cadence band with sustained threshold effort."
            } else if cadenceExact || zone4Percent >= 0.15 {
                tier = .partiallyMet
                tierDescription = cadenceExact ? "Hit turnover target, but effort remained sub-threshold." : "Reached threshold intensity, but cadence was off target."
            } else {
                tier = .notMet
                tierDescription = "Missed both target cadence and threshold intensity goals."
            }
        } else if isHRTarget {
            if let zone = drillId.targetHeartRateZone {
                if zone == 2 {
                    if actualHR > 0 {
                        if runRecord.percentZone4 <= 0.04 && actualCadence >= 155 {
                            tier = .exceeded
                            tierDescription = "Preserved Zone 2 ceiling with crisp turnover (≥155 SPM)."
                        } else if runRecord.percentZone4 <= 0.08 {
                            tier = .met
                            tierDescription = "Successfully maintained steady Zone 2 aerobic intensity."
                        } else if runRecord.percentZone4 <= 0.20 {
                            tier = .partiallyMet
                            tierDescription = "Moderate intensity drift; spent partial duration above Zone 2."
                        } else {
                            tier = .notMet
                            tierDescription = "Cardiac drift exceeded aerobic threshold into Zones 3 and 4."
                        }
                    } else {
                        tier = .met
                        tierDescription = "Completed steady aerobic effort."
                    }
                } else { // zone 1
                    if actualHR > 0 {
                        if runRecord.percentZone4 == 0 && actualHR <= 125 {
                            tier = .exceeded
                            tierDescription = "Flawless active recovery with zero cardiac strain."
                        } else if runRecord.percentZone4 <= 0.03 && actualHR <= 135 {
                            tier = .met
                            tierDescription = "Controlled intensity within the Zone 1 recovery envelope."
                        } else if runRecord.percentZone4 <= 0.10 {
                            tier = .partiallyMet
                            tierDescription = "Effort drifted slightly higher than target recovery ceiling."
                        } else {
                            tier = .notMet
                            tierDescription = "Intensity was too elevated for an active recovery run."
                        }
                    } else {
                        tier = .met
                        tierDescription = "Completed gentle recovery effort."
                    }
                }
            } else {
                tier = .met
                tierDescription = "Completed aerobic session."
            }
        } else if let range = drillObj.effectiveTargetCadence {
            let zeroSpike = runRecord.percentZone4 <= 0.05
            let formImproved = oscDelta <= 0
            if range.contains(actualCadence) && zeroSpike && formImproved {
                tier = .exceeded
                tierDescription = "Target turnover held with effortless aerobic stability and form control."
            } else if range.contains(actualCadence) {
                tier = .met
                tierDescription = "Cadence landed precisely within the target \(targetCadenceStr) SPM band."
            } else if actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2 {
                tier = .partiallyMet
                tierDescription = "Turnover was close to target (within 2 SPM of target band)."
            } else {
                tier = .notMet
                tierDescription = "Turnover missed the target cadence band by more than 2 SPM."
            }
        } else {
            tier = .met
            tierDescription = "Completed steady effort drill."
        }

        return VStack(spacing: 14) {
            // Header: Icon + Title + Capsule Badge (Single line)
            HStack(spacing: 8) {
                Image(systemName: drillId.iconName)
                    .foregroundColor(drillId.iconColor)
                    .font(.title3)
                Text("Drill Performance")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: tier.badgeIcon)
                        .font(.caption2.bold())
                    Text(tier.badgeText)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tier.tintColor.opacity(0.12))
                .foregroundColor(tier.tintColor)
                .clipShape(Capsule())
            }

            // Interval Adherence Meter (Pips + Fraction)
            if let summary = intervalSummary, isIntervalDrill {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Interval Adherence")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(summary.intervalsMet) of \(summary.totalIntervals) on Target (\(summary.adherencePercentage)%)")
                            .font(.caption.bold())
                            .foregroundColor(summary.tier.tintColor)
                    }

                    // Pips (R1, R2, ...)
                    HStack(spacing: 6) {
                        ForEach(summary.reps, id: \.repIndex) { rep in
                            HStack(spacing: 3) {
                                Image(systemName: rep.isMet ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundColor(rep.isMet ? .green : .orange)
                                Text("R\(rep.repIndex)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(rep.isMet ? .primary : .secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(rep.isMet ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // Primary Target vs Actual Metric Tiles
            if let summary = intervalSummary, isIntervalDrill {
                HStack(spacing: 10) {
                    metricTile(
                        label: "WORK CADENCE",
                        value: "\(summary.workCadenceAvg > 0 ? summary.workCadenceAvg : actualCadence) SPM",
                        valueColor: summary.tier == .notMet ? .red : (summary.tier == .partiallyMet ? .orange : .green),
                        subtitle: "Target: \(targetCadenceStr) SPM"
                    )
                    metricTile(
                        label: "RECOVERY CADENCE",
                        value: "\(summary.recoveryCadenceAvg > 0 ? summary.recoveryCadenceAvg : max(130, actualCadence - 20)) SPM",
                        valueColor: .secondary,
                        subtitle: "Walk / Easy Jog"
                    )
                }
            } else if isDualTarget {
                // Dual Target (Cadence + Zone 4 Threshold)
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        metricTile(
                            label: "TARGET CADENCE",
                            value: "\(targetCadenceStr) SPM",
                            valueColor: .primary
                        )
                        metricTile(
                            label: "ACTUAL CADENCE",
                            value: "\(actualCadence) SPM",
                            valueColor: tier == .notMet ? .red : (tier == .partiallyMet ? .orange : .green)
                        )
                    }

                    HStack(spacing: 10) {
                        metricTile(
                            label: "THRESHOLD GOAL",
                            value: "≥20% Zone 4",
                            valueColor: .primary
                        )
                        metricTile(
                            label: "ZONE 4 TIME",
                            value: String(format: "%.0f%%", runRecord.percentZone4 * 100),
                            valueColor: runRecord.percentZone4 >= 0.20 ? .green : .orange
                        )
                    }
                }
            } else if isHRTarget {
                // Heart Rate Hero Metric
                HStack(spacing: 10) {
                    metricTile(
                        label: "TARGET ZONE",
                        value: drillId.targetHeartRateZoneName ?? "Zone 2",
                        valueColor: .primary
                    )
                    metricTile(
                        label: "ACTUAL HEART RATE",
                        value: actualHR > 0 ? "\(actualHR) BPM" : "--",
                        valueColor: tier == .notMet ? .red : (tier == .partiallyMet ? .orange : .green)
                    )
                }
            } else {
                // Cadence Hero Metric
                HStack(spacing: 10) {
                    metricTile(
                        label: "TARGET CADENCE",
                        value: "\(targetCadenceStr) SPM",
                        valueColor: .primary
                    )
                    metricTile(
                        label: "ACTUAL CADENCE",
                        value: "\(actualCadence) SPM",
                        valueColor: tier == .notMet ? .red : (tier == .partiallyMet ? .orange : .green)
                    )
                }
            }

            // Secondary Form / Guardrail Chips
            let hasFormDelta = abs(oscDelta) > 0.01 && runRecord.workingAvgVerticalOscillation != nil
            let hasTurnoverChip = isHRTarget && actualCadence > 0
            let hasZone4Chip = !isDualTarget && runRecord.percentZone4 > 0.15

            if hasFormDelta || hasTurnoverChip || hasZone4Chip {
                HStack(spacing: 8) {
                    if hasFormDelta {
                        HStack(spacing: 4) {
                            Image(systemName: oscDelta < 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.caption2.bold())
                            Text(String(format: "Form Delta: %+.1f cm", oscDelta))
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(oscDelta < 0 ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .foregroundColor(oscDelta < 0 ? .green : .orange)
                        .clipShape(Capsule())
                    }

                    if hasTurnoverChip {
                        HStack(spacing: 4) {
                            Image(systemName: "shoeprints.fill")
                                .font(.caption2)
                            Text("Turnover: \(actualCadence) SPM")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    }

                    if hasZone4Chip {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                            Text(String(format: "Zone 4 Spike: %.0f%%", runRecord.percentZone4 * 100))
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
            }

            // Coaching Verdict Callout Banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tier == .notMet ? "xmark.circle.fill" : (tier == .partiallyMet ? "info.circle.fill" : "checkmark.seal.fill"))
                    .font(.caption)
                    .foregroundColor(tier.tintColor)
                    .padding(.top, 1)
                Text(tierDescription)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(10)
            .background(tier.tintColor.opacity(0.08))
            .cornerRadius(8)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(drillId.iconColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func metricTile(label: String, value: String, valueColor: Color, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(valueColor)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}
