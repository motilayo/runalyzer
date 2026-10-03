import Foundation
@testable import Runalyst

/// A telemetry-accurate representation of an authentic HealthKit workout recording.
/// Designed to eliminate synthetic "metronomic" assumptions and validate the real-world
/// behavior of classification and coaching algorithms.
struct WorkoutTelemetryFixture: Codable, Sendable {
    let id: String
    let name: String
    let expectedClassification: String
    let physiologicalNotes: String
    let durationMinutes: Double
    let samples: [BucketTelemetrySample]

    /// Converts the telemetry samples into engine-ready `BucketData` structures.
    func toBucketData(startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [BucketData] {
        var current = startDate
        return samples.map { sample in
            let bucket = BucketData(
                startTime: current,
                distanceMeters: sample.distanceMeters,
                durationSeconds: sample.durationSeconds,
                meanPaceSecPerKm: sample.meanPaceSecPerKm,
                meanCadence: sample.meanCadence,
                meanHR: sample.meanHR,
                meanVerticalOscillation: sample.meanVerticalOscillation,
                meanStrideLength: sample.meanStrideLength,
                elevationGainMeters: sample.elevationGainMeters
            )
            current = current.addingTimeInterval(sample.durationSeconds)
            return bucket
        }
    }

    /// Serializes the fixture to pretty-printed JSON data.
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Deserializes a fixture from JSON data.
    static func fromJSONData(_ data: Data) throws -> WorkoutTelemetryFixture {
        let decoder = JSONDecoder()
        return try decoder.decode(WorkoutTelemetryFixture.self, from: data)
    }
}

/// A single discrete telemetry window (e.g. 15s or 30s bucket) extracted from an authentic recording.
struct BucketTelemetrySample: Codable, Sendable {
    let durationSeconds: Double
    let distanceMeters: Double
    let meanPaceSecPerKm: Double
    let meanCadence: Double
    let meanHR: Double
    let meanVerticalOscillation: Double
    let meanStrideLength: Double
    let elevationGainMeters: Double

    init(
        durationSeconds: Double = 30.0,
        distanceMeters: Double,
        meanPaceSecPerKm: Double,
        meanCadence: Double,
        meanHR: Double,
        meanVerticalOscillation: Double = 0.0,
        meanStrideLength: Double = 0.0,
        elevationGainMeters: Double = 0.0
    ) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.meanPaceSecPerKm = meanPaceSecPerKm
        self.meanCadence = meanCadence
        self.meanHR = meanHR
        self.meanVerticalOscillation = meanVerticalOscillation
        self.meanStrideLength = meanStrideLength
        self.elevationGainMeters = elevationGainMeters
    }

    /// Convenience factory computing distance directly from duration and pace in sec/km.
    static func make(
        durationSeconds: Double = 30.0,
        paceSecPerKm: Double,
        cadence: Double,
        hr: Double,
        verticalOscillation: Double = 0.0,
        strideLength: Double = 0.0,
        elevationGainMeters: Double = 0.0
    ) -> BucketTelemetrySample {
        let distance = paceSecPerKm > 0 ? (durationSeconds / paceSecPerKm) * 1000.0 : 0.0
        return BucketTelemetrySample(
            durationSeconds: durationSeconds,
            distanceMeters: distance,
            meanPaceSecPerKm: paceSecPerKm,
            meanCadence: cadence,
            meanHR: hr,
            meanVerticalOscillation: verticalOscillation,
            meanStrideLength: strideLength,
            elevationGainMeters: elevationGainMeters
        )
    }
}
