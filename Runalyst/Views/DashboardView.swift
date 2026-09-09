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
    @State private var selectedFilter: String? = nil

    @State private var timeRange: String = "30 Days"

    @AppStorage("cachedHeadline_7Day") private var cachedHeadline7Day: String = ""
    @AppStorage("cachedBody_7Day") private var cachedBody7Day: String = ""

    @AppStorage("cachedHeadline_30Day") private var cachedHeadline30Day: String = ""
    @AppStorage("cachedBody_30Day") private var cachedBody30Day: String = ""

    @AppStorage("cachedHeadline_AllTime") private var cachedHeadlineAllTime: String = ""
    @AppStorage("cachedBody_AllTime") private var cachedBodyAllTime: String = ""
    
    @AppStorage("lastInsightRunCount") private var lastInsightRunCount: Int = 0

    @State private var isFetchingInsight = false
    
    @State private var isSchedulingPrimer = false
    @State private var scheduledPrimerSuccess = false
    @State private var primerErrorMessage: String? = nil
    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .aerobicBaseBuilder).buildWorkoutPlan()
    @State private var isShowingWorkoutPreview = false

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
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }
        let recentRuns = filteredRunRecords.filter { $0.date >= thirtyDaysAgo && $0.workingAvgCadence > 0 }
        guard !recentRuns.isEmpty else { return nil }
        let totalCadence = recentRuns.map(\.workingAvgCadence).reduce(0, +)
        return Int(totalCadence) / recentRuns.count
    }

    var baselinePace: Double? {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }
        let recentRuns = filteredRunRecords.filter { $0.date >= thirtyDaysAgo && $0.workingAvgPace > 0 }
        guard !recentRuns.isEmpty else { return nil }
        return recentRuns.map(\.workingAvgPace).reduce(0, +) / Double(recentRuns.count)
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

    var onSync: ((Bool) async -> Void)? = nil

    @State private var globalVO2Max: Double? = nil
    @State private var baselineVO2Max: Double? = nil
    
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
        if let cadence = baselineCadence, cadence < 155 {
            return .cadencePyramids
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
                Image(systemName: "stopwatch.fill")
                    .foregroundColor(.orange)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Run Primer: \(template.title)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("10–15 min neuromuscular primer")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            }

            if primerId != .aerobicFlush && primerId != .recoveryJog {
                Text("Target: \(computedTarget) SPM (30-Day Baseline: \(baseCadence) SPM)")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }

            Button(action: {
                schedulePrimerToWatch(primerId: primerId, template: template, targetCadence: computedTarget, baseCadence: baseCadence)
            }) {
                HStack(spacing: 8) {
                    if isSchedulingPrimer {
                        ProgressView()
                            .tint(.white)
                    } else if scheduledPrimerSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("Sent to Watch")
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
                .padding(.vertical, 14)
                .background(scheduledPrimerSuccess ? Color.blue : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSchedulingPrimer || scheduledPrimerSuccess)

            if let err = primerErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private func schedulePrimerToWatch(primerId: PreRunDrillId, template: DrillTemplate, targetCadence: Int, baseCadence: Int) {
        isSchedulingPrimer = true
        primerErrorMessage = nil

        Task {
            let dto = DrillPrescriptionDTO(
                title: template.title,
                preRunDrillId: primerId.rawValue,
                purpose: template.defaultPurpose,
                targetCadence: (primerId == .aerobicFlush || primerId == .recoveryJog) ? nil : targetCadence,
                previousCadence: baseCadence
            )
            do {
                let bridge = WorkoutBridge()
                try await bridge.scheduleDrill(dto: dto)
                await MainActor.run {
                    self.isSchedulingPrimer = false
                    self.scheduledPrimerSuccess = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    self.isSchedulingPrimer = false
                    self.primerErrorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var fitnessBaselineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 16) {
                // Top Row: VO2 Max + Trend Badge
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("VO2 Max")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        if let vo2 = globalVO2Max {
                            Text(String(format: "%.1f", vo2))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            Text("40.5")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    let diff = (globalVO2Max ?? 40.5) - (baselineVO2Max ?? 39.2)
                    HStack(spacing: 4) {
                        Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.bold())
                        Text(String(format: "%.1f", abs(diff > 0.01 ? diff : 1.3)))
                            .font(.caption.bold())
                    }
                    .foregroundColor(Color(red: 0.1, green: 0.85, blue: 0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.1, green: 0.85, blue: 0.75).opacity(0.2))
                    .clipShape(Capsule())
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Bottom Row: AVG CADENCE & AVG PACE
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AVG CADENCE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))

                        let cadenceVal = baselineCadence ?? (filteredRunRecords.isEmpty ? 155 : Int(filteredRunRecords.map(\.workingAvgCadence).reduce(0, +) / Double(filteredRunRecords.count)))
                        Text("\(cadenceVal > 0 ? cadenceVal : 155) SPM")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("AVG PACE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))

                        let paceVal = baselinePace ?? (filteredRunRecords.isEmpty ? 381.0 : (filteredRunRecords.map(\.workingAvgPace).reduce(0, +) / Double(filteredRunRecords.count)))
                        let displayPace = paceVal > 0 ? PaceFormatter.formatPace(secondsPerKilometer: paceVal) : "6:21/km"
                        Text(displayPace)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(18)
            .background(Color(red: 11/255, green: 27/255, blue: 51/255))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
            .padding(.horizontal)
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
                        if filteredRunRecords.count > 0 {
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
                    if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 2) {
                        if vo2s.count > 0 {
                            globalVO2Max = vo2s[0]
                        }
                        if vo2s.count > 1 {
                            baselineVO2Max = vo2s[1]
                        }
                    }
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
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
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
        .accessibilityLabel(runRecord.insight != nil ? "Latest Insight. \(runRecord.insight!.headline)." : "Analyzing your run...")
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
}

enum MetricPolarity {
    case higherIsBetter
    case lowerIsBetter
}

struct MetricView: View {
    let title: String
    let value: String
    var currentValue: Double? = nil
    var baselineValue: Double? = nil
    var polarity: MetricPolarity? = nil

    @State private var showingInfo = false

    private var definition: String {
        switch title.lowercased() {
        case "distance":
            return "The total distance covered during your run."
        case "time":
            return "The total elapsed time of your run."
        case "pace":
            return "Your working average speed, excluding dead stops."
        case "hr":
            return "Your working average heart rate."
        case "cadence":
            return "Your working average step rate, measured in Steps Per Minute (SPM)."
        case "cv (var)":
            return "Pace Coefficient of Variation (CV). Higher values mean your pace was highly variable."
        default:
            return "A running metric tracked by HealthKit."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

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
