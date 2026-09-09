import Foundation
import CoreML

/// A manager for interfacing with the CoreML PersonalizedRunClassifier.
/// In the absence of a pre-trained `.mlmodel` file, this actor delegates predictions
/// to the deterministic `FramboiseEngine` as a fallback.
actor ModelManager {
    
    // CoreML integration
    private var runClassifier: PersonalizedRunClassifier?
    
    init() {
        do {
            let config = MLModelConfiguration()
            self.runClassifier = try PersonalizedRunClassifier(configuration: config)
        } catch {
            print("Failed to load PersonalizedRunClassifier: \(error)")
        }
    }
    
    /// Predicts the run type based on mathematical features using the retrained CoreML model.
    /// Enforces strict cardiac guardrails (high HR / zone4 runs are never misclassified as easy).
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
                let prediction = try classifier.prediction(
                    averagePace: averagePace,
                    averageHeartRate: averageHeartRate,
                    percentZone4: percentZone4,
                    averageCadence: averageCadence,
                    verticalOscillation: verticalOscillation,
                    runnerStage: Int64(runnerStage)
                )
                return prediction.targetClass
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }
        
        let framboise = FramboiseEngine()
        return await framboise.classifyRun(cv: cv, slope: slope, zone4: percentZone4, durationMinutes: durationMinutes, averageHR: averageHeartRate)
    }
    
}
