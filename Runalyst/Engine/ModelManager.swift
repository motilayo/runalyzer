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
        if let classifier = self.runClassifier {
            do {
                let input = RunalystClassifierInput(
                    averagePace: averagePace,
                    averageHeartRate: averageHeartRate,
                    percentZone4: percentZone4,
                    averageCadence: averageCadence,
                    verticalOscillation: verticalOscillation,
                    runnerStage: Double(runnerStage)
                )
                let prediction = try await classifier.prediction(input: input)
                return prediction.targetClass
            } catch {
                print("CoreML prediction failed: \(error).")
            }
        }

        return "Steady Effort"
    }

}

extension RunalystClassifier: @unchecked Sendable {}
extension RunalystClassifierOutput: @unchecked Sendable {}
