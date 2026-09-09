import SwiftUI
import SwiftData
import WorkoutKit

struct DrillsLibraryView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @State private var selectedCategory: String = "All"
    
    @State private var activeWorkoutPlan: WorkoutPlan = PreRunDrill(id: .strides).buildWorkoutPlan()
    @State private var isShowingWorkoutPreview: Bool = false
    
    let categories = ["All", "Foundation", "Threshold", "Speed"]
    
    private var baselineCadence: Int {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return 160 }
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.workingAvgCadence > 0 }
        guard !recentRuns.isEmpty else { return 160 }
        return Int(recentRuns.map(\.workingAvgCadence).reduce(0, +) / Double(recentRuns.count))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Category Picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Section 1: Foundation & Recovery Primers
                if selectedCategory == "All" || selectedCategory == "Foundation" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Foundation & Recovery Primers (10-15 Min)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        DrillPrimerCardView(
                            icon: "chart.line.downtrend.xyaxis",
                            iconColor: .blue,
                            title: "Recovery Run Prep (Shakeout)",
                            description: "10 min low-impact flush. strictly Zone 1.",
                            target: "Target HR: 100 - 118 BPM",
                            drillId: "aerobic_flush",
                            targetCadence: nil,
                            baselineCadence: baselineCadence,
                            onStart: { plan in
                                activeWorkoutPlan = plan
                                isShowingWorkoutPreview = true
                            }
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
                        
                        let targetCadence = min(185, baselineCadence + 8)
                        DrillPrimerCardView(
                            icon: "stopwatch",
                            iconColor: .orange,
                            title: "Cadence Correction Drill",
                            description: "12 min turnover focus to fix over-striding.",
                            target: "Target: \(targetCadence) SPM (Current Baseline: \(baselineCadence) SPM)",
                            drillId: "cadence_pyramids",
                            targetCadence: targetCadence,
                            baselineCadence: baselineCadence,
                            onStart: { plan in
                                activeWorkoutPlan = plan
                                isShowingWorkoutPreview = true
                            }
                        )
                        .padding(.horizontal)
                        
                        DrillPrimerCardView(
                            icon: "bolt.fill",
                            iconColor: .yellow,
                            title: "Neuromuscular Strides",
                            description: "10 min pre-race explosive activation.",
                            target: "Target: 175 - 185 SPM",
                            drillId: "strides",
                            targetCadence: 180,
                            baselineCadence: baselineCadence,
                            onStart: { plan in
                                activeWorkoutPlan = plan
                                isShowingWorkoutPreview = true
                            }
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
                            icon: "waveform.path.ecg",
                            iconColor: .purple,
                            title: "Rhythm Intervals (Tempo Primer)",
                            description: "12 min progressive cadence ramp.",
                            target: "Target: 168 - 174 SPM",
                            drillId: "rhythm_intervals",
                            targetCadence: 170,
                            baselineCadence: baselineCadence,
                            onStart: { plan in
                                activeWorkoutPlan = plan
                                isShowingWorkoutPreview = true
                            }
                        )
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .workoutPreview(activeWorkoutPlan, isPresented: $isShowingWorkoutPreview)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("🏃 Pre-Run Library")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DrillPrimerCardView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let target: String
    let drillId: String
    let targetCadence: Int?
    let baselineCadence: Int
    var onStart: ((WorkoutPlan) -> Void)? = nil
    
    @State private var isScheduling = false
    @State private var scheduledSuccess = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(target)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Button(action: {
                    startDrill()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                        Text("Start")
                            .foregroundColor(.white)
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    scheduleToWatch()
                }) {
                    HStack(spacing: 6) {
                        if isScheduling {
                            ProgressView()
                                .tint(.white)
                        } else if scheduledSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Loaded")
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "applewatch")
                                .foregroundColor(.white)
                            Text("Load to Watch")
                                .foregroundColor(.white)
                        }
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        scheduledSuccess ? Color.blue : Color(red: 0.05, green: 0.45, blue: 0.5)
                    )
                    .cornerRadius(12)
                }
                .disabled(isScheduling || scheduledSuccess)
            }
            
            if let err = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    private func startDrill() {
        let preRunId = PreRunDrillId(rawValue: drillId) ?? .strides
        let drill = PreRunDrill(id: preRunId, previousCadence: baselineCadence, targetCadence: targetCadence)
        let plan = drill.buildWorkoutPlan()
        onStart?(plan)
    }
    
    private func scheduleToWatch() {
        isScheduling = true
        errorMessage = nil
        
        Task {
            if #available(iOS 17.0, *) {
                let dto = DrillPrescriptionDTO(
                    title: title,
                    preRunDrillId: drillId,
                    purpose: description,
                    targetCadence: targetCadence,
                    previousCadence: baselineCadence
                )
                
                do {
                    let bridge = WorkoutBridge()
                    try await bridge.scheduleDrill(dto: dto)
                    await MainActor.run {
                        self.isScheduling = false
                        self.scheduledSuccess = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } catch {
                    await MainActor.run {
                        self.isScheduling = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            } else {
                await MainActor.run {
                    self.isScheduling = false
                    self.errorMessage = "WorkoutKit requires iOS 17.0 or newer."
                }
            }
        }
    }
}
