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
    
    /// Predicts the run type based on mathematical features.
    /// Uses CoreML model if available, falling back to rule-based FramboiseEngine.
    func predictRunType(cv: Double, slope: Double, zone4: Double, durationMinutes: Double) async -> String {
        if let classifier = self.runClassifier {
            do {
                let prediction = try classifier.prediction(paceCV: cv, paceSlope: slope, percentZone4: zone4, durationMinutes: durationMinutes)
                return prediction.runClassification
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }
        
        let framboise = FramboiseEngine()
        return await framboise.classifyRun(cv: cv, slope: slope, zone4: zone4, durationMinutes: durationMinutes)
    }
    
}
