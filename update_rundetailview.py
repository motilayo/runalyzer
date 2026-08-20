import sys

file_path = "Runalyzer/Views/RunDetailView.swift"

with open(file_path, "r") as f:
    contents = f.read()

old_code = """                    .task {
                        if #available(iOS 26.0, *) {
                            if runRecord.insight == nil {
                                let runId = runRecord.persistentModelID
                                let container = modelContext.container

                                Task.detached {
                                    let backgroundContext = ModelContext(container)
                                    if let backgroundRun = backgroundContext.model(for: runId) as? RunRecord {
                                        do {
                                            let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                                            let history = (try? backgroundContext.fetch(descriptor)) ?? []

                                            let insight = try await CoachingEngine.shared.generateInsight(for: backgroundRun, history: history)
                                            backgroundRun.insight = insight
                                            try backgroundContext.save()
                                        } catch {
                                            print("Failed to generate AI insight for run \\(backgroundRun.id): \\(error)")
                                        }
                                    }
                                }
                            }
                        }
                    }"""

new_code = """                    .task {
                        if #available(iOS 26.0, *) {
                            if runRecord.insight == nil {
                                let baseline = RunRecord.thirtyDayBaseline(from: runRecord.date, in: modelContext)
                                let runData = RunDataForAI(
                                    date: runRecord.date,
                                    distance: runRecord.distance,
                                    avgPace: runRecord.avgPace,
                                    avgHeartRate: runRecord.avgHeartRate,
                                    avgCadence: runRecord.avgCadence,
                                    formattedPace: runRecord.formattedPace,
                                    baseline: baseline
                                )
                                let runId = runRecord.persistentModelID
                                let container = modelContext.container
                                let previousCadence = runRecord.avgCadence

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
                                    print("Failed to generate AI insight for run \\(runData.date): \\(error)")
                                }
                            }
                        }
                    }"""

contents = contents.replace(old_code, new_code)

with open(file_path, "w") as f:
    f.write(contents)

print("Updated RunDetailView.swift")
