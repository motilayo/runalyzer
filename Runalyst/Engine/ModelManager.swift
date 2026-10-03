import Foundation
import CoreML

/// A manager for interfacing with the CoreML RunalystClassifier.
actor ModelManager {

    // CoreML integration
    private var runClassifier: RunalystClassifier?

    init() {
        do {
            let config = MLModelConfiguration()
            self.runClassifier = try RunalystClassifier(configuration: config)
        } catch {
            print("Failed to load RunalystClassifier: \(error)")
        }
    }

    /// Predicts the run type using the CoreML model.
    func predictRunType(
        buckets: [BucketData],
        paceDelta: Double,
        hrDelta: Double,
        percentZone4: Double,
        cadenceDelta: Double,
        verticalOscillation: Double = 9.5,
        runnerStage: Int = 1,
        cv: Double = 0.05,
        slope: Double = 0.0,
        durationMinutes: Double = 30.0,
        cadenceCV: Double = 0.0,
        rawAverageHR: Double? = nil
    ) async -> String {
        let framboise = FramboiseEngine()
        let cycles = await framboise.extractOscillationCycles(buckets: buckets)
        let weightedClass = await framboise.classifyRun(
            buckets: buckets,
            cv: cv,
            slope: slope,
            zone4: percentZone4,
            durationMinutes: durationMinutes,
            cadenceCV: cadenceCV,
            averageHR: rawAverageHR,
            paceDelta: paceDelta,
            hrDelta: hrDelta,
            cycles: cycles
        )

        if let classifier = self.runClassifier {
            do {
                let input = RunalystClassifierInput(
                    paceDelta: paceDelta,
                    hrDelta: hrDelta,
                    percentZone4: percentZone4,
                    cadenceDelta: cadenceDelta,
                    verticalOscillation: verticalOscillation,
                    cv: cv,
                    paceSlope: slope,
                    runnerStage: Double(runnerStage),
                    durationMinutes: durationMinutes,
                    cadenceCV: cadenceCV
                )
                let prediction = try await classifier.prediction(input: input)
                var targetClass = prediction.targetClass

                // Topological Structural Guardrail:
                // 1. Continuous Run Gate:
                // If < 3 corroborated oscillation cycles, the run is continuous.
                // CoreML CANNOT classify it as Fartlek, Intervals, or Pyramids.
                if (targetClass == "Fartlek" || targetClass == "Intervals" || targetClass == "Pyramids") && cycles.count < 3 {
                    targetClass = weightedClass
                }

                // 2. Intermittent Gate:
                // If >= 3 corroborated cycles, delegate to weightedClass which accurately separates Pyramids, Intervals, and Fartlek.
                if targetClass != "Intervals" && targetClass != "Fartlek" && targetClass != "Pyramids" && cycles.count >= 3 {
                    targetClass = weightedClass
                }

                // 3. Environmental & Topographic Override:
                // If deterministic telemetry validates Urban Traffic or Hill Repeats, override scalar tabular CoreML.
                if weightedClass == "Urban Traffic" || weightedClass == "Hill Repeats" {
                    targetClass = weightedClass
                }

                return targetClass
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }

        return weightedClass
    }

}

extension RunalystClassifier: @unchecked Sendable {}
extension RunalystClassifierOutput: @unchecked Sendable {}
