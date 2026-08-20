import sys

file_path = "Runalyzer/CoachingEngine/CoachingEngine.swift"

with open(file_path, "r") as f:
    contents = f.read()

contents = contents.replace("import FoundationModels", """import FoundationModels
import SwiftData""")


data_struct = """
struct RunDataForAI: Sendable {
    let date: Date
    let distance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
    let formattedPace: String
    let baseline: BaselineStats?
}
"""
contents = contents.replace("struct CoachingInsightPayload {", data_struct + "\nstruct CoachingInsightPayload {")

contents = contents.replace("func generateInsight(for runRecord: RunRecord, history: [RunRecord]) async throws -> CoachingInsight", "func generateInsight(for runData: RunDataForAI) async throws -> CoachingInsightPayload")

contents = contents.replace("let paceFormatted = runRecord.formattedPace", "let paceFormatted = runData.formattedPace")
contents = contents.replace("let distanceConverted = useMetricSystem ? (runRecord.distance / 1000.0) : (runRecord.distance / 1609.344)", "let distanceConverted = useMetricSystem ? (runData.distance / 1000.0) : (runData.distance / 1609.344)")
contents = contents.replace("let dateFormatted = dateFormatter.string(from: runRecord.date)", "let dateFormatted = dateFormatter.string(from: runData.date)")
contents = contents.replace("if let baseline = history.thirtyDayBaseline(from: runRecord.date) {", "if let baseline = runData.baseline {")

# the line with pace delta
contents = contents.replace("(useMetricSystem ? runRecord.avgPace : runRecord.avgPace * 1.609344)", "(useMetricSystem ? runData.avgPace : runData.avgPace * 1.609344)")

contents = contents.replace("runRecord.avgHeartRate", "runData.avgHeartRate")
contents = contents.replace("runRecord.avgCadence", "runData.avgCadence")

# the return part inside do block
old_return = """            let drillRecommendation = DrillRecommendation(
                drillTitle: generatedInsight.content.drillTitle,
                drillReps: generatedInsight.content.drillReps,
                drillRecovery: generatedInsight.content.drillRecovery,
                drillCues: generatedInsight.content.drillCues,
                targetCadence: generatedInsight.content.targetCadence,
                previousCadence: runRecord.avgCadence,
                isCompleted: false
            )

            // Map the generated struct to our SwiftData model
            return CoachingInsight(
                headline: generatedInsight.content.headline,
                longitudinalObservation: generatedInsight.content.longitudinalObservation,
                drillRecommendation: drillRecommendation
            )"""

contents = contents.replace(old_return, "            return generatedInsight.content")

# the return part inside catch block
old_catch = """            // Graceful fallback for unsupported languages/locales or generation failures
            let fallbackDrill = DrillRecommendation(
                drillTitle: "Strides",
                drillReps: "4 × 20s",
                drillRecovery: "60s easy walk",
                drillCues: "Focus on relaxed shoulders and quick turnover.",
                targetCadence: nil,
                previousCadence: runData.avgCadence,
                isCompleted: false
            )

            return CoachingInsight(
                headline: "Run Analyzed Successfully",
                longitudinalObservation: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days.",
                drillRecommendation: fallbackDrill
            )"""

new_catch = """            // Graceful fallback for unsupported languages/locales or generation failures
            return CoachingInsightPayload(
                headline: "Run Analyzed Successfully",
                longitudinalObservation: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days.",
                drillTitle: "Strides",
                drillReps: "4 × 20s",
                drillRecovery: "60s easy walk",
                drillCues: "Focus on relaxed shoulders and quick turnover.",
                targetCadence: nil
            )"""

contents = contents.replace(old_catch, new_catch)

with open(file_path, "w") as f:
    f.write(contents)

print("Updated CoachingEngine.swift")
