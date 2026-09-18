import Foundation

/// Represents the evaluated performance of an individual drill work rep.
struct DrillIntervalRep: Sendable, Equatable {
    let repIndex: Int
    let workCadence: Int
    let workHeartRate: Int
    let recoveryCadence: Int
    let recoveryHeartRate: Int
    let isMet: Bool
}

/// The complete interval-by-interval performance scorecard for a prescribed drill.
struct DrillIntervalSummary: Sendable, Equatable {
    let drillId: PreRunDrillId
    let intervalsMet: Int
    let totalIntervals: Int
    let workCadenceAvg: Int
    let recoveryCadenceAvg: Int
    let reps: [DrillIntervalRep]
    let tier: DrillAdherenceTier
    let verdict: String

    var adherencePercentage: Int {
        guard totalIntervals > 0 else { return 0 }
        return Int(round(Double(intervalsMet) / Double(totalIntervals) * 100.0))
    }

    /// Tags to persist interval results in RunRecord.framboiseTags
    var framboiseTags: [String] {
        var tags: [String] = []
        tags.append("drillIntervals:\(intervalsMet)/\(totalIntervals)")
        tags.append("drillWorkCadence:\(workCadenceAvg)")
        tags.append("drillRecCadence:\(recoveryCadenceAvg)")
        let repBits = reps.map { $0.isMet ? "1" : "0" }.joined(separator: ",")
        tags.append("drillReps:\(repBits)")
        return tags
    }

    /// Reconstructs a summary from stored framboiseTags if available
    static func from(tags: [String], drillId: PreRunDrillId) -> DrillIntervalSummary? {
        guard let intervalTag = tags.first(where: { $0.hasPrefix("drillIntervals:") }) else { return nil }
        let rawCounts = intervalTag.replacingOccurrences(of: "drillIntervals:", with: "").split(separator: "/")
        guard rawCounts.count == 2,
              let met = Int(rawCounts[0]),
              let total = Int(rawCounts[1]) else { return nil }

        let workCadence = tags.first(where: { $0.hasPrefix("drillWorkCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillWorkCadence:", with: "")) } ?? 0
        let recCadence = tags.first(where: { $0.hasPrefix("drillRecCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillRecCadence:", with: "")) } ?? 0

        var reps: [DrillIntervalRep] = []
        if let repTag = tags.first(where: { $0.hasPrefix("drillReps:") }) {
            let bits = repTag.replacingOccurrences(of: "drillReps:", with: "").split(separator: ",")
            for (idx, bit) in bits.enumerated() {
                reps.append(DrillIntervalRep(
                    repIndex: idx + 1,
                    workCadence: workCadence,
                    workHeartRate: 0,
                    recoveryCadence: recCadence,
                    recoveryHeartRate: 0,
                    isMet: bit == "1"
                ))
            }
        }

        let tier: DrillAdherenceTier
        let verdict: String
        if met == total && total > 0 {
            tier = .met
            verdict = "Flawless turnover discipline: hit all \(total) work intervals on target."
        } else if met >= (total + 1) / 2 {
            tier = .partiallyMet
            verdict = "Strong turnover adherence: hit \(met) of \(total) target intervals."
        } else {
            tier = .notMet
            verdict = "Developing turnover: hit \(met) of \(total) intervals in target band."
        }

        return DrillIntervalSummary(
            drillId: drillId,
            intervalsMet: met,
            totalIntervals: total,
            workCadenceAvg: workCadence,
            recoveryCadenceAvg: recCadence,
            reps: reps,
            tier: tier,
            verdict: verdict
        )
    }
}

/// Evaluates interval workouts rep-by-rep against prescribed target cadence and durations.
enum DrillIntervalEvaluator {

