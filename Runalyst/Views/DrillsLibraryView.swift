import SwiftUI
import SwiftData
import WorkoutKit

struct DrillsLibraryView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @State private var selectedCategory: String = "All"

    @AppStorage("dashboardTimeRange") private var dashboardTimeRange: String = "30 Days"
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("lastBaselineChangeTimestamp") private var lastBaselineChangeTimestamp: Double = 0
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""

    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .strides).buildWorkoutPlan()
    @State private var pendingWatchDrillDTO: DrillPrescriptionDTO?
    @State private var isShowingWorkoutPreview: Bool = false
    @State private var isAutoSyncing: Bool = false
    @State private var autoSyncSuccess: Bool = false

    let categories = ["All", "Foundation", "Threshold", "Speed"]

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        var filtered = runRecords.filter { $0.totalDistanceMeters >= (minDistanceInMeters - 0.01) }
        let now = Date()
        if dashboardTimeRange == "7 Days", let limit = Calendar.current.date(byAdding: .day, value: -7, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        } else if dashboardTimeRange == "30 Days", let limit = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        }
        return filtered
    }

    private var baselineCadence: Int {
        let recentRuns = filteredRunRecords.filter { $0.workingAvgCadence > 0 }
        guard !recentRuns.isEmpty else { return 160 }
        return Int(recentRuns.map(\.workingAvgCadence).reduce(0, +)) / recentRuns.count
    }

    private var isExportStale: Bool {
        lastWatchExportTimestamp > 0 && lastBaselineChangeTimestamp > lastWatchExportTimestamp
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isAutoSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(red: 0.05, green: 0.45, blue: 0.5))
                        Text("Auto-updating Watch targets for your new \(baselineCadence) SPM baseline...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else if autoSyncSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Watch targets auto-updated for your new \(baselineCadence) SPM baseline ✓")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else if isExportStale {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Baseline Updated (\(baselineCadence) SPM)")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                            Text("Update Watch targets to match your new baseline.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Sync Now") {
                            Task {
                                await autoSyncStaleExportIfNeeded()
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Category Picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)

                // Section 1: Foundation & Recovery Primers
                if selectedCategory == "All" || selectedCategory == "Foundation" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Foundation & Recovery Primers (10-15 Min)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        DrillPrimerCardView(
                            drillId: .aerobicFlush,
                            customTitle: "Recovery Run Prep (Shakeout)",
                            customTarget: "Target HR: 100 - 118 BPM",
                            baselineCadence: baselineCadence,
                            onStart: handleStartDrill
                        )
                        .padding(.horizontal)

                        DrillPrimerCardView(
                            drillId: .zone2Run,
                            customTitle: "Zone 2 Run",
                            customTarget: "Target: Zone 2 HR",
                            baselineCadence: baselineCadence,
                            onStart: handleStartDrill
                        )
                        .padding(.horizontal)
                    }
                }

                // Section 2: Speed & Efficiency Primers
                if selectedCategory == "All" || selectedCategory == "Speed" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speed & Efficiency Primers (10-15 Min)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        DrillPrimerCardView(
                            drillId: .cadencePyramids,
                            baselineCadence: baselineCadence,
                            onStart: handleStartDrill
                        )
                        .padding(.horizontal)

                        DrillPrimerCardView(
                            drillId: .strides,
                            baselineCadence: baselineCadence,
                            onStart: handleStartDrill
                        )
                        .padding(.horizontal)
                    }
                }

                // Section 3: Threshold & Form Primers
                if selectedCategory == "All" || selectedCategory == "Threshold" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Threshold & Form Primers (10-15 Min)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        DrillPrimerCardView(
                            drillId: .rhythmIntervals,
                            baselineCadence: baselineCadence,
                            onStart: handleStartDrill
                        )
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
        .onChange(of: isShowingWorkoutPreview) { oldValue, newValue in
            if oldValue && !newValue, let dto = pendingWatchDrillDTO {
                pendingWatchDrillDTO = nil
                scheduleDrillToWatch(dto: dto)
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("🏃 Pre-Run Library")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isExportStale {
                await autoSyncStaleExportIfNeeded()
            }
        }
        .onChange(of: baselineCadence) {
            if lastWatchExportTimestamp > 0 {
                Task {
                    await autoSyncStaleExportIfNeeded()
                }
            }
        }
    }

    private func handleStartDrill(plan: WorkoutPlan, dto: DrillPrescriptionDTO) {
        activeWorkoutPlan = plan
        pendingWatchDrillDTO = dto
        isShowingWorkoutPreview = true
    }

    private func scheduleDrillToWatch(dto: DrillPrescriptionDTO) {
        Task {
            if #available(iOS 17.0, *) {
                do {
                    let bridge = WorkoutBridge()
                    try await bridge.scheduleDrill(dto: dto)
                    await MainActor.run {
                        self.lastExportedDrillId = dto.preRunDrillId ?? ""
                        self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } catch {
                    print("[DrillsLibraryView] Error scheduling drill: \(error.localizedDescription)")
                }
            }
        }
    }

    private func autoSyncStaleExportIfNeeded() async {
        guard !lastExportedDrillId.isEmpty || lastWatchExportTimestamp > 0 else { return }
        guard #available(iOS 17.0, *) else { return }

        await MainActor.run {
            self.isAutoSyncing = true
        }

        let drillIdToSync = !lastExportedDrillId.isEmpty ? lastExportedDrillId : "cadence_pyramids"
        let preRunId = PreRunDrillId(rawValue: drillIdToSync) ?? .strides
        let template = DrillTemplate.template(for: preRunId)
        let newTarget = template.calculateTargetCadence(baselineCadence)

        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: preRunId.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: newTarget,
            previousCadence: baselineCadence
        )

        do {
            let bridge = WorkoutBridge()
            try await bridge.scheduleDrill(dto: dto)
            await MainActor.run {
                self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                self.isAutoSyncing = false
                self.autoSyncSuccess = true
            }
        } catch {
            await MainActor.run {
                self.isAutoSyncing = false
            }
        }
    }
}

