import SwiftUI
import Charts
import SwiftData

enum ProgressionMetric: String, CaseIterable, Identifiable {
    case efficiencyFactor = "Efficiency Factor"
    case pace = "Average Pace"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .efficiencyFactor: return "Eff. Factor (Speed÷HR)"
        case .pace: return "Average Pace"
        }
    }
}

enum ChartTimeHorizon: String, CaseIterable, Identifiable {
    case thirtyDays = "30 Days"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .thirtyDays: return 30
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }
}

struct ChartRunPoint: Identifiable {
    let id: UUID
    let date: Date
    let runType: String
    let pace: Double
    let efficiencyFactor: Double
    let smoothedValue: Double
}

struct ProgressionChartView: View {
    var allRuns: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var selectedMetric: ProgressionMetric = .efficiencyFactor
    @State private var selectedHorizon: ChartTimeHorizon = .thirtyDays
    @State private var selectedRunTypes: Set<String> = []
    @State private var selectedDate: Date?

    private var horizonRuns: [RunRecord] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -selectedHorizon.days, to: Date()) else {
            return allRuns
        }
        return allRuns.filter { $0.date >= cutoff && $0.workingAvgPace > 0 }
    }

    /// Sorted unique run classifications by frequency in the selected horizon
    private var availableRunTypesSorted: [String] {
        var counts: [String: Int] = [:]
        for run in horizonRuns {
            let type = run.normalizedClassification
            counts[type, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Color mapping for canonical run classifications
    private func colorForRunType(_ type: String) -> Color {
        switch type {
        case "Easy Run": return Color.teal
        case "Steady Effort": return Color(red: 0.15, green: 0.55, blue: 0.95)
        case "Tempo Run": return Color.orange
        case "Intervals": return Color.purple
        case "Long Run": return Color.indigo
        case "Progression Run": return Color.green
        case "Recovery Run": return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "Hill Repeats": return Color.red
        case "Fartlek": return Color.pink
        default: return Color.yellow
        }
    }

    /// Generates structured chart data points per selected run type with 3-point moving average smoothing
    private var chartPointsByRunType: [String: [ChartRunPoint]] {
        var result: [String: [ChartRunPoint]] = [:]

        for type in selectedRunTypes {
            let runsOfType = horizonRuns
                .filter { $0.normalizedClassification == type }
                .sorted { $0.date < $1.date }

            guard !runsOfType.isEmpty else { continue }

            var points: [ChartRunPoint] = []
            for (index, run) in runsOfType.enumerated() {
                let pace = run.workingAvgPace
                let speedMetersPerMin = (pace > 0) ? (60_000.0 / pace) : 0
                let hr = run.workingAvgHeartRate
                let ef = (hr > 0 && speedMetersPerMin > 0) ? (speedMetersPerMin / hr) : 1.0

                // 3-point smoothed moving average for trajectory
                let startIdx = max(0, index - 1)
                let endIdx = min(runsOfType.count - 1, index + 1)
                let windowRuns = runsOfType[startIdx...endIdx]

                let smoothedValue: Double
                if selectedMetric == .efficiencyFactor {
                    let sum = windowRuns.compactMap { r -> Double? in
                        guard r.workingAvgHeartRate > 0, r.workingAvgPace > 0 else { return nil }
                        return (60_000.0 / r.workingAvgPace) / r.workingAvgHeartRate
                    }.reduce(0, +)
                    let count = windowRuns.filter { $0.workingAvgHeartRate > 0 && $0.workingAvgPace > 0 }.count
                    smoothedValue = count > 0 ? (sum / Double(count)) : ef
                } else {
                    let sum = windowRuns.map(\.workingAvgPace).reduce(0, +)
                    smoothedValue = sum / Double(windowRuns.count)
                }

                points.append(ChartRunPoint(
                    id: run.id,
                    date: run.date,
                    runType: type,
                    pace: pace,
                    efficiencyFactor: ef,
                    smoothedValue: smoothedValue
                ))
            }
            result[type] = points
        }
        return result
    }

    /// Closest run to selected scrubber date
    private var highlightedPoint: ChartRunPoint? {
        guard let selDate = selectedDate else { return nil }
        let allPoints = chartPointsByRunType.values.flatMap { $0 }
        return allPoints.min(by: { abs($0.date.timeIntervalSince(selDate)) < abs($1.date.timeIntervalSince(selDate)) })
    }

    private func syncDefaultSelectedRunTypes() {
        let types = availableRunTypesSorted
        guard !types.isEmpty else {
            selectedRunTypes = []
            return
        }

        // Retain any existing selections that are still present
        let currentValid = selectedRunTypes.intersection(Set(types))
        if currentValid.isEmpty {
            // Default strictly to the two most common run types
            selectedRunTypes = Set(types.prefix(2))
        } else {
            selectedRunTypes = currentValid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title & Metric Toggle
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.orange)
                            .font(.headline)
                        Text("Longitudinal Progression")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(ProgressionMetric.allCases) { metric in
                            Text(metric.shortTitle).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }

                // Time Horizon Picker
                Picker("Time Horizon", selection: $selectedHorizon) {
                    ForEach(ChartTimeHorizon.allCases) { horizon in
                        Text(horizon.rawValue).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedHorizon) {
                    syncDefaultSelectedRunTypes()
                }
            }

            // Interactive Legend Chips
            if !availableRunTypesSorted.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableRunTypesSorted, id: \.self) { type in
                            let isSelected = selectedRunTypes.contains(type)
                            let typeColor = colorForRunType(type)

                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    if isSelected {
                                        if selectedRunTypes.count > 1 {
                                            selectedRunTypes.remove(type)
                                        }
                                    } else {
                                        selectedRunTypes.insert(type)
                                    }
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(typeColor)
                                        .frame(width: 8, height: 8)
                                    Text(type)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? typeColor.opacity(0.18) : Color(UIColor.tertiarySystemFill))
                                .foregroundColor(isSelected ? typeColor : .secondary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? typeColor : Color.clear, lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Highlighted Scrubber Tooltip
            if let point = highlightedPoint {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.runType)
                            .font(.caption.bold())
                            .foregroundColor(colorForRunType(point.runType))
                        Text(point.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if selectedMetric == .efficiencyFactor {
                            Text(String(format: "%.2f m/beat", point.efficiencyFactor))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Efficiency Factor")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text(PaceFormatter.formatPace(secondsPerKilometer: point.pace))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Average Pace")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
                .transition(.opacity)
            }

            // Apple Chart
            if chartPointsByRunType.isEmpty || chartPointsByRunType.values.allSatisfy(\.isEmpty) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No runs recorded for the selected time horizon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart {
                    ForEach(Array(chartPointsByRunType.keys), id: \.self) { type in
                        if let points = chartPointsByRunType[type] {
                            let color = colorForRunType(type)

                            // Raw scattered runs
                            ForEach(points) { point in
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value(
                                        selectedMetric.rawValue,
                                        selectedMetric == .efficiencyFactor ? point.efficiencyFactor : point.pace
                                    )
                                )
                                .foregroundStyle(color.opacity(0.40))
                                .symbolSize(32)
                            }

                            // Smoothed trajectory trendline
                            if points.count >= 2 {
                                ForEach(points) { point in
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value(
                                            selectedMetric.rawValue,
                                            point.smoothedValue
                                        )
                                    )
                                    .foregroundStyle(color)
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                    .interpolationMethod(.monotone)
                                }
                            }
                        }
                    }

                    // Scrubber line
                    if let sel = highlightedPoint {
                        RuleMark(x: .value("Selected", sel.date))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if selectedMetric == .efficiencyFactor {
                                if let val = value.as(Double.self) {
                                    Text(String(format: "%.2f", val))
                                        .font(.caption2)
                                }
                            } else {
                                if let paceSecs = value.as(Double.self) {
                                    let minutes = Int(paceSecs) / 60
                                    let seconds = Int(paceSecs) % 60
                                    Text(String(format: "%d:%02d", minutes, seconds))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 230)
                .animation(.easeInOut(duration: 0.3), value: selectedMetric)
                .animation(.easeInOut(duration: 0.3), value: selectedRunTypes)
            }

            // Descriptive Subtitle / Metric Context
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if selectedMetric == .efficiencyFactor {
                    Text("Efficiency Factor (Speed ÷ Heart Rate) shows true physiological economy regardless of terrain or weather.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Overlaying trendlines across workout types reveals true progression without single-session noise.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
        .onAppear {
            syncDefaultSelectedRunTypes()
        }
    }
}
