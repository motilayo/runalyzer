import Foundation
import SwiftData
import FoundationModels

@available(iOS 26.0, *)
@ModelActor
actor MacroQueryEngine {

    // Calculates the rolling averages over the specified number of days back from a target date.
    func calculateRollingAverages(days: Int, minimumDistance: Double = 0, to targetDate: Date = Date()) async throws -> BaselineStats? {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: targetDate) else {
            return nil
        }

        // Subtracted 0.01 to avoid precision issues like 1000.0 >= 999.999
        let minDistanceFloat = minimumDistance - 0.01

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.distance >= minDistanceFloat && $0.date >= startDate && $0.date <= targetDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let runs = try modelContext.fetch(descriptor)

        // Ensure sequential mapping on the actor to adhere to Swift 6 strict concurrency
        var dtos: [RunMetricsDTO] = []
        for run in runs {
            dtos.append(RunMetricsDTO(
                date: run.date,
                distance: run.distance,
                avgPace: run.avgPace,
                avgHeartRate: run.avgHeartRate,
                avgCadence: run.avgCadence
            ))
        }

        guard !dtos.isEmpty else { return nil }

        return try await calculateAverages(from: dtos)
    }

    // Abstracting calculation to allow for dependency injection/testing with Sendable DTOs
    // Pass the Sendable DTOs into a background TaskGroup to calculate averages
    func calculateAverages(from dtos: [RunMetricsDTO]) async throws -> BaselineStats? {
        guard !dtos.isEmpty else { return nil }

        return try await withThrowingTaskGroup(of: BaselineStats?.self) { group in
            group.addTask {
                let avgDistance = dtos.map(\.distance).reduce(0, +) / Double(dtos.count)
                let avgPace = dtos.map(\.avgPace).reduce(0, +) / Double(dtos.count)
                let avgHR = dtos.map(\.avgHeartRate).reduce(0, +) / dtos.count
                let avgCadence = dtos.map(\.avgCadence).reduce(0, +) / dtos.count

                return BaselineStats(
                    avgDistance: avgDistance,
                    avgPace: avgPace,
                    avgHeartRate: avgHR,
                    avgCadence: avgCadence,
                    avgVerticalOscillation: 0.0, // Unused for these macros currently
                    avgVo2Max: 0.0,              // Unused
                    avgGroundContactTime: 0.0,   // Unused
                    avgStrideLength: 0.0         // Unused
                )
            }

            return try await group.next() ?? nil
        }
    }

    func generateWeeklyFatigueInsight(minimumDistance: Double = 0, for targetDate: Date = Date(), modelProvider: (any LanguageModelProvider)? = nil) async throws -> FatigueInsight? {
        let provider = await MainActor.run {
            return modelProvider ?? DefaultLanguageModelProvider()
        }

        let isAvailable = await MainActor.run {
            return provider.isAvailable
        }

        guard isAvailable else {
            return nil
        }

        // 1. Calculate 7-day and 30-day macros
        guard let sevenDayAvg = try await calculateRollingAverages(days: 7, minimumDistance: minimumDistance, to: targetDate),
              let thirtyDayAvg = try await calculateRollingAverages(days: 30, minimumDistance: minimumDistance, to: targetDate) else {
            return nil
        }

        // 2. Prepare context
        let cadenceDelta = sevenDayAvg.avgCadence - thirtyDayAvg.avgCadence
        let hrDelta = sevenDayAvg.avgHeartRate - thirtyDayAvg.avgHeartRate

        let instructions = """
        persona: elite_running_coach
        task: synthesize_weekly_fatigue_management_insight
        rules:
        - speak directly to user using second person ("You", "Your")
        - STRICT ZERO NUMBERS RULE: forbid all numbers, digits, percentages, measurements, and unit names in the headline and observation.
        - CRITICAL: You are strictly forbidden from using any numbers, digits, percentages, or exact measurements in your response. Translate all data deltas into purely qualitative biomechanical observations.
        - focus strictly on comparing the 7-day trends against their 30-day baseline to evaluate fatigue and form breakdown.
        - respond entirely in \(Locale.current.language.languageCode?.identifier ?? "en")
        """

        let promptTemplate = """
        You are a running coach evaluating a runner's recent week against their monthly baseline.

        [MACRO_DATA_START]
        7_DAY_AVG_CADENCE: \(sevenDayAvg.avgCadence) SPM
        30_DAY_AVG_CADENCE: \(thirtyDayAvg.avgCadence) SPM
        CADENCE_DELTA: \(cadenceDelta) (If negative, form is breaking down)

        7_DAY_AVG_HR: \(sevenDayAvg.avgHeartRate) BPM
        30_DAY_AVG_HR: \(thirtyDayAvg.avgHeartRate) BPM
        HR_DELTA: \(hrDelta) (If positive, they are experiencing cardiovascular strain/fatigue)
        [MACRO_DATA_END]

        Generate a FatigueInsight evaluating their recovery status.
        """

        // 3. Generate Insight
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: instructions
            )

            // Note: We use the injected provider here for testing purposes, but fallback to session in real use if needed.
            // For architecture consistency, we'll try to use the session directly as shown in FoundationModels examples.

            let generatedInsight = try await session.respond(to: promptTemplate, generating: FatigueInsight.self)

            return generatedInsight.content
        } catch {
            print("Failed to generate fatigue insight: \(error)")
            return nil
        }
    }
}
