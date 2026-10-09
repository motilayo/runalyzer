import Foundation

/// Represents a segmented time window in a run (work interval, recovery interval, steady cruising, or walking break).
struct PhaseSegment: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(startSeconds)-\(endSeconds)-\(kind)" }
    let startSeconds: Double
    let endSeconds: Double
    let kind: String // "work", "recovery", "steady", "walking"
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }
}

/// Represents the persisted mathematical signature and structural classification of a run.
/// Computed strictly once at ingestion to power the interactive RAG Analyst chat and Variance Map without battery drain.
struct RunSignature: Codable, Sendable, Equatable {
    let classification: String
    let confidence: Double
    let probabilities: [String: Double]
    let anomalies: [String]
    let cadenceFloor: Double
    let phaseSegments: [PhaseSegment]
    let dataSource: String // "wrist", "gymkit", "footpod"
    let isIndoor: Bool
    let needsInclineReview: Bool

    /// Formats this signature into a token-efficient compact key-value block for FoundationModels prompts.
    var compactRAGSummary: String {
        var lines: [String] = []
        lines.append("Workout Type: \(classification)")
        lines.append("Classification Confidence: \(Int(confidence * 100))%")
        lines.append("Sensor Source: \(dataSource.capitalized)")
        lines.append("Environment: \(isIndoor ? "Indoor Treadmill" : "Outdoor Road/Trail")")
        lines.append("Cadence Floor: \(Int(cadenceFloor)) SPM")
        if !anomalies.isEmpty {
            lines.append("Telemetry Highlights: \(anomalies.joined(separator: ", "))")
        }
        if needsInclineReview {
            lines.append("Incline Note: Potential Incline Intervals Detected")
        }
        let workSegments = phaseSegments.filter { $0.kind == "work" }
        let recoverySegments = phaseSegments.filter { $0.kind == "recovery" }
        if !workSegments.isEmpty {
            lines.append("Interval Structure: \(workSegments.count) work reps, \(recoverySegments.count) recovery reps")
        }
        return lines.joined(separator: "\n")
    }
}