    /// Slices continuous 15-second buckets into individual work and recovery intervals.
    static func evaluate(
        buckets: [BucketData],
        drillId: PreRunDrillId,
        baselineCadence: Int,
        workoutDuration: Double,
        oscDelta: Double = 0.0
    ) -> DrillIntervalSummary {
        let durationCategory: DrillDuration
        if workoutDuration <= 720 { // <= 12 min
            durationCategory = .tenMinutes
        } else if workoutDuration >= 1500 { // >= 25 min
            durationCategory = .thirtyMinutes
        } else {
            durationCategory = .fifteenMinutes
        }

        let template = DrillTemplate.template(for: drillId)
        let targetCadenceStr = template.calculateTargetCadence(baselineCadence)
        let preRunDrill = PreRunDrill(id: drillId, previousCadence: baselineCadence, targetCadence: targetCadenceStr, duration: durationCategory)
        let effectiveRange = preRunDrill.effectiveTargetCadence

        let (warmupSec, iterations, workSec, recSec) = drillSchedule(for: drillId, duration: durationCategory)

        guard iterations > 1, !buckets.isEmpty, let workoutStart = buckets.first?.startTime else {
            // Fallback for continuous drills (Zone 2, Recovery Jog, Aerobic Flush) or empty buckets
            let avgCadence = Int(round(buckets.map(\.meanCadence).reduce(0, +) / Double(max(1, buckets.count))))
            let inTarget = effectiveRange?.contains(avgCadence) ?? true
            let met = inTarget ? 1 : 0
            let tier: DrillAdherenceTier = inTarget ? .met : .notMet
            return DrillIntervalSummary(
                drillId: drillId,
                intervalsMet: met,
                totalIntervals: 1,
                workCadenceAvg: avgCadence,
                recoveryCadenceAvg: 0,
                reps: [DrillIntervalRep(repIndex: 1, workCadence: avgCadence, workHeartRate: 0, recoveryCadence: 0, recoveryHeartRate: 0, isMet: inTarget)],
                tier: tier,
                verdict: inTarget ? "Held steady cadence throughout the drill." : "Cadence missed target steady band."
            )
        }

        var reps: [DrillIntervalRep] = []
        var totalWorkCadence = 0
        var workCount = 0
        var totalRecCadence = 0
        var recCount = 0

        for i in 0..<iterations {
            let workStartOffset = warmupSec + Double(i) * (workSec + recSec)
            let workEndOffset = workStartOffset + workSec
            let recStartOffset = workEndOffset
            let recEndOffset = recStartOffset + recSec

            let workStartDate = workoutStart.addingTimeInterval(workStartOffset)
            let workEndDate = workoutStart.addingTimeInterval(workEndOffset)
            let recStartDate = workoutStart.addingTimeInterval(recStartOffset)
            let recEndDate = workoutStart.addingTimeInterval(recEndOffset)

            // Collect buckets whose midpoint falls within work interval
            let workBuckets = buckets.filter { bucket in
                let mid = bucket.startTime.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= workStartDate && mid < workEndDate
            }

            // Collect buckets whose midpoint falls within recovery interval
            let recBuckets = buckets.filter { bucket in
                let mid = bucket.startTime.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= recStartDate && mid < recEndDate
            }

            let repWorkCadence: Int
            let repWorkHR: Int
            if !workBuckets.isEmpty {
                repWorkCadence = Int(round(workBuckets.map(\.meanCadence).reduce(0, +) / Double(workBuckets.count)))
                repWorkHR = Int(round(workBuckets.map(\.meanHR).filter { $0 > 0 }.reduce(0, +) / Double(max(1, workBuckets.filter { $0.meanHR > 0 }.count))))
            } else {
                repWorkCadence = baselineCadence
                repWorkHR = 0
            }

            let repRecCadence: Int
            let repRecHR: Int
            if !recBuckets.isEmpty {
                repRecCadence = Int(round(recBuckets.map(\.meanCadence).reduce(0, +) / Double(recBuckets.count)))
                repRecHR = Int(round(recBuckets.map(\.meanHR).filter { $0 > 0 }.reduce(0, +) / Double(max(1, recBuckets.filter { $0.meanHR > 0 }.count))))
            } else {
                repRecCadence = max(130, baselineCadence - 20)
                repRecHR = 0
            }

            let isMet: Bool
            if let range = effectiveRange {
                // Generous grace: in band or within 2 SPM
                isMet = range.contains(repWorkCadence) || (repWorkCadence >= range.lowerBound - 2 && repWorkCadence <= range.upperBound + 2)
            } else {
                isMet = repWorkCadence >= baselineCadence
            }

            reps.append(DrillIntervalRep(
                repIndex: i + 1,
                workCadence: repWorkCadence,
                workHeartRate: repWorkHR,
                recoveryCadence: repRecCadence,
                recoveryHeartRate: repRecHR,
                isMet: isMet
            ))

            totalWorkCadence += repWorkCadence
            workCount += 1
            totalRecCadence += repRecCadence
            recCount += 1
        }

        let intervalsMet = reps.filter(\.isMet).count
        let totalIntervals = reps.count
        let avgWork = workCount > 0 ? (totalWorkCadence / workCount) : baselineCadence
        let avgRec = recCount > 0 ? (totalRecCadence / recCount) : max(130, baselineCadence - 20)

        let tier: DrillAdherenceTier
        let verdict: String

        if intervalsMet == totalIntervals {
            if oscDelta <= 0 {
                tier = .exceeded
                verdict = "Flawless form execution: nailed all \(totalIntervals) intervals with improved vertical efficiency."
            } else {
                tier = .met
                verdict = "Target discipline held: nailed all \(totalIntervals) of \(totalIntervals) work intervals on target."
            }
        } else if intervalsMet >= (totalIntervals + 1) / 2 {
            tier = .partiallyMet
            verdict = "Solid effort: landed \(intervalsMet) of \(totalIntervals) work intervals within the target turnover band."
        } else {
            tier = .notMet
            verdict = "Developing turnover rhythm: completed \(intervalsMet) of \(totalIntervals) intervals in the target zone."
        }

        return DrillIntervalSummary(
            drillId: drillId,
            intervalsMet: intervalsMet,
            totalIntervals: totalIntervals,
            workCadenceAvg: avgWork,
            recoveryCadenceAvg: avgRec,
            reps: reps,
            tier: tier,
            verdict: verdict
        )
    }

