import sys

file_path = "Runalyzer/CoachingEngine/CoachingEngine.swift"

with open(file_path, "r") as f:
    contents = f.read()


old_top = """@available(iOS 26.0, *)
@Generable

struct RunDataForAI: Sendable {
    let date: Date
    let distance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
    let formattedPace: String
    let baseline: BaselineStats?
}

struct CoachingInsightPayload {"""


new_top = """struct RunDataForAI: Sendable {
    let date: Date
    let distance: Double
    let avgPace: Double
    let avgHeartRate: Int
    let avgCadence: Int
    let formattedPace: String
    let baseline: BaselineStats?
}

@available(iOS 26.0, *)
@Generable
struct CoachingInsightPayload {"""

contents = contents.replace(old_top, new_top)


old_return = """            let drillRecommendation = DrillRecommendation(
                drillTitle: generatedInsight.content.drillTitle,
                drillReps: generatedInsight.content.drillReps,
                drillRecovery: generatedInsight.content.drillRecovery,
                drillCues: generatedInsight.content.drillCues,
                targetCadence: generatedInsight.content.targetCadence,
                previousCadence: runData.avgCadence,
                isCompleted: false
            )

            // Map the generated struct to our SwiftData model
            return CoachingInsight(
                headline: generatedInsight.content.headline,
                longitudinalObservation: generatedInsight.content.longitudinalObservation,
                drillRecommendation: drillRecommendation
            )"""

new_return = """            return generatedInsight.content"""

contents = contents.replace(old_return, new_return)

with open(file_path, "w") as f:
    f.write(contents)

print("Fixed CoachingEngine.swift")
