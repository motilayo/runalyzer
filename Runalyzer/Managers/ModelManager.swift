import Foundation
import CoreML
import SwiftData

/// Represents the extracted mathematical features for run classification.
public struct RunFeatures: Sendable {
    public let averagePace: Double       // sec/km
    public let paceCV: Double            // σ / μ
    public let paceSlope: Double         // regression slope
    public let percentZone4: Double      // 0.0 - 1.0
    public let durationMinutes: Double   // minutes

    public init(
        averagePace: Double,
        paceCV: Double,
        paceSlope: Double,
        percentZone4: Double,
        durationMinutes: Double
    ) {
        self.averagePace = averagePace
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.durationMinutes = durationMinutes
    }

    /// Converts the features into an MLMultiArray of shape [5] with Float32 values.
    public func toMultiArray() throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [5], dataType: .float32)
        array[0] = NSNumber(value: Float(averagePace))
        array[1] = NSNumber(value: Float(paceCV))
        array[2] = NSNumber(value: Float(paceSlope))
        array[3] = NSNumber(value: Float(percentZone4))
        array[4] = NSNumber(value: Float(durationMinutes))
        return array
    }
}

/// Feature provider wrapper for CoreML inference.
final class RunFeaturesProvider: MLFeatureProvider {
    let features: RunFeatures

    init(features: RunFeatures) {
        self.features = features
    }

    var featureNames: Set<String> {
        ["features", "averagePace", "paceCV", "paceSlope", "percentZone4", "durationMinutes"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "features":
            guard let multiArray = try? features.toMultiArray() else { return nil }
            return MLFeatureValue(multiArray: multiArray)
        case "averagePace":
            return MLFeatureValue(double: features.averagePace)
        case "paceCV":
            return MLFeatureValue(double: features.paceCV)
        case "paceSlope":
            return MLFeatureValue(double: features.paceSlope)
        case "percentZone4":
            return MLFeatureValue(double: features.percentZone4)
        case "durationMinutes":
            return MLFeatureValue(double: features.durationMinutes)
        default:
            return nil
        }
    }
}

/// Feature provider wrapper for CoreML on-device training batches.
final class TrainingFeatureProvider: MLFeatureProvider {
    let multiArray: MLMultiArray
    let label: String

    init(multiArray: MLMultiArray, label: String) {
        self.multiArray = multiArray
        self.label = label
    }

    var featureNames: Set<String> {
        ["features", "label", "detectedType"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "features" {
            return MLFeatureValue(multiArray: multiArray)
        } else if featureName == "label" || featureName == "detectedType" {
            return MLFeatureValue(string: label)
        }
        return nil
    }
}

/// Singleton manager responsible for on-device CoreML model provisioning, inference, and personalization updates.
@MainActor
public final class ModelManager {
    public static let shared = ModelManager()

    private let modelName = "PersonalizedRunClassifier"
    private var cachedModel: MLModel?
    private var isUpdating = false

    public var writableModelURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelDir = documents.appendingPathComponent("RunClassifier", isDirectory: true)
        return modelDir.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
    }

    private init() {
        provisionModelIfNeeded()
    }

    /// Step 1: Model File Provisioning
    /// Copies the precompiled .mlmodelc from Bundle.main to the user's writable Documents directory if not already present.
    public func provisionModelIfNeeded() {
        let fileManager = FileManager.default
        let targetURL = writableModelURL
        let targetDir = targetURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: targetDir.path) {
            try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        }

