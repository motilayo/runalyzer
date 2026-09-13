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
        averagePace: Double,
        averageHeartRate: Double,
        percentZone4: Double,
        averageCadence: Double,
        verticalOscillation: Double = 9.5,
        runnerStage: Int = 1,
        cv: Double = 0.05,
        slope: Double = 0.0,
        durationMinutes: Double = 30.0
    ) async -> String {
        // High pace variability (CV > 0.12) indicates an Interval / Fartlek workout,
        // not a steady-state continuous Tempo run.
        if cv > 0.15 {
            return "Intervals"
        }
        if cv > 0.10 && percentZone4 < 0.25 {
            return "Fartlek"
        }

        if let classifier = self.runClassifier {
            do {
                let input = RunalystClassifierInput(
                    averagePace: averagePace,
                    averageHeartRate: averageHeartRate,
                    percentZone4: percentZone4,
                    averageCadence: averageCadence,
                    verticalOscillation: verticalOscillation,
                    runnerStage: Int64(runnerStage)
                )
                let prediction = try await classifier.prediction(input: input)
                return prediction.targetClass
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }

        let framboise = FramboiseEngine()
        return await framboise.classifyRun(cv: cv, slope: slope, zone4: percentZone4, durationMinutes: durationMinutes, averageHR: averageHeartRate)
    }

}

extension RunalystClassifier: @unchecked Sendable {}
extension RunalystClassifierOutput: @unchecked Sendable {}
