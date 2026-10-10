import Foundation

/// Represents the athlete's longitudinal macro profile (ACWR, acute/chronic load, 30-day baseline stats).
/// Calculated strictly once per data sync and persisted locally to provide instant RAG context for AI chat.
struct MacroProfile: Codable, Sendable, Equatable {
    let acwr: Double?
    let acuteLoad: Double
    let chronicWeeklyLoad: Double
    let baselinePace: Double?
    let baselineHR: Double?
    let baselineCadence: Double?
    let baselineEfficiencyFactor: Double?
    let updatedAt: Date

    static let storageKey = "runalyst_persisted_macro_profile"

    /// Loads the cached macro profile from local storage.
    static func load() -> MacroProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MacroProfile.self, from: data)
    }

    /// Persists this macro profile to local storage.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Formats the macro profile into a token-efficient compact key-value block for FoundationModels prompts.
    var compactRAGSummary: String {
        var lines: [String] = []
        if let acwr = acwr {
            lines.append("Workload Ratio (ACWR): \(String(format: "%.2f", acwr))")
        } else {
            lines.append("Workload Ratio (ACWR): Baseline calibrating (< 21 days)")
        }
        lines.append("7-Day Training Load: \(Int(acuteLoad))")
        lines.append("28-Day Baseline Weekly Load: \(Int(chronicWeeklyLoad))")
        if let pace = baselinePace {
            lines.append("30-Day Baseline Pace: \(Int(pace)) sec/km")
        }
        if let hr = baselineHR {
            lines.append("30-Day Baseline Heart Rate: \(Int(hr)) BPM")
        }
        if let cad = baselineCadence {
            lines.append("30-Day Baseline Cadence: \(Int(cad)) SPM")
        }
        if let ef = baselineEfficiencyFactor {
            lines.append("Aerobic Efficiency Factor: \(String(format: "%.2f", ef))")
        }
        return lines.joined(separator: "\n")
    }
}