        if !fileManager.fileExists(atPath: targetURL.path) {
            // Find bundled .mlmodelc
            if let bundleURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    try fileManager.copyItem(at: bundleURL, to: targetURL)
                    print("Successfully copied \(modelName).mlmodelc to writable directory: \(targetURL.path)")
                } catch {
                    print("Failed to copy bundled model: \(error)")
                }
            } else {
                print("Warning: Bundled \(modelName).mlmodelc not found in Bundle.main.")
            }
        }
    }

    /// Step 2: Inference
    /// Evaluates the mathematical features against the writable model and returns the predicted run type string.
    public func classify(features: RunFeatures) -> String {
        provisionModelIfNeeded()

        do {
            let model = try loadModel()
            let provider = RunFeaturesProvider(features: features)
            let prediction = try model.prediction(from: provider)

            var result: String? = nil
            if let labelValue = prediction.featureValue(for: "label")?.stringValue {
                result = labelValue
            } else if let detectedValue = prediction.featureValue(for: "detectedType")?.stringValue {
                result = detectedValue
            } else if let classLabelValue = prediction.featureValue(for: "classLabel")?.stringValue {
                result = classLabelValue
            }

            if let result = result {
                let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized != "urbantraffic" && normalized != "urban traffic" && normalized != "unknown" && !normalized.isEmpty {
                    return result
                }
            }
        } catch {
            print("CoreML Inference Error: \(error.localizedDescription)")
        }

        // Deterministic fallback if inference encounters an issue
        return fallbackClassification(features: features)
    }

    /// Loads the active MLModel instance from the writable directory
    private func loadModel() throws -> MLModel {
        if let cached = cachedModel {
            return cached
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: writableModelURL, configuration: config)
        self.cachedModel = model
        return model
    }

    /// Step 3: Personalization Loop (The 3-5 Batch Rule)
    /// Checks for queued TrainingCorrection objects. If count >= 5, kicks off MLUpdateTask.
    public func processTrainingCorrections(in modelContext: ModelContext) {
        guard !isUpdating else { return }

        let descriptor = FetchDescriptor<TrainingCorrection>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        guard let allCorrections = try? modelContext.fetch(descriptor), allCorrections.count >= 5 else {
            return
        }

        let batchToProcess = Array(allCorrections.prefix(5))
        let correctionIDs = batchToProcess.map(\.persistentModelID)

        var featureProviders: [MLFeatureProvider] = []
        for item in batchToProcess {
            let feat = RunFeatures(
                averagePace: item.averagePace,
                paceCV: item.paceCV,
                paceSlope: item.paceSlope,
                percentZone4: item.percentZone4,
                durationMinutes: item.durationMinutes
            )
            if let multiArray = try? feat.toMultiArray() {
                featureProviders.append(TrainingFeatureProvider(multiArray: multiArray, label: item.correctedLabel))
            }
        }

        guard featureProviders.count >= 5 else { return }
        let batchProvider = MLArrayBatchProvider(array: featureProviders)

        isUpdating = true
        let targetURL = writableModelURL
        let container = modelContext.container

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly

            let updateTask = try MLUpdateTask(
                forModelAt: targetURL,
                trainingData: batchProvider,
                configuration: config,
                completionHandler: { context in
                    let isCompleted = context.task.state == .completed
                    if isCompleted {
                        do {
                            // Overwrite the writable .mlmodelc
                            try context.model.write(to: targetURL)
                            print("CoreML Personalization: Model successfully updated and written to \(targetURL.path)")
                        } catch {
                            print("Failed to save updated model: \(error)")
                        }
                    } else {
                        print("CoreML Personalization failed with state: \(context.task.state), error: \(String(describing: context.task.error))")
                    }

                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        defer { self.isUpdating = false }
                        if isCompleted {
                            self.cachedModel = nil // Invalidate cached model to reload updated weights
                            let ctx = container.mainContext
                            for id in correctionIDs {
                                if let model = ctx.model(for: id) as? TrainingCorrection {
                                    ctx.delete(model)
                                }
                            }
                            try? ctx.save()
                        }
                    }
                }
            )

            updateTask.resume()
        } catch {
            print("Failed to initialize MLUpdateTask: \(error)")
            self.isUpdating = false
        }
    }

    /// Deterministic mathematical classification fallback
    private func fallbackClassification(features: RunFeatures) -> String {
        if features.paceCV > 0.12 {
            return "intervals"
        }
        if features.percentZone4 >= 0.35 {
            return "tempo"
        }
        return "steady"
    }
}