struct DrillPrimerCardView: View {
    let drillId: PreRunDrillId
    var customTitle: String?
    var customPurpose: String?
    var customTarget: String?
    let baselineCadence: Int
    var onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)?

    @State private var selectedDuration: DrillDuration = .fifteenMinutes
    @AppStorage("drillHapticFeedbackMode") private var selectedHapticModeRaw: String = HapticFeedbackMode.on.rawValue
    @State private var showingTargetExplainer = false

    private var selectedHapticMode: HapticFeedbackMode {
        get { HapticFeedbackMode(rawValue: selectedHapticModeRaw) ?? .on }
        nonmutating set { selectedHapticModeRaw = newValue.rawValue }
    }

    var body: some View {
        let template = DrillTemplate.template(for: drillId)
        let displayTitle = customTitle ?? template.title
        let purpose = customPurpose ?? template.defaultPurpose
        let work = template.workString(for: selectedDuration)
        let recovery = template.recoveryString(for: selectedDuration)
        let effort = template.defaultEffort
        let targetCadence: Int? = template.calculateTargetCadence(baselineCadence)
        let cue = template.generateInstructionalCue(targetCadence ?? baselineCadence)
        let icon = drillId.iconName
        let iconColor = drillId.iconColor

        let hasCadenceTarget = drillId != .aerobicFlush && drillId != .recoveryJog && drillId != .aerobicBaseBuilder && drillId != .zone2Run
        let isZone2 = drillId == .aerobicBaseBuilder || drillId == .zone2Run

        let displayTargetText: String? = {
            if let customTarget = customTarget { return customTarget }
            if isZone2 {
                return "Target: Zone 2 HR"
            }
            if hasCadenceTarget {
                return targetCadence.map { "Target: \($0) SPM (Baseline: \(baselineCadence) SPM)" }
            }
            return nil
        }()

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(selectedDuration.rawValue) min drill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Purpose
            if !purpose.isEmpty {
                Text(purpose)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Repeat / Rest / Effort Badges
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

            // Cue
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

            // Target
            if let targetText = displayTargetText, !targetText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text(targetText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if hasCadenceTarget || isZone2 {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasCadenceTarget || isZone2 {
                        showingTargetExplainer = true
                    }
                }
                .sheet(isPresented: $showingTargetExplainer) {
                    let explainerTitle = isZone2 ? "Zone 2 Heart Rate" : "Target Cadence"
                    let explainer = MetricDetailExplainer.explainer(for: explainerTitle, isWorkoutStats: false)
                    MetricExplainerSheet(explainer: explainer, mode: "Working Stats")
                }
            }

            // Duration Selector
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Duration")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(DrillDuration.allCases, id: \.self) { dur in
                            Text(dur.title).tag(dur)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }

            // Haptic Feedback (on cadence/rhythm drills)
            if hasCadenceTarget {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.teal)
                            Text("Haptic Feedback")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("Haptic Feedback", selection: Binding(
                            get: { selectedHapticMode },
                            set: { selectedHapticMode = $0 }
                        )) {
                            ForEach(HapticFeedbackMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 130)
                    }
                }
            }

            // Single Action Button: Start Drill
            Button(action: {
                startDrill(title: displayTitle, purpose: purpose, targetCadence: targetCadence)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                    Text("Start Drill")
                        .foregroundColor(.white)
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .cornerRadius(12)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func startDrill(title: String, purpose: String, targetCadence: Int?) {
        let drill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadence,
            duration: selectedDuration,
            hapticMode: selectedHapticMode
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: title,
            preRunDrillId: drillId.rawValue,
            purpose: purpose,
            targetCadence: targetCadence,
            previousCadence: baselineCadence,
            durationMinutes: selectedDuration.rawValue,
            hapticMode: selectedHapticMode.rawValue
        )
        onStart?(plan, dto)
    }
}
