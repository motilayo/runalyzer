import SwiftUI
import UIKit
import SwiftData
import HealthKit
import WorkoutKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0

    @State private var isSyncing: Bool = true
    @State private var selectedFilter: String?

    @AppStorage("dashboardTimeRange") private var timeRange: String = "30 Days"
    @AppStorage("lastBaselineChangeTimestamp") private var lastBaselineChangeTimestamp: Double = 0
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""
    @AppStorage("primerCompletedDate") private var primerCompletedDate: String = ""

    @AppStorage("cachedHeadline_7Day") private var cachedHeadline7Day: String = ""
    @AppStorage("cachedBody_7Day") private var cachedBody7Day: String = ""

    @AppStorage("cachedHeadline_30Day") private var cachedHeadline30Day: String = ""
    @AppStorage("cachedBody_30Day") private var cachedBody30Day: String = ""

    @AppStorage("cachedHeadline_AllTime") private var cachedHeadlineAllTime: String = ""
    @AppStorage("cachedBody_AllTime") private var cachedBodyAllTime: String = ""

    @AppStorage("lastInsightRunCount") private var lastInsightRunCount: Int = 0

    @State private var isFetchingInsight = false
    @State private var isShowingWorkoutPreview: Bool = false
    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .strides).buildWorkoutPlan()
    @State private var pendingWatchDrillDTO: DrillPrescriptionDTO?
    @State private var activeExplainer: MetricExplainerInfo?

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        var filtered = runRecords.filter { $0.totalDistanceMeters >= (minDistanceInMeters - 0.01) }

        // Time filter
        let now = Date()
        if timeRange == "7 Days", let limit = Calendar.current.date(byAdding: .day, value: -7, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        } else if timeRange == "30 Days", let limit = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        }

        if let filter = selectedFilter {
            filtered = filtered.filter { $0.detectedTypeRaw == filter || $0.framboiseTags.contains(filter) }
        }
        return filtered
    }

    var baselineCadence: Int? {
        let runs = filteredRunRecords.filter { $0.workingAvgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        return Int(runs.map(\.workingAvgCadence).reduce(0, +)) / runs.count
    }

    var baselinePace: Double? {
        let runs = filteredRunRecords.filter { $0.workingAvgPace > 0 }
        guard !runs.isEmpty else { return nil }
        return runs.map(\.workingAvgPace).reduce(0, +) / Double(runs.count)
    }

    private var previousBaselineCadence: Int? {
        let calendar = Calendar.current
        let now = Date()
        let previousRuns: [RunRecord]
        if timeRange == "7 Days" {
            guard let start = calendar.date(byAdding: .day, value: -14, to: now),
                  let end = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgCadence > 0 }
        } else if timeRange == "30 Days" {
            guard let start = calendar.date(byAdding: .day, value: -60, to: now),
                  let end = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgCadence > 0 }
        } else {
            return nil
        }
        guard !previousRuns.isEmpty else { return nil }
        return Int(previousRuns.map(\.workingAvgCadence).reduce(0, +)) / previousRuns.count
    }

    private var previousBaselinePace: Double? {
        let calendar = Calendar.current
        let now = Date()
        let previousRuns: [RunRecord]
        if timeRange == "7 Days" {
            guard let start = calendar.date(byAdding: .day, value: -14, to: now),
                  let end = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgPace > 0 }
        } else if timeRange == "30 Days" {
            guard let start = calendar.date(byAdding: .day, value: -60, to: now),
                  let end = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgPace > 0 }
        } else {
            return nil
        }
        guard !previousRuns.isEmpty else { return nil }
        return previousRuns.map(\.workingAvgPace).reduce(0, +) / Double(previousRuns.count)
    }

    private var workoutDensityTier: String {
        let count = filteredRunRecords.count
        switch timeRange {
        case "7 Days":
            if count <= 2 { return "Low" }
            if count <= 4 { return "Moderate" }
            return "Optimal"
        case "30 Days":
            if count <= 6 { return "Low" }
            if count <= 12 { return "Moderate" }
            return "Optimal"
        default: // All Time
            if count <= 10 { return "Low" }
            if count <= 25 { return "Moderate" }
            return "Optimal"
        }
    }

    private var isPrimerCompletedToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return primerCompletedDate == formatter.string(from: Date())
    }

    private func togglePrimerCompletedToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        if primerCompletedDate == today {
            primerCompletedDate = ""
        } else {
            primerCompletedDate = today
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // Extract unique tags for filter chips
    var availableFilters: [String] {
        var tags = Set<String>()
        for run in runRecords {
            tags.insert(run.detectedTypeRaw)
            for tag in run.framboiseTags {
                tags.insert(tag)
            }
        }
        return Array(tags).sorted()
    }

    var onSync: ((Bool) async -> Void)?

    @State private var globalVO2Max: Double?
    @State private var baselineVO2Max: Double?

    @ViewBuilder
    private var filterControlsSection: some View {
        VStack(spacing: 12) {
            Picker("Time Range", selection: $timeRange) {
                Text("7 Days").tag("7 Days")
                Text("30 Days").tag("30 Days")
                Text("All Time").tag("All Time")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Min Distance: \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $minimumRunDistance, in: useMetricSystem ? 0.5...10.0 : 0.3...6.0, step: 0.1)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var aiFatigueInsightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundColor(.primary)
                Text("AI Fatigue Insight")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                let headline = currentHeadline()
                HStack {
                    Text("✨ \(headline.isEmpty ? "Acute Fatigue Detected" : headline)")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                let bodyText = currentBody()
                Text(bodyText.isEmpty ? "You've put in some solid work this week, but your heart rate shows you're carrying a bit of fatigue. Keep things light today to let your legs bounce back." : bodyText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                AIDisclaimerFooter()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            .padding(.horizontal)
        }
        .onAppear {
            checkAndFetchInsight()
        }
        .onChange(of: timeRange) {
            checkAndFetchInsight()
            refreshBaselineVO2Max()
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
        .onChange(of: minimumRunDistance) {
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
    }

    private func currentHeadline() -> String {
        switch timeRange {
        case "7 Days": return cachedHeadline7Day
        case "30 Days": return cachedHeadline30Day
        case "All Time": return cachedHeadlineAllTime
        default: return ""
        }
    }

    private func currentBody() -> String {
        switch timeRange {
        case "7 Days": return cachedBody7Day
        case "30 Days": return cachedBody30Day
        case "All Time": return cachedBodyAllTime
        default: return ""
        }
    }

    private func checkAndFetchInsight() {
        let currentRunCount = runRecords.count
        if currentRunCount != lastInsightRunCount {
            // Invalidate cache
            cachedHeadline7Day = ""
            cachedBody7Day = ""
            cachedHeadline30Day = ""
            cachedBody30Day = ""
            cachedHeadlineAllTime = ""
            cachedBodyAllTime = ""
            lastInsightRunCount = currentRunCount
        }

        if currentHeadline().isEmpty || currentBody().isEmpty {
            fetchInsight()
        }
    }

    private func fetchInsight() {
        guard !isFetchingInsight else { return }
        guard !filteredRunRecords.isEmpty else { return }
        isFetchingInsight = true

        let avgPace = filteredRunRecords.map(\.workingAvgPace).reduce(0, +) / Double(filteredRunRecords.count)
        let avgHR = filteredRunRecords.map(\.workingAvgHeartRate).reduce(0, +) / Double(filteredRunRecords.count)
        let avgCadence = filteredRunRecords.map(\.workingAvgCadence).reduce(0, +) / Double(filteredRunRecords.count)
        let avgCV = filteredRunRecords.map(\.paceCV).reduce(0, +) / Double(filteredRunRecords.count)
        let avgSlope = filteredRunRecords.map(\.paceSlope).reduce(0, +) / Double(filteredRunRecords.count)
        let zone4Sum = filteredRunRecords.map(\.percentZone4).reduce(0, +) / Double(filteredRunRecords.count)

        let paceContext = PaceFormatter.formatPace(secondsPerKilometer: avgPace)
        let hrContext = "\(Int(avgHR)) BPM"
        let cadenceContext = "\(Int(avgCadence)) SPM"
        let zone4Context = "\(Int(zone4Sum * 100))% Zone 4"
        let cvContext = String(format: "%.3f", avgCV)
        let slopeContext = String(format: "%.3f", avgSlope)
        let stageContext = "Competitor" // Simplified for now, or could calculate from volume

        let runData = AggregateRunDataForAI(
            paceContext: paceContext,
            hrContext: hrContext,
            cadenceContext: cadenceContext,
            zone4Context: zone4Context,
            cvContext: cvContext,
            slopeContext: slopeContext,
            stageContext: stageContext
        )

        let targetTimeRange = timeRange

        Task {
            do {
                if #available(iOS 26.0, *) {
                    let insight = try await CoachingEngine.shared.generateDashboardInsight(for: targetTimeRange, runData: runData)
                    await MainActor.run {
                        switch targetTimeRange {
                        case "7 Days":
                            self.cachedHeadline7Day = insight.headline
                            self.cachedBody7Day = insight.body
                        case "30 Days":
                            self.cachedHeadline30Day = insight.headline
                            self.cachedBody30Day = insight.body
                        case "All Time":
                            self.cachedHeadlineAllTime = insight.headline
                            self.cachedBodyAllTime = insight.body
                        default: break
                        }
                        self.isFetchingInsight = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingInsight = false
                    // Silent failure logic leaves string empty, falls back to default
                }
            }
        }
    }

    private var activePrimerId: PreRunDrillId {
        if let cadence = baselineCadence, cadence < 150 {
            return .cadencePyramids
        } else if let cadence = baselineCadence, cadence < 160 {
            return .rhythmIntervals
        } else if currentHeadline().localizedCaseInsensitiveContains("fatigue") {
            return .aerobicFlush
        } else {
            return .neuromuscularPrimer
        }
    }

    @ViewBuilder
    private var proactiveCoachCard: some View {
        let primerId = activePrimerId
        let template = DrillTemplate.template(for: primerId)
        let baseCadence = baselineCadence ?? 155
        let computedTarget = template.calculateTargetCadence(baseCadence)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: primerId.iconName)
                    .foregroundColor(primerId.iconColor)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("10–15 min drill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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

            Text(template.defaultPurpose)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label(template.defaultWork, systemImage: "repeat")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Label(template.defaultRecovery, systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(template.defaultEffort, systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let cue = template.generateInstructionalCue(computedTarget)
            if !cue.isEmpty {
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

            if primerId == .aerobicFlush || primerId == .recoveryJog {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text("Target: Zone 1 HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Zone 1 Heart Rate", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }
            } else if primerId == .aerobicBaseBuilder || primerId == .zone2Run {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text("Target: Zone 2 HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Zone 2 Heart Rate", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text("Target: \(computedTarget) SPM (\(timeRange) Baseline: \(baseCadence) SPM)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Target Cadence", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }
            }

            HStack(spacing: 12) {
                Button(action: {
                    activeWorkoutPlan = PreRunDrill(id: primerId, previousCadence: baseCadence, targetCadence: computedTarget).buildWorkoutPlan()
                    pendingWatchDrillDTO = DrillPrescriptionDTO(
                        title: template.title,
                        preRunDrillId: primerId.rawValue,
                        purpose: template.defaultPurpose,
                        targetCadence: computedTarget,
                        previousCadence: baseCadence
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
                    togglePrimerCompletedToday()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPrimerCompletedToday ? "checkmark.circle.fill" : "circle")
                        Text(isPrimerCompletedToday ? "Completed ✓" : "Mark completed")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isPrimerCompletedToday ? Color.green.opacity(0.15) : Color.orange)
                    .foregroundColor(isPrimerCompletedToday ? .green : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
        .onChange(of: isShowingWorkoutPreview) { oldValue, newValue in
            if oldValue && !newValue, let dto = pendingWatchDrillDTO {
                pendingWatchDrillDTO = nil
                scheduleDashboardDrillToWatch(dto: dto)
            }
        }
    }

    private func scheduleDashboardDrillToWatch(dto: DrillPrescriptionDTO) {
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
                    print("[DashboardView] Failed to schedule drill: \(error.localizedDescription)")
                }
            }
        }
    }

    private func autoSyncStaleWatchDrillIfNeeded() {
        guard lastWatchExportTimestamp > 0 && lastBaselineChangeTimestamp > lastWatchExportTimestamp, !lastExportedDrillId.isEmpty else { return }
        guard #available(iOS 17.0, *) else { return }

        let preRunId = PreRunDrillId(rawValue: lastExportedDrillId) ?? activePrimerId
        let template = DrillTemplate.template(for: preRunId)
        let baseCadence = baselineCadence ?? 155
        let computedTarget = template.calculateTargetCadence(baseCadence)

        Task {
            let dto = DrillPrescriptionDTO(
                title: template.title,
                preRunDrillId: preRunId.rawValue,
                purpose: template.defaultPurpose,
                targetCadence: computedTarget,
                previousCadence: baseCadence
            )
            do {
                let bridge = WorkoutBridge()
                try await bridge.scheduleDrill(dto: dto)
                await MainActor.run {
                    self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                }
            } catch {}
        }
    }

    private func refreshBaselineVO2Max() {
        let now = Date()
        let boundaryDate: Date? = {
            switch timeRange {
            case "7 Days": return Calendar.current.date(byAdding: .day, value: -7, to: now)
            case "30 Days": return Calendar.current.date(byAdding: .day, value: -30, to: now)
            default: return nil
            }
        }()

        Task {
            do {
                if let targetDate = boundaryDate {
                    let historicalVO2 = try await HealthKitManager.shared.fetchVO2MaxClosestTo(date: targetDate)
                    await MainActor.run {
                        self.baselineVO2Max = historicalVO2
                    }
                } else {
                    await MainActor.run {
                        self.baselineVO2Max = nil
                    }
                }
            } catch {
                // Keep current baselineVO2Max
            }
        }
    }

    @ViewBuilder
    private var fitnessBaselineCard: some View {
        VStack(spacing: 16) {
            // Top Row: VO2 Max & AVG CADENCE
            HStack(alignment: .top) {
                // Quadrant 1: VO2 Max
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("VO2 Max")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    let vo2Val = globalVO2Max ?? 40.5
                    Text(String(format: "%.1f", vo2Val))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let base = baselineVO2Max {
                        let diff = vo2Val - base
                        if abs(diff) > 0.05 {
                            HStack(spacing: 4) {
                                Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2.bold())
                                Text(String(format: "%@%.1f", diff >= 0 ? "+" : "", diff))
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(diff >= 0 ? Color(red: 0.1, green: 0.85, blue: 0.75) : .pink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "VO2 Max", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }

                // Quadrant 2: AVG CADENCE
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("AVG CADENCE")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    let cadenceVal = baselineCadence ?? (filteredRunRecords.isEmpty ? 155 : Int(filteredRunRecords.map(\.workingAvgCadence).reduce(0, +) / Double(filteredRunRecords.count)))
                    let displayCadence = cadenceVal > 0 ? cadenceVal : 155
                    Text("\(displayCadence) SPM")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let prevCadence = previousBaselineCadence {
                        let diff = displayCadence - prevCadence
                        if diff != 0 {
                            HStack(spacing: 4) {
                                Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2.bold())
                                Text(String(format: "%@%d SPM", diff > 0 ? "+" : "", diff))
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(diff >= 0 ? Color(red: 0.1, green: 0.85, blue: 0.75) : .pink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Average Cadence", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Bottom Row: AVG PACE & WORKOUT DENSITY
            HStack(alignment: .top) {
                // Quadrant 3: AVG PACE
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .foregroundColor(.teal)
                            .font(.caption)
                        Text("AVG PACE")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    let paceVal = baselinePace ?? (filteredRunRecords.isEmpty ? 381.0 : (filteredRunRecords.map(\.workingAvgPace).reduce(0, +) / Double(filteredRunRecords.count)))
                    let displayPace = paceVal > 0 ? PaceFormatter.formatPace(secondsPerKilometer: paceVal) : "6:21/km"
                    Text(displayPace)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let prevPace = previousBaselinePace, paceVal > 0 {
                        let diffSecs = Int(round(paceVal - prevPace))
                        if diffSecs != 0 {
                            let isFaster = diffSecs < 0
                            HStack(spacing: 4) {
                                Image(systemName: isFaster ? "arrow.down.right" : "arrow.up.right")
                                    .font(.caption2.bold())
                                Text(String(format: "%@%ds", diffSecs > 0 ? "+" : "", diffSecs))
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(isFaster ? Color(red: 0.1, green: 0.85, blue: 0.75) : .pink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Average Pace", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }

                // Quadrant 4: WORKOUT DENSITY
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("WORKOUT DENSITY")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    let density = workoutDensityTier
                    Text(density)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(density == "Optimal" ? Color(red: 0.1, green: 0.85, blue: 0.75) : (density == "Moderate" ? .yellow : .orange))

                    Text("\(filteredRunRecords.count) runs in \(timeRange.lowercased())")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeExplainer = MetricExplainerInfo(
                        explainer: MetricDetailExplainer.explainer(for: "Workout Density", isWorkoutStats: false),
                        mode: "Working Stats"
                    )
                }
            }
        }
        .padding(18)
        .background(Color(red: 11/255, green: 27/255, blue: 51/255))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
        .sheet(item: $activeExplainer) { info in
            MetricExplainerSheet(info: info)
        }
    }

    @ViewBuilder
    private var filterChips: some View {
        if !availableFilters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { selectedFilter = nil }) {
                        Text("All")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == nil ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundColor(selectedFilter == nil ? .white : .primary)
                            .clipShape(Capsule())
                    }

                    ForEach(availableFilters, id: \.self) { filter in
                        Button(action: {
                            if selectedFilter == filter {
                                selectedFilter = nil
                            } else {
                                selectedFilter = filter
                            }
                        }) {
                            Text(filter)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedFilter == filter ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                                .foregroundColor(selectedFilter == filter ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    filterControlsSection

                    fitnessBaselineCard

                    aiFatigueInsightCard

                    proactiveCoachCard

                    filterChips

                    if filteredRunRecords.isEmpty {
                        if isSyncing && runRecords.isEmpty {
                            AnimatedLoadingView(text: "Analyzing your running history...")
                                .padding(.top, 100)
                        } else {
                            ContentUnavailableView(
                                "No Runs Found",
                                systemImage: "figure.run.circle",
                                description: Text("Go for a run with your Apple Watch and it will appear here.")
                            )
                            .padding(.top, 60)
                        }
                    } else {
                        if !filteredRunRecords.isEmpty {
                            Section(header: Text(selectedFilter == nil ? "Past Runs" : "Filtered Runs")
                                                .font(.title3.bold())
                                                .padding(.horizontal)
                                                .frame(maxWidth: .infinity, alignment: .leading)) {
                                ForEach(filteredRunRecords) { run in
                                    NavigationLink(value: run) {
                                        RunListRowView(runRecord: run)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }
            .navigationDestination(for: RunRecord.self) { runRecord in
                RunDetailView(runRecord: runRecord)
            }
            .task {
                do {
                    try await HealthKitManager.shared.requestAuthorization()
                    if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 1), !vo2s.isEmpty {
                        globalVO2Max = vo2s[0]
                    }
                    refreshBaselineVO2Max()
                } catch {
                    print("Error requesting HealthKit authorization on dashboard: \(error.localizedDescription)")
                }

                if let onSync {
                    await onSync(false)
                    isSyncing = false
                }
            }
            .refreshable {
                if let onSync {
                    isSyncing = true
                    let task = Task {
                        await onSync(false)
                    }
                    _ = await task.result
                    isSyncing = false
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: DrillsLibraryView()) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .font(.headline)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Dashboard")
                            .font(.headline)
                        Spacer()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        #if DEBUG
                        Button(action: {
                            Task {
                                await HealthKitSeeder.shared.seedCouchTo5K(context: modelContext)
                            }
                        }) {
                            Image(systemName: "ladybug.fill")
                                .foregroundColor(.red)
                        }
                        #endif

                        NavigationLink(destination: SettingsView(onForceSync: onSync)) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
        }
    }
}

struct HeroCardView: View {
    var runRecord: RunRecord
    var isSyncing: Bool
    var allRuns: [RunRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: runRecord.duration) ?? ""
    }

    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return allRuns.filter { $0.date < runRecord.date && $0.date >= thirtyDaysAgo }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Proactive Coaching")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(runRecord.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }

            let columns = verticalSizeClass == .regular
                ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                let distanceConverted = useMetricSystem ? (runRecord.totalDistanceMeters / 1000.0) : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                MetricView(title: "Distance", value: String(format: "%.2f %@", distanceConverted, distanceUnit))
                MetricView(title: "Pace", value: PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace), currentValue: runRecord.workingAvgPace, baselineValue: baselinePace, polarity: .lowerIsBetter)
                MetricView(title: "Time", value: formattedDuration)
                MetricView(title: "HR", value: "\(Int(runRecord.workingAvgHeartRate)) BPM", currentValue: runRecord.workingAvgHeartRate, baselineValue: baselineHR, polarity: .lowerIsBetter)
                MetricView(title: "Cadence", value: "\(Int(runRecord.workingAvgCadence)) SPM", currentValue: runRecord.workingAvgCadence, baselineValue: baselineCadence, polarity: .higherIsBetter)
                MetricView(title: "CV (Var)", value: String(format: "%.3f", runRecord.paceCV))
            }

            Divider()

            if let insight = runRecord.insight {
                if !insight.headline.isEmpty {
                    Text(insight.headline)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .foregroundColor(.primary)
                }

                if !insight.longitudinalObservation.isEmpty {
                    Text(insight.longitudinalObservation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                if let firstDrill = insight.drillRecommendations?.first {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.purple)

                        Text("Scheduled: \(firstDrill.drillTitle)")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }

                aiDisclaimerFooter
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    AnimatedLoadingView(
                        text: "Analyzing your run...",
                        isHorizontal: true,
                        imageSize: 24,
                        textFont: .title2.bold(),
                        textColor: .primary,
                        iconColor: .primary,
                        spacing: 12
                    )
                }
                .frame(minHeight: 1)
                .task(id: runRecord.id) {
                    if !isSyncing && runRecord.insight == nil {
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
        .frame(minHeight: 1)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(runRecord.insight.map { "Latest Insight. \($0.headline)." } ?? "Analyzing your run...")
    }

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        AIDisclaimerFooter()
    }
}

enum MetricPolarity {
    case higherIsBetter
    case lowerIsBetter
}

struct MetricView: View {
    let title: String
    let value: String
    var currentValue: Double?
    var baselineValue: Double?
    var polarity: MetricPolarity?

    @State private var showingInfo = false

    var body: some View {
        let explainer = MetricDetailExplainer.explainer(for: title, isWorkoutStats: false)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            HStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let current = currentValue, let baseline = baselineValue, let polarity = polarity {
                    let diff = current - baseline
                    if abs(diff) > 0.01 {
                        let isPositiveTrend = diff > 0
                        let isGood = (polarity == .higherIsBetter) ? isPositiveTrend : !isPositiveTrend

                        Image(systemName: isPositiveTrend ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(isGood ? .green : .red)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            MetricExplainerSheet(explainer: explainer, mode: "Working Stats")
        }
    }
}

struct RunListRowView: View {
    var runRecord: RunRecord

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(runRecord.date, style: .date)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text(runRecord.detectedTypeRaw)
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.1, green: 0.7, blue: 0.7).opacity(0.18))
                    .foregroundColor(Color(red: 0.05, green: 0.55, blue: 0.55))
                    .clipShape(Capsule())
            }

            HStack {
                let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
                let distanceConverted = useMetricSystem ? (runRecord.totalDistanceMeters / 1000.0) : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"
                let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)

                Text(String(format: "%.2f %@ • %@", distanceConverted, distanceUnit, pace))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}
