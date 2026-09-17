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
                return prediction.targetClass
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }

        let framboise = FramboiseEngine()
        return await framboise.classifyRun(cv: cv, slope: slope, zone4: percentZone4, durationMinutes: durationMinutes, cadenceCV: cadenceCV, averageHR: rawAverageHR)
    }

}

extension RunalystClassifier: @unchecked Sendable {}
extension RunalystClassifierOutput: @unchecked Sendable {}
