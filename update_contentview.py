import sys

file_path = "Runalyzer/ContentView.swift"

with open(file_path, "r") as f:
    contents = f.read()

old_code = """                // Generate AI insight locally for EACH run so baseline context is strictly temporal
                if #available(iOS 26.0, *) {
                    let runId = newRun.persistentModelID
                    let container = modelContext.container

                    // Await the detached task to ensure sequential processing
                    await Task.detached {
                        let backgroundContext = ModelContext(container)
                        if let backgroundRun = backgroundContext.model(for: runId) as? RunRecord {
                            do {
                                let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                                let history = (try? backgroundContext.fetch(descriptor)) ?? []
                                let insight = try await CoachingEngine.shared.generateInsight(for: backgroundRun, history: history)
                                backgroundRun.insight = insight
                                try backgroundContext.save()
                            } catch {
                                print("Failed to generate AI insight for run \(backgroundRun.id): \(error)")
                            }
                        }
                    }.value

                    // Delay between generations to avoid overloading the model
                    runCount += 1
                    if runCount % 5 == 0 {
                        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds longer pause
                    } else {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds default pause
                    }
                } else {
                    print("AI insights require iOS 26.0+")
                }"""

new_code = """                // Generate AI insight locally for EACH run so baseline context is strictly temporal
                if #available(iOS 26.0, *) {
                    let baseline = RunRecord.thirtyDayBaseline(from: newRun.date, in: modelContext)
                    let runData = RunDataForAI(
                        date: newRun.date,
                        distance: newRun.distance,
                        avgPace: newRun.avgPace,
                        avgHeartRate: newRun.avgHeartRate,
                        avgCadence: newRun.avgCadence,
                        formattedPace: newRun.formattedPace,
                        baseline: baseline
                    )
                    let runId = newRun.persistentModelID
                    let container = modelContext.container
                    let previousCadence = newRun.avgCadence

                    do {
                        let payload = try await CoachingEngine.shared.generateInsight(for: runData)

                        await MainActor.run {
                            let mainContext = container.mainContext
                            if let mainRun = mainContext.model(for: runId) as? RunRecord {
                                let drill = DrillRecommendation(
                                    drillTitle: payload.drillTitle,
                                    drillReps: payload.drillReps,
                                    drillRecovery: payload.drillRecovery,
                                    drillCues: payload.drillCues,
                                    targetCadence: payload.targetCadence,
                                    previousCadence: previousCadence,
                                    isCompleted: false
                                )
                                let insight = CoachingInsight(
                                    headline: payload.headline,
                                    longitudinalObservation: payload.longitudinalObservation,
                                    drillRecommendation: drill
                                )
                                mainRun.insight = insight
                                try? mainContext.save()
                            }
                        }
                    } catch {
                        print("Failed to generate AI insight for run \\(newRun.id): \\(error)")
                    }

                    // Delay between generations to avoid overloading the model
                    runCount += 1
                    if runCount % 5 == 0 {
                        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds longer pause
                    } else {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds default pause
                    }
                } else {
                    print("AI insights require iOS 26.0+")
                }"""

contents = contents.replace(old_code, new_code)

with open(file_path, "w") as f:
    f.write(contents)

print("Updated ContentView.swift")
