import Foundation
import HealthKit
import SwiftData

@MainActor
protocol HKHealthStoreProtocol: AnyObject, Sendable {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws
    func execute(_ query: HKQuery)
}

extension HKHealthStore: HKHealthStoreProtocol {}

enum DateFilter {
    case sevenDays
    case thirtyDays
    case allTime
}


struct RunRecordDTO: Sendable {
    let hkWorkoutID: UUID
    let date: Date
    let totalDistanceMeters: Double
    let duration: TimeInterval
    let rawAvgPace: Double
    let rawAvgHeartRate: Double
    let rawAvgCadence: Double
    let workingAvgPace: Double
    let workingAvgCadence: Double
    let workingAvgHeartRate: Double
    let rawAvgVerticalOscillation: Double?
    let workingAvgVerticalOscillation: Double?
    let workingDistanceMeters: Double?
    let workingDurationSeconds: Double?
    let paceCV: Double
    let paceSlope: Double
    let percentZone4: Double
    let detectedTypeRaw: String
    let framboiseTags: [String]
}

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    var healthStore: HKHealthStoreProtocol?
    var isHealthDataAvailable: () -> Bool

    @Published var isAuthorized: Bool = false
    var onWorkoutsUpdated: (@Sendable () async -> Void)?
    private var observerQuery: HKObserverQuery?

    init(
        healthStore: HKHealthStoreProtocol? = nil,
        isHealthDataAvailable: @escaping () -> Bool = { HKHealthStore.isHealthDataAvailable() }
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        if let healthStore = healthStore {
            self.healthStore = healthStore
        } else if isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        }
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: .runningStrideLength)!
        ]

        try await healthStore?.requestAuthorization(toShare: [], read: typesToRead)

        let workoutStatus = healthStore?.authorizationStatus(for: HKObjectType.workoutType())
        self.isAuthorized = (workoutStatus == .sharingAuthorized) || (workoutStatus == .notDetermined)
        self.isAuthorized = true

        try await enableBackgroundDelivery()
    }

    func enableBackgroundDelivery() async throws {
        try await healthStore?.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    func startObservingWorkouts() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            nonisolated(unsafe) let handler = completionHandler
            Task { @MainActor in
                await self?.onWorkoutsUpdated?()
                handler()
            }
        }
        observerQuery = query
        healthStore?.execute(query)
    }

    func fetchRunningWorkouts(filter: DateFilter = .allTime) async throws -> [HKWorkout] {
        var subpredicates = [HKQuery.predicateForWorkouts(with: .running)]
        
        switch filter {
        case .sevenDays:
            if let date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                subpredicates.append(HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate))
            }
        case .thirtyDays:
            if let date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) {
                subpredicates.append(HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate))
            }
        case .allTime:
            break
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: workouts)
            }
            healthStore?.execute(query)
        }
    }

    func fetchWorkout(with uuid: UUID) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore?.execute(query)
        }
    }

    func fetchRecentGlobalVO2Maxes(limit: Int = 2) async throws -> [Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return []
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                let vo2s = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "ml/kg*min")) }
                continuation.resume(returning: vo2s)
            }
            healthStore?.execute(query)
        }
    }
    
    // MARK: - Bucketing & Extraction

    func fetchBucketedSamples(for workout: HKWorkout) async throws -> [BucketData] {
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!
        
        async let distanceStats = fetchCollection(for: workout, type: distanceType, options: .cumulativeSum)
        async let stepStats = fetchCollection(for: workout, type: stepType, options: .cumulativeSum)
        async let hrStats = fetchCollection(for: workout, type: hrType, options: .discreteAverage)
        async let oscStats = fetchCollection(for: workout, type: oscType, options: .discreteAverage)
        
        let (distances, steps, hrs, oscs) = try await (distanceStats, stepStats, hrStats, oscStats)
        
        var buckets: [BucketData] = []
        var currentDate = workout.startDate
        
        while currentDate < workout.endDate {
            let distance = distances[currentDate]?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            let stepCount = steps[currentDate]?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            let hr = hrs[currentDate]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            let osc = oscs[currentDate]?.averageQuantity()?.doubleValue(for: HKUnit.meterUnit(with: .centi)) ?? 0
            
            let cadence = stepCount // since bucket is 1 minute
            let pace = distance > 0 ? (60.0 / (distance / 1000.0)) : 0
            
            buckets.append(BucketData(
                startTime: currentDate,
                distanceMeters: distance,
                meanPaceSecPerKm: pace,
                meanCadence: cadence,
                meanHR: hr,
                meanVerticalOscillation: osc
            ))
            
            currentDate = currentDate.addingTimeInterval(60)
        }
        
        return buckets
    }
    
    private func fetchCollection(for workout: HKWorkout, type: HKQuantityType, options: HKStatisticsOptions) async throws -> [Date: HKStatistics] {
        return try await withCheckedThrowingContinuation { continuation in
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [workoutPredicate, datePredicate])
            var interval = DateComponents()
            interval.minute = 1
            
            // Align to workout start
            let anchor = workout.startDate
            
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: interval
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                var statsDict: [Date: HKStatistics] = [:]
                results?.enumerateStatistics(from: workout.startDate, to: workout.endDate) { stats, _ in
                    statsDict[stats.startDate] = stats
                }
                
                continuation.resume(returning: statsDict)
            }
            
            healthStore?.execute(query)
        }
    }

    func extractRunRecord(from workout: HKWorkout, engine: FramboiseEngine) async throws -> RunRecordDTO {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0

        let rawAvgPace = distance > 0 ? (duration / (distance / 1000.0)) : 0.0
        
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        
        let rawAvgHeartRate = try await fetchAverage(for: workout, type: hrType, unit: HKUnit.count().unitDivided(by: .minute()))
        let totalSteps = try await fetchSum(for: workout, type: stepType, unit: HKUnit.count())
        let rawAvgCadence = duration > 0 ? (totalSteps / (duration / 60.0)) : 0.0
        
        let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!
        let rawAvgOscillation = try? await fetchAverage(for: workout, type: oscType, unit: HKUnit.meterUnit(with: .centi))
        
        let buckets = try await fetchBucketedSamples(for: workout)
        let trimmed = await engine.trimDeadStops(buckets: buckets)
        let (workingPace, workingCadence, workingHR, workingOscillation, workingDistance, workingDuration) = await engine.calculateWorkingAverages(trimmed: trimmed)
        
        let paces = trimmed.map { $0.meanPaceSecPerKm }
        let hrs = trimmed.map { $0.meanHR }
        
        let cv = await engine.calculatePaceCV(bucketPaces: paces)
        let slope = await engine.calculatePaceSlope(bucketPaces: paces)
        // Hardcoding maxHR to 190 for now as it's not globally tracked in this context,
        // or we could use the classic 220 - age if we had DOB.
        let zone4 = await engine.calculatePercentZone4(bucketHRs: hrs, maxHR: 190)
        
        let validRawOsc = (rawAvgOscillation ?? 0) > 0 ? rawAvgOscillation : nil
        let validWorkingOsc = workingOscillation > 0 ? workingOscillation : validRawOsc
        let finalRawOsc = validRawOsc ?? validWorkingOsc

        let modelManager = ModelManager()
        let classification = await modelManager.predictRunType(
            averagePace: workingPace > 0 ? workingPace : rawAvgPace,
            averageHeartRate: workingHR > 0 ? workingHR : rawAvgHeartRate,
            percentZone4: zone4,
            averageCadence: workingCadence > 0 ? workingCadence : rawAvgCadence,
            verticalOscillation: validWorkingOsc ?? 9.5,
            runnerStage: 1,
            cv: cv,
            slope: slope,
            durationMinutes: duration / 60.0
        )
        let tags = await engine.generateFramboiseTags(cv: cv, slope: slope, deadStopsCount: buckets.count - trimmed.count)

        return RunRecordDTO(
            hkWorkoutID: workout.uuid,
            date: workout.startDate,
            totalDistanceMeters: distance,
            duration: duration,
            rawAvgPace: rawAvgPace,
            rawAvgHeartRate: rawAvgHeartRate,
            rawAvgCadence: rawAvgCadence,
            workingAvgPace: workingPace,
            workingAvgCadence: workingCadence,
            workingAvgHeartRate: workingHR,
            rawAvgVerticalOscillation: finalRawOsc,
            workingAvgVerticalOscillation: validWorkingOsc,
            workingDistanceMeters: workingDistance,
            workingDurationSeconds: workingDuration,
            paceCV: cv,
            paceSlope: slope,
            percentZone4: zone4,
            detectedTypeRaw: classification,
            framboiseTags: tags
        )
    }

    private func fetchAverage(for workout: HKWorkout, type: HKQuantityType, unit: HKUnit) async throws -> Double {
        // 1. Direct workout statistics - exact source used by Apple Fitness
        if let stat = workout.statistics(for: type),
           let avg = stat.averageQuantity()?.doubleValue(for: unit),
           avg > 0 {
            return avg
        }
        
        // 2. Query HealthStore with object predicate, fallback to date predicate
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
                if let avg = result?.averageQuantity()?.doubleValue(for: unit), avg > 0 {
                    continuation.resume(returning: avg)
                } else {
                    let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
                    let fallbackQuery = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: datePredicate, options: .discreteAverage) { _, fallbackResult, _ in
                        let fallbackAvg = fallbackResult?.averageQuantity()?.doubleValue(for: unit) ?? 0.0
                        continuation.resume(returning: fallbackAvg)
                    }
                    store?.execute(fallbackQuery)
                }
            }
            store?.execute(query)
        }
    }

    private func fetchSum(for workout: HKWorkout, type: HKQuantityType, unit: HKUnit) async throws -> Double {
        // 1. Direct workout statistics if available
        if let stat = workout.statistics(for: type),
           let sum = stat.sumQuantity()?.doubleValue(for: unit),
           sum > 0 {
            return sum
        }
        
        // 2. Query HealthStore
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                    continuation.resume(returning: sum)
                } else {
                    let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
                    let fallbackQuery = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: datePredicate, options: .cumulativeSum) { _, fallbackResult, _ in
                        let fallbackSum = fallbackResult?.sumQuantity()?.doubleValue(for: unit) ?? 0.0
                        continuation.resume(returning: fallbackSum)
                    }
                    store?.execute(fallbackQuery)
                }
            }
            store?.execute(query)
        }
    }
}
//
//  seeder.swift
//  Runalyst
//
//  Created by Joshua Agboola on 2026-08-22.
//  Updated for Runalyst V2: 1-Minute Chunking & Variance Profiles
//

