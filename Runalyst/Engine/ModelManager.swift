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
        rawAverageHR: Double? = nil,
        buckets: [BucketData] = []
    ) async -> String {
        let framboise = FramboiseEngine()
        let weightedClass = await framboise.classifyRun(
            buckets: buckets,
            cv: cv,
            slope: slope,
            zone4: percentZone4,
            durationMinutes: durationMinutes,
            cadenceCV: cadenceCV,
            averageHR: rawAverageHR,
            paceDelta: paceDelta,
            hrDelta: hrDelta
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

                // Physiological Structural Gate:
                if !buckets.isEmpty {
                    let cycles = await framboise.extractOscillationCycles(buckets: buckets)
                    // 1. Continuous Run Gate:
                    // If < 3 corroborated oscillation cycles, the run is continuous.
                    // CoreML CANNOT classify it as Fartlek or Intervals.
                    if (targetClass == "Fartlek" || targetClass == "Intervals") && cycles.count < 3 {
                        targetClass = weightedClass
                    }

                    // 2. Intermittent Gate:
                    // If >= 3 corroborated cycles and high regularity, override continuous predictions with Intervals.
                    if (targetClass == "Steady Effort" || targetClass == "Easy Run" || targetClass == "Recovery Run" || targetClass == "Tempo Run") && cycles.count >= 3 {
                        let regularity = await framboise.calculateCycleRegularity(cycles: cycles)
                        if regularity >= 0.65 {
                            targetClass = "Intervals"
                        }
                    }
                } else {
                    // Legacy scalar fallback when bucket time series is unavailable
                    if (targetClass == "Fartlek" || targetClass == "Intervals") && cadenceCV < 0.025 {
                        targetClass = weightedClass
                    }

                    if (targetClass == "Steady Effort" || targetClass == "Easy Run" || targetClass == "Recovery Run" || targetClass == "Tempo Run") && cadenceCV >= 0.038 && cv >= 0.12 {
                        targetClass = "Intervals"
                    }
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
