import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A structured response definition representing weekly fatigue insights.
/// The `@Generable` macro allows `LanguageModelSession` to automatically map LLM text to this struct.
@available(iOS 26.0, *)
#if canImport(FoundationModels)
@Generable
#endif
struct FatigueInsight: Codable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Constrain strictly to a 3-5 word title. Forbid full sentences, punctuation-heavy titles, numbers, percentages, measurements, and digits.")
    #endif
    var headline: String

    #if canImport(FoundationModels)
    @Guide(description: "Describe the specific qualitative biomechanical trend over the period. Strictly enforce the 'Zero Numbers' rule. Forbid all numbers, digits, percentages, measurements, and unit names. Write exactly one or two sentences.")
    #endif
    var observation: String

    #if canImport(FoundationModels)
    @Guide(description: "A short, actionable recommendation or adjustment to apply to upcoming drills based on the observation. E.g. 'Prioritize zone 2 recovery for the next 48 hours'.")
    #endif
    var recommendation: String
}