import Foundation
import HealthKit

enum MockRunProfile: String, CaseIterable {
    case easy = "Easy Run"
    case recovery = "Recovery Run"
    case steady = "Steady Effort"
    case tempo = "Tempo Run"
    case intervals = "Intervals"
    case pyramids = "Pyramids"
    case fartlek = "Fartlek"
    case progression = "Progression Run"
    case cadenceRun = "Cadence Run"
    case hillRepeats = "Hill Repeats"
    case longRun = "Long Run"
    case urbanTraffic = "Urban Traffic"

    var durationMinutes: Int {
        switch self {
        case .recovery: return 25
        case .longRun: return 75
        case .intervals, .hillRepeats, .pyramids: return 30
        default: return 40
        }
    }
}

@MainActor
class HealthKitSeeder {
    static let shared = HealthKitSeeder()
    let healthStore = HKHealthStore()

    func seedCouchTo5K(context: ModelContext? = nil) async {
        if let context = context {
            seedDirectToSwiftData(context: context)
        }
        await seedAdvancedMockRuns()
    }
    
    func seedAdvancedMockRuns() async {
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.vo2Max),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningStrideLength)
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
        } catch {
            print("Failed to authorize HealthKit Seeder: \(error)")
            return
        }
        
        let calendar = Calendar.current
        let today = Date()
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        
        // Seed 27 runs (3 cycles of 9 profiles) to give a good history
        let totalRuns = MockRunProfile.allCases.count * 3
        for index in 0..<totalRuns {
            let profile = MockRunProfile.allCases[index % MockRunProfile.allCases.count]
            let daysAgo = (totalRuns * 2) - (index * 2)
            let workoutStartTime = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            
            let totalMinutes = profile.durationMinutes
            let workoutEndTime = workoutStartTime.addingTimeInterval(TimeInterval(totalMinutes * 60))
            
            do {
                let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
                try await builder.beginCollection(at: workoutStartTime)
                
                var allSamples: [HKSample] = []
                
                for minute in 0..<totalMinutes {
                    let chunkStart = workoutStartTime.addingTimeInterval(TimeInterval(minute * 60))
                    let chunkEnd = chunkStart.addingTimeInterval(60)
                    
                    let metrics = generateMinuteMetrics(for: profile, minuteIndex: minute)
                    
                    let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: metrics.distanceMeters)
                    let speedQuantity = HKQuantity(
                        unit: HKUnit.meter().unitDivided(by: .second()),
                        doubleValue: metrics.distanceMeters / 60.0
                    )
                    let hrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: metrics.heartRate)
                    let stepQuantity = HKQuantity(unit: .count(), doubleValue: metrics.cadence)
                    let oscQuantity = HKQuantity(unit: HKUnit.meterUnit(with: .centi), doubleValue: metrics.oscillation)
                    let gctQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: metrics.gct)
                    let strideQuantity = HKQuantity(unit: .meter(), doubleValue: metrics.stride)
                    
                    allSamples.append(contentsOf: [
                        HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: distanceQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.runningSpeed), quantity: speedQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.heartRate), quantity: hrQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.stepCount), quantity: stepQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.runningVerticalOscillation), quantity: oscQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.runningGroundContactTime), quantity: gctQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.runningStrideLength), quantity: strideQuantity, start: chunkStart, end: chunkEnd)
                    ])
                }
                
                let vo2Quantity = HKQuantity(unit: HKUnit(from: "ml/kg*min"), doubleValue: 45.0)
                allSamples.append(HKQuantitySample(type: HKQuantityType(.vo2Max), quantity: vo2Quantity, start: workoutStartTime, end: workoutEndTime))
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add(allSamples) { success, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
                
                try await builder.endCollection(at: workoutEndTime)
                _ = try await builder.finishWorkout()
                
            } catch {
                print("Failed to save mock workout for day \(index): \(error)")
            }
        }
        print("✅ Successfully seeded advanced variance profiles to Apple Health!")
    }
    
    func seedDirectToSwiftData(context: ModelContext) {
        let calendar = Calendar.current
        let today = Date()
        let profiles = MockRunProfile.allCases
        
        for (index, profile) in profiles.enumerated() {
            let daysAgo = Double(index * 2) + 0.5
            guard let date = calendar.date(byAdding: .hour, value: -Int(daysAgo * 24), to: today) else { continue }
            
            let durationMin = Double(profile.durationMinutes)
            let durationSec = durationMin * 60.0
            let avgPaceSec = Double.random(in: 320...390) // ~5:20 - 6:30 /km
            let distanceMeters = (durationSec / avgPaceSec) * 1000.0
            let avgHR = Double.random(in: 142...168)
            let avgCadence = Double.random(in: 156...174)
            let vertOsc = Double.random(in: 7.8...9.2)
            let paceCV = profile == .intervals || profile == .fartlek ? 0.18 : 0.04
            let paceSlope = profile == .progression ? -0.45 : (profile == .longRun ? 0.35 : 0.0)
            let percentZone4 = profile == .tempo ? 0.65 : (profile == .intervals ? 0.45 : 0.08)
            
            let drill = DrillRecommendation(
                drillTitle: "Cadence Correction Drill",
                preRunDrillId: "cadence_accelerator",
                drillPurpose: "12 min turnover focus to fix over-striding and ground impact.",
                drillWork: "4 x 60s fast turnover intervals",
                drillCues: "Drive knees forward, keep arms at 90 degrees",
                drillEffort: "Controlled progressive effort",
                drillRecovery: "60s easy jog between reps",
                targetCadence: "\(Int(avgCadence) + 6) SPM",
                previousCadence: Int(avgCadence)
            )
            
            let insight = CoachingInsight(
                headline: "Form breakdown under late fatigue",
                longitudinalObservation: "Your cadence dropped slightly near the final kilometer, correlating with a minor spike in heart rate.",
                drillRecommendation: drill,
                drillRecommendations: [drill]
            )
            
            let record = RunRecord(
                hkWorkoutID: UUID(),
                date: date,
                totalDistanceMeters: distanceMeters,
                duration: durationSec,
                rawAvgPace: avgPaceSec + Double.random(in: 2...8),
                rawAvgHeartRate: avgHR + 2.0,
                rawAvgCadence: avgCadence - 1.0,
                workingAvgPace: avgPaceSec,
                workingAvgCadence: avgCadence,
                workingAvgHeartRate: avgHR,
                workingAvgVerticalOscillation: vertOsc,
                rawAvgVerticalOscillation: vertOsc + 0.3,
                workingDistanceMeters: distanceMeters,
                workingDurationSeconds: durationSec,
                paceCV: paceCV,
                paceSlope: paceSlope,
                percentZone4: percentZone4,
                detectedTypeRaw: profile.rawValue,
                framboiseTags: [profile.rawValue],
                insight: insight
            )
            
            context.insert(record)
        }
        
        try? context.save()
        print("✅ Successfully seeded 12 SwiftData RunRecords directly!")
    }
    
    private func generateMinuteMetrics(for profile: MockRunProfile, minuteIndex: Int) -> (distanceMeters: Double, heartRate: Double, cadence: Double, oscillation: Double, gct: Double, stride: Double) {
        var distance: Double = 0
        var hr: Double = 0
        var cadence: Double = 0
        
        switch profile {
        case .easy:
            distance = Double.random(in: 155...165)
            hr = Double.random(in: 135...142)
            cadence = Double.random(in: 158...162)
            
        case .recovery:
            distance = Double.random(in: 145...155)
            hr = Double.random(in: 125...132)
            cadence = Double.random(in: 154...158)
            
        case .steady:
            distance = Double.random(in: 175...185)
            hr = Double.random(in: 148...152)
            cadence = Double.random(in: 164...166)
            
        case .tempo:
            distance = Double.random(in: 210...220)
            hr = Double.random(in: 175...182)
            cadence = Double.random(in: 172...176)
            
        case .intervals:
            let isWorkInterval = (minuteIndex % 5) < 3
            if isWorkInterval {
                distance = Double.random(in: 220...240)
                hr = Double.random(in: 180...190)
                cadence = Double.random(in: 175...182)
            } else {
                distance = Double.random(in: 110...130)
                hr = Double.random(in: 130...145)
                cadence = Double.random(in: 145...155)
            }
            
        case .fartlek:
            // 1 min fast, 3 min slow
            let isFast = (minuteIndex % 4) == 0
            if isFast {
                distance = Double.random(in: 230...250)
                hr = Double.random(in: 175...185)
                cadence = Double.random(in: 178...184)
            } else {
                distance = Double.random(in: 140...150)
                hr = Double.random(in: 135...145)
                cadence = Double.random(in: 155...160)
            }
            
        case .progression:
            // Starts around 145m/min, ends around 210m/min
            let progress = Double(minuteIndex) / 45.0
            distance = 145.0 + (progress * 65.0) + Double.random(in: -5...5)
            hr = 135.0 + (progress * 45.0) + Double.random(in: -3...3)
            cadence = 155.0 + (progress * 20.0) + Double.random(in: -2...2)
            
        case .longRun:
            // Distance slowly decreases (fatigue drift), HR drifts up
            let progress = Double(minuteIndex) / 90.0
            distance = 175.0 - (progress * 15.0) + Double.random(in: -5...5)
            hr = 145.0 + (progress * 20.0) + Double.random(in: -3...3)
            cadence = 165.0 - (progress * 5.0) + Double.random(in: -2...2)
            
        case .pyramids:
            // Ascending then descending effort
            let cycle = minuteIndex % 8
            let effort = cycle < 4 ? Double(cycle) : Double(7 - cycle)
            distance = 160.0 + (effort * 25.0)
            hr = 145.0 + (effort * 12.0)
            cadence = 162.0 + (effort * 4.0)

        case .cadenceRun:
            // High turnover focus, minimal vertical oscillation
            distance = Double.random(in: 175...185)
            hr = Double.random(in: 145...152)
            cadence = Double.random(in: 172...178)

        case .hillRepeats:
            // Alternating steep uphill effort with slow recovery jog
            let isUphill = (minuteIndex % 3) == 0
            if isUphill {
                distance = Double.random(in: 130...145)
                hr = Double.random(in: 178...188)
                cadence = Double.random(in: 156...162)
            } else {
                distance = Double.random(in: 120...135)
                hr = Double.random(in: 138...148)
                cadence = Double.random(in: 150...155)
            }

        case .urbanTraffic:
            let isDeadStop = (minuteIndex == 10 || minuteIndex == 11 || minuteIndex == 25 || minuteIndex == 26)
            if isDeadStop {
                distance = 0
                hr = Double.random(in: 130...140)
                cadence = 0
            } else {
                distance = Double.random(in: 170...180)
                hr = Double.random(in: 145...155)
                cadence = Double.random(in: 160...165)
            }
        }
        
        let osc = cadence > 0 ? (9.0 + Double.random(in: -0.5...0.5)) : 0.0
        let gct = cadence > 0 ? (240.0 + Double.random(in: -10...10)) : 0.0
        let stride = cadence > 0 ? (1.1 + (distance - 150) / 500.0) : 0.0
        
        return (distanceMeters: distance, heartRate: hr, cadence: cadence, oscillation: osc, gct: gct, stride: stride)
    }
}