    /// Helper returning (warmupSec, iterations, workSec, recoverySec) for each drill archetype.
    private static func drillSchedule(for drillId: PreRunDrillId, duration: DrillDuration) -> (warmup: Double, iterations: Int, workSec: Double, recSec: Double) {
        switch drillId {
        case .cadencePyramids:
            switch duration {
            case .tenMinutes: return (120, 4, 30, 45)
            case .fifteenMinutes: return (180, 4, 60, 90)
            case .thirtyMinutes: return (240, 6, 90, 120)
            }
        case .rhythmIntervals:
            switch duration {
            case .tenMinutes: return (120, 4, 30, 45)
            case .fifteenMinutes: return (180, 5, 45, 75)
            case .thirtyMinutes: return (240, 6, 90, 120)
            }
        case .tempoSurges:
            switch duration {
            case .tenMinutes: return (120, 3, 60, 90)
            case .fifteenMinutes: return (180, 3, 120, 120)
            case .thirtyMinutes: return (240, 4, 180, 180)
            }
        case .strides:
            switch duration {
            case .tenMinutes: return (120, 4, 15, 45)
            case .fifteenMinutes: return (180, 6, 20, 60)
            case .thirtyMinutes: return (240, 8, 30, 90)
            }
        case .neuromuscularPrimer:
            switch duration {
            case .tenMinutes: return (120, 4, 20, 40)
            case .fifteenMinutes: return (180, 5, 30, 60)
            case .thirtyMinutes: return (240, 6, 45, 90)
            }
        case .fartlekPrimer:
            switch duration {
            case .tenMinutes: return (120, 4, 45, 45)
            case .fifteenMinutes: return (180, 5, 60, 60)
            case .thirtyMinutes: return (240, 6, 120, 120)
            }
        case .hillBounds:
            switch duration {
            case .tenMinutes: return (120, 4, 20, 40)
            case .fifteenMinutes: return (180, 5, 30, 60)
            case .thirtyMinutes: return (240, 6, 45, 90)
            }
        case .aerobicFlush, .recoveryJog, .zone2Run:
            return (0, 1, Double(duration.rawValue * 60), 0)
        }
    }
}
