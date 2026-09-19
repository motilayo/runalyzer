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
        rawAverageHR: Double? = nil
    ) async -> String {
        let framboise = FramboiseEngine()
        let weightedClass = await framboise.classifyRun(
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
                // 1. Cadence Stability Gate (Continuous vs. Intermittent):
                // If cadenceCV is locked in (< 0.025), the run is continuous with no interval alternation.
                // It CANNOT be Fartlek or Intervals.
                if (targetClass == "Fartlek" || targetClass == "Intervals") && cadenceCV < 0.025 {
                    targetClass = weightedClass
                }

                // 2. Intermittent Gate:
                // If cadenceCV and pace CV are both high, the workout has intermittent work/rest intervals.
                if (targetClass == "Steady Effort" || targetClass == "Easy Run" || targetClass == "Recovery Run" || targetClass == "Tempo Run") && cadenceCV >= 0.038 && cv >= 0.12 {
                    targetClass = "Intervals"
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
