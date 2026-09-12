import Foundation
import HealthKit
import SwiftData

protocol HKHealthStoreProtocol: AnyObject, Sendable {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws
    nonisolated func execute(_ query: HKQuery)
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
    let isIndoor: Bool?
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

    var allTypesToRead: Set<HKObjectType> {
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .runningSpeed,
            .stepCount,
            .distanceWalkingRunning,
            .runningVerticalOscillation,
            .vo2Max,
            .runningGroundContactTime,
            .runningStrideLength
        ]
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        try await healthStore?.requestAuthorization(toShare: [], read: allTypesToRead)

        let workoutStatus = healthStore?.authorizationStatus(for: HKObjectType.workoutType())
        self.isAuthorized = (workoutStatus == .sharingAuthorized) || (workoutStatus == .notDetermined)
        self.isAuthorized = true

        try await enableBackgroundDelivery()
    }

    func enableBackgroundDelivery() async throws {
        try await healthStore?.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    func getRequestStatusForAuthorization() async throws -> HKAuthorizationRequestStatus {
        guard isHealthDataAvailable(), let store = healthStore else {
            return .unknown
        }
        return try await store.statusForAuthorizationRequest(toShare: [], read: allTypesToRead)
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

    func fetchVO2MaxClosestTo(date: Date) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let samples = samples as? [HKQuantitySample], let first = samples.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let vo2 = first.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
                continuation.resume(returning: vo2)
            }
            healthStore?.execute(query)
        }
    }

    // MARK: - Bucketing & Extraction

    func fetchBucketedSamples(for workout: HKWorkout) async throws -> [BucketData] {
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) else {
            return []
        }

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

        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) else {
            throw NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Required HealthKit quantity types unavailable"])
        }

        let rawAvgHeartRate = try await fetchAverage(for: workout, type: hrType, unit: HKUnit.count().unitDivided(by: .minute()))
        let totalSteps = try await fetchSum(for: workout, type: stepType, unit: HKUnit.count())

        let rawAvgOscillation = try? await fetchAverage(for: workout, type: oscType, unit: HKUnit.meterUnit(with: .centi))
        let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool

        let buckets = try await fetchBucketedSamples(for: workout)
        let trimmed = await engine.trimDeadStops(buckets: buckets)
        let (workingPace, workingCadence, workingHR, workingOscillation, workingDistance, workingDuration) = await engine.calculateWorkingAverages(
            trimmed: trimmed,
            rawWorkoutDuration: duration,
            rawWorkoutDistance: distance,
            originalBucketCount: buckets.count
        )

        // Raw cadence is total moving steps over the entire elapsed time (including pauses)
        let rawAvgCadence: Double = duration > 0 ? (totalSteps / (duration / 60.0)) : 0.0

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
            isIndoor: isIndoor,
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
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
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
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
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
    static let totalProgressionRuns = 38
    let healthStore = HKHealthStore()

    static func profile(forIndex index: Int) -> MockRunProfile {
        let phase1: [MockRunProfile] = [
            .recovery, .easy, .urbanTraffic, .easy,
            .recovery, .cadenceRun, .urbanTraffic, .easy,
            .recovery, .cadenceRun, .easy, .recovery
        ]
        let phase2: [MockRunProfile] = [
            .easy, .steady, .cadenceRun, .steady,
            .fartlek, .easy, .progression, .steady,
            .cadenceRun, .easy, .steady, .fartlek, .progression
        ]
        let phase3: [MockRunProfile] = [
            .steady, .tempo, .longRun, .cadenceRun,
            .intervals, .steady, .pyramids, .tempo,
            .hillRepeats, .progression, .intervals, .longRun, .tempo
        ]
        if index < phase1.count {
            return phase1[index]
        } else if index < phase1.count + phase2.count {
            return phase2[index - phase1.count]
        } else {
            let offset = index - (phase1.count + phase2.count)
            return phase3[min(offset, phase3.count - 1)]
        }
    }

    static func recommendedDrillId(for profile: MockRunProfile, progress: Double) -> PreRunDrillId {
        switch profile {
        case .cadenceRun, .pyramids:
            return .cadencePyramids
        case .recovery:
            return progress < 0.5 ? .recoveryJog : .aerobicFlush
        case .easy:
            return .zone2Run
        case .steady:
            return .rhythmIntervals
        case .tempo, .progression:
            return .tempoSurges
        case .intervals:
            return progress < 0.5 ? .neuromuscularPrimer : .strides
        case .fartlek:
            return .fartlekPrimer
        case .hillRepeats:
            return .hillBounds
        case .longRun:
            return .aerobicFlush
        case .urbanTraffic:
            return .neuromuscularPrimer
        }
    }

    func seedCouchTo5K(context: ModelContext? = nil) async {
        let seededWorkouts = await seedAdvancedMockRuns()
        if let context = context {
            if seededWorkouts.isEmpty {
                // If Apple Health is not authorized or failed, seed directly to SwiftData
                seedDirectToSwiftData(context: context)
            } else {
                // Purge any existing SwiftData records so the ensuing HealthKit sync will populate clean, non-duplicate runs
                let descriptor = FetchDescriptor<RunRecord>()
                if let existing = try? context.fetch(descriptor) {
                    for run in existing {
                        context.delete(run)
                    }
                    try? context.save()
                }
            }
        }
    }

    @discardableResult
    func seedAdvancedMockRuns() async -> [HKWorkout] {
        var savedWorkouts: [HKWorkout] = []
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
            return []
        }

        let calendar = Calendar.current
        let today = Date()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        // Seed 38 runs spanning 3 months (~90 days) showing beginner-to-intermediate progression
        let totalRuns = Self.totalProgressionRuns
        for index in 0..<totalRuns {
            let profile = Self.profile(forIndex: index)
            let progress = Double(index) / Double(max(1, totalRuns - 1))
            let daysAgo = 90.0 - (Double(index) * (89.0 / Double(max(1, totalRuns - 1))))
            guard let workoutStartTime = calendar.date(byAdding: .day, value: -Int(daysAgo), to: today) else { continue }

            let totalMinutes = profile.durationMinutes
            let workoutEndTime = workoutStartTime.addingTimeInterval(TimeInterval(totalMinutes * 60))

            do {
                let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
                try await builder.beginCollection(at: workoutStartTime)

                var allSamples: [HKSample] = []

                for minute in 0..<totalMinutes {
                    let chunkStart = workoutStartTime.addingTimeInterval(TimeInterval(minute * 60))
                    let chunkEnd = chunkStart.addingTimeInterval(60)

                    let metrics = generateMinuteMetrics(for: profile, minuteIndex: minute, progress: progress)

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

                    var chunkSamples: [HKSample] = [
                        HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: distanceQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.runningSpeed), quantity: speedQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.heartRate), quantity: hrQuantity, start: chunkStart, end: chunkEnd),
                        HKQuantitySample(type: HKQuantityType(.stepCount), quantity: stepQuantity, start: chunkStart, end: chunkEnd)
                    ]

                    // Apple Watch only records running biomechanics when actively taking running strides
                    if metrics.cadence > 0 && metrics.oscillation > 0 {
                        let oscQuantity = HKQuantity(unit: HKUnit.meterUnit(with: .centi), doubleValue: metrics.oscillation)
                        let gctQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: metrics.gct)
                        let strideQuantity = HKQuantity(unit: .meter(), doubleValue: metrics.stride)

                        chunkSamples.append(contentsOf: [
                            HKQuantitySample(type: HKQuantityType(.runningVerticalOscillation), quantity: oscQuantity, start: chunkStart, end: chunkEnd),
                            HKQuantitySample(type: HKQuantityType(.runningGroundContactTime), quantity: gctQuantity, start: chunkStart, end: chunkEnd),
                            HKQuantitySample(type: HKQuantityType(.runningStrideLength), quantity: strideQuantity, start: chunkStart, end: chunkEnd)
                        ])
                    }

                    allSamples.append(contentsOf: chunkSamples)
                }

                // Progressive VO2 Max from 37.5 (beginner) to 44.5 (intermediate/advanced)
                let vo2Value = 37.5 + (progress * 7.0)
                let vo2Quantity = HKQuantity(unit: HKUnit(from: "ml/kg*min"), doubleValue: vo2Value)
                allSamples.append(HKQuantitySample(type: HKQuantityType(.vo2Max), quantity: vo2Quantity, start: workoutStartTime, end: workoutEndTime))

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add(allSamples) { _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }

                try await builder.endCollection(at: workoutEndTime)
                if let finished = try await builder.finishWorkout() {
                    savedWorkouts.append(finished)
                }

            } catch {
                print("Failed to save mock workout for day \(index): \(error)")
            }
        }
        print("✅ Successfully seeded 3 months of progressive runs to Apple Health!")
        return savedWorkouts
    }

    func seedDirectToSwiftData(context: ModelContext) {
        // Purge any previously seeded/stored RunRecords to prevent duplicate stacking
        let descriptor = FetchDescriptor<RunRecord>()
        if let existing = try? context.fetch(descriptor) {
            for run in existing {
                context.delete(run)
            }
            try? context.save()
        }

        let calendar = Calendar.current
        let today = Date()
        let totalRuns = Self.totalProgressionRuns

        for index in 0..<totalRuns {
            let profile = Self.profile(forIndex: index)
            let progress = Double(index) / Double(max(1, totalRuns - 1))
            let daysAgo = 90.0 - (Double(index) * (89.0 / Double(max(1, totalRuns - 1))))
            guard let date = calendar.date(byAdding: .hour, value: -Int(daysAgo * 24.0), to: today) else { continue }

            let durationMin = Double(profile.durationMinutes)
            // Total workout elapsed time recorded by Apple Watch
            let rawDurationSec = durationMin * 60.0

            // Model realistic dead-stop & pause durations filtered out by Framboise
            let pauseSec: Double = {
                switch profile {
                case .urbanTraffic: return Double.random(in: 90...180) // 1.5–3 mins of stoplights
                case .intervals, .pyramids: return Double.random(in: 45...90) // 1–1.5 mins recovery pauses
                case .hillRepeats: return Double.random(in: 30...60) // walking back down hill
                case .fartlek, .recovery: return Double.random(in: 20...45) // gentle breathers
                case .easy, .steady, .longRun: return Double.random(in: 15...35) // street crossings
                case .tempo, .cadenceRun, .progression: return Double.random(in: 10...25) // quick crossings/watch start
                }
            }()

            // True active running duration
            let workingSec = rawDurationSec - pauseSec
            // Progression curves across 3 months:
            // Slower beginner pace (430s/km ~ 7:10/km) advancing to faster pace (320s/km ~ 5:20/km)
            let basePace = 430.0 - (progress * 110.0)
            let profilePaceOffset: Double = {
                switch profile {
                case .recovery: return 45.0
                case .easy: return 20.0
                case .steady: return 0.0
                case .tempo: return -20.0
                case .intervals: return -10.0 // Fast intervals + slow jogs = slightly faster than steady
                case .pyramids: return -5.0
                case .fartlek: return -5.0
                case .progression: return -10.0
                case .cadenceRun: return 10.0
                case .hillRepeats: return 15.0 // Hills are slow going up and jogging down
                case .longRun: return 15.0
                case .urbanTraffic: return 20.0
                }
            }()
            let workingPaceSec = max(240.0, basePace + profilePaceOffset + Double.random(in: -3...3))
            let distanceMeters = (workingSec / workingPaceSec) * 1000.0
            let distanceKm = distanceMeters / 1000.0

            // Exact mathematical averages:
            let workingAvgPace = distanceKm > 0 ? (workingSec / distanceKm) : workingPaceSec
            let rawAvgPace = distanceKm > 0 ? (rawDurationSec / distanceKm) : workingPaceSec

            // Cadence begins at ~148 SPM (beginner floor) and climbs toward ~168 SPM
            let baseCadence = 148.0 + (progress * 20.0)
            let profileCadenceOffset: Double = {
                switch profile {
                case .cadenceRun: return 6.0
                case .intervals: return 2.0
                case .pyramids: return 1.0
                case .tempo: return 4.0
                case .recovery: return -4.0
                case .easy: return -2.0
                case .urbanTraffic: return -5.0
                case .hillRepeats: return -2.0
                default: return 0.0
                }
            }()
            let workingCadence = min(186.0, max(142.0, baseCadence + profileCadenceOffset + Double.random(in: -1.5...1.5)))
            // Raw cadence is total steps over the entire elapsed duration
            let rawCadence = (workingCadence * (workingSec / 60.0)) / (rawDurationSec / 60.0)

            // Vertical oscillation: starts higher at ~10.4 cm (bounding) and drops to ~8.0 cm (efficient)
            let baseOsc = 10.4 - (progress * 2.4)
            let profileOscOffset: Double = {
                switch profile {
                case .cadenceRun, .pyramids: return -0.4
                case .recovery: return 0.3
                case .urbanTraffic: return 0.4
                default: return 0.0
                }
            }()
            let vertOsc = max(7.2, baseOsc + profileOscOffset + Double.random(in: -0.2...0.2))
            // Vertical oscillation is only recorded when actively running, so working and raw are identical
            let rawOsc = vertOsc

            // Heart rate: Aerobic efficiency improves over time
            let baseHR = 154.0 - (progress * 12.0)
            let profileHROffset: Double = {
                switch profile {
                case .recovery: return -20.0
                case .easy: return -10.0
                case .steady: return 0.0
                case .tempo: return 15.0
                case .intervals: return 5.0
                case .hillRepeats: return 10.0
                case .fartlek: return 5.0
                case .progression: return 5.0
                case .pyramids: return 5.0
                case .longRun: return 5.0
                case .urbanTraffic: return -5.0
                case .cadenceRun: return -4.0
                }
            }()
            let workingHR = max(115.0, min(192.0, baseHR + profileHROffset + Double.random(in: -2...2)))
            // Raw HR includes pauses where heart rate drops (assuming rest HR around 110 for recovery)
            let rawHR = ((workingHR * workingSec) + (110.0 * pauseSec)) / rawDurationSec

            let paceCV: Double = {
                switch profile {
                case .intervals, .fartlek: return 0.18
                case .urbanTraffic: return 0.22
                case .hillRepeats: return 0.15
                case .pyramids: return 0.12
                default: return 0.04
                }
            }()
            let paceSlope = profile == .progression ? -0.45 : (profile == .longRun ? 0.35 : 0.0)
            let percentZone4: Double = {
                switch profile {
                case .tempo: return 0.65
                case .intervals: return 0.45
                case .pyramids: return 0.35
                case .hillRepeats: return 0.40
                case .fartlek: return 0.30
                default: return 0.08
                }
            }()

            // Aligned Drill Recommendation
            let drillId = Self.recommendedDrillId(for: profile, progress: progress)
            let template = DrillTemplate.template(for: drillId)
            let targetCadenceInt = template.calculateTargetCadence(Int(workingCadence))

            let drill = DrillRecommendation(
                drillTitle: template.title,
                preRunDrillId: template.id.rawValue,
                drillPurpose: template.defaultPurpose,
                drillWork: template.defaultWork,
                drillCues: template.generateInstructionalCue(targetCadenceInt),
                drillEffort: template.defaultEffort,
                drillRecovery: template.defaultRecovery,
                targetCadence: "\(targetCadenceInt) SPM",
                previousCadence: Int(workingCadence)
            )

            // Dynamic Coaching Insight tailored to the runner's 3-month progression
            let headline: String
            let observation: String
            if progress < 0.33 {
                headline = "Low Cadence Turnover & High Ground Impact"
                observation = "Early baseline shows average cadence at \(Int(workingCadence)) SPM with vertical oscillation at \(String(format: "%.1f", vertOsc)) cm. Focus on quick, light foot strikes to protect knees and ankles."
            } else if progress < 0.67 {
                headline = "Aerobic Base Stabilizing with Improved Rhythm"
                observation = "Cadence has progressed to \(Int(workingCadence)) SPM and vertical oscillation has reduced to \(String(format: "%.1f", vertOsc)) cm. Heart rate stability demonstrates growing aerobic efficiency."
            } else {
                headline = "Efficient Biomechanics & Strong Tempo Stability"
                observation = "Turnover is well-stabilized at \(Int(workingCadence)) SPM with a compact vertical oscillation of \(String(format: "%.1f", vertOsc)) cm. Form remains resilient through varying paces."
            }

            let insight = CoachingInsight(
                headline: headline,
                longitudinalObservation: observation,
                drillRecommendation: drill,
                drillRecommendations: [drill]
            )

            let record = RunRecord(
                hkWorkoutID: UUID(),
                date: date,
                totalDistanceMeters: distanceMeters,
                duration: rawDurationSec,
                rawAvgPace: rawAvgPace,
                rawAvgHeartRate: rawHR,
                rawAvgCadence: rawCadence,
                workingAvgPace: workingAvgPace,
                workingAvgCadence: workingCadence,
                workingAvgHeartRate: workingHR,
                workingAvgVerticalOscillation: vertOsc,
                rawAvgVerticalOscillation: rawOsc,
                workingDistanceMeters: distanceMeters,
                workingDurationSeconds: workingSec,
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
        print("✅ Successfully seeded \(totalRuns) SwiftData RunRecords directly with 3-month progression and aligned drill IDs!")
    }

    private func generateMinuteMetrics(
        for profile: MockRunProfile,
        minuteIndex: Int,
        progress: Double
    ) -> (distanceMeters: Double, heartRate: Double, cadence: Double, oscillation: Double, gct: Double, stride: Double) {
        var distance: Double = 0
        var hr: Double = 0
        var cadence: Double = 0

        // Speed scale factor: beginner runs slower (~0.85x), advanced runs faster (~1.12x)
        let speedFactor = 0.85 + (progress * 0.27)
        // Cadence progression offset: -10 SPM early on to +8 SPM later
        let cadenceShift = -10.0 + (progress * 18.0)
        // HR efficiency shift: runs at easy paces cost less cardiac effort as fitness improves
        let hrShift = 6.0 - (progress * 12.0)

        switch profile {
        case .easy:
            if minuteIndex == 15 {
                distance = 0
                hr = Double.random(in: 125...132)
                cadence = 0
            } else {
                distance = Double.random(in: 155...165) * speedFactor
                hr = Double.random(in: 135...142) + hrShift
                cadence = Double.random(in: 158...162) + cadenceShift
            }

        case .recovery:
            if minuteIndex == 12 {
                distance = 0
                hr = Double.random(in: 118...124)
                cadence = 0
            } else {
                distance = Double.random(in: 145...155) * speedFactor
                hr = Double.random(in: 125...132) + hrShift
                cadence = Double.random(in: 154...158) + cadenceShift
            }

        case .steady:
            if minuteIndex == 18 {
                distance = 0
                hr = Double.random(in: 135...140)
                cadence = 0
            } else {
                distance = Double.random(in: 175...185) * speedFactor
                hr = Double.random(in: 148...152) + hrShift
                cadence = Double.random(in: 164...166) + cadenceShift
            }

        case .tempo:
            distance = Double.random(in: 210...220) * speedFactor
            hr = Double.random(in: 175...182)
            cadence = Double.random(in: 172...176) + (cadenceShift * 0.5)

        case .intervals:
            let isWorkInterval = (minuteIndex % 5) < 3
            let isRestStop = minuteIndex == 14 || minuteIndex == 24
            if isWorkInterval {
                distance = Double.random(in: 220...240) * speedFactor
                hr = Double.random(in: 180...190)
                cadence = Double.random(in: 175...182) + (cadenceShift * 0.5)
            } else if isRestStop {
                distance = 0
                hr = Double.random(in: 125...135)
                cadence = 0
            } else {
                distance = Double.random(in: 110...125) * speedFactor
                hr = Double.random(in: 135...145) + hrShift
                cadence = Double.random(in: 150...156) + cadenceShift
            }

        case .fartlek:
            let isFast = (minuteIndex % 4) == 0
            if isFast {
                distance = Double.random(in: 230...250) * speedFactor
                hr = Double.random(in: 175...185)
                cadence = Double.random(in: 178...184) + (cadenceShift * 0.5)
            } else {
                distance = Double.random(in: 140...150) * speedFactor
                hr = Double.random(in: 135...145) + hrShift
                cadence = Double.random(in: 155...160) + cadenceShift
            }

        case .progression:
            let minuteProgress = Double(minuteIndex) / 45.0
            distance = (145.0 + (minuteProgress * 65.0) + Double.random(in: -5...5)) * speedFactor
            hr = 135.0 + (minuteProgress * 45.0) + Double.random(in: -3...3)
            cadence = 155.0 + (minuteProgress * 20.0) + cadenceShift + Double.random(in: -2...2)

        case .longRun:
            let minuteProgress = Double(minuteIndex) / 90.0
            distance = (175.0 - (minuteProgress * 15.0) + Double.random(in: -5...5)) * speedFactor
            hr = 145.0 + (minuteProgress * 20.0) + Double.random(in: -3...3)
            cadence = 165.0 - (minuteProgress * 5.0) + cadenceShift + Double.random(in: -2...2)

        case .pyramids:
            let cycle = minuteIndex % 8
            let isPause = minuteIndex == 15
            if isPause {
                distance = 0
                hr = Double.random(in: 130...138)
                cadence = 0
            } else {
                let effort = cycle < 4 ? Double(cycle) : Double(7 - cycle)
                distance = (160.0 + (effort * 25.0)) * speedFactor
                hr = 145.0 + (effort * 12.0)
                cadence = 162.0 + (effort * 4.0) + (cadenceShift * 0.5)
            }

        case .cadenceRun:
            distance = Double.random(in: 175...185) * speedFactor
            hr = Double.random(in: 145...152) + hrShift
            cadence = Double.random(in: 172...178) + (cadenceShift * 0.5)

        case .hillRepeats:
            let isUphill = (minuteIndex % 3) == 0
            let isPauseAtBottom = minuteIndex == 14 || minuteIndex == 26
            if isUphill {
                distance = Double.random(in: 130...145) * speedFactor
                hr = Double.random(in: 178...188)
                cadence = Double.random(in: 156...162) + (cadenceShift * 0.5)
            } else if isPauseAtBottom {
                distance = 0
                hr = Double.random(in: 130...140)
                cadence = 0
            } else {
                distance = Double.random(in: 120...135) * speedFactor
                hr = Double.random(in: 138...148) + hrShift
                cadence = Double.random(in: 150...155) + cadenceShift
            }

        case .urbanTraffic:
            let isDeadStop = (minuteIndex == 12 || minuteIndex == 25)
            if isDeadStop {
                distance = 0
                hr = Double.random(in: 130...140)
                cadence = 0
            } else {
                distance = Double.random(in: 170...180) * speedFactor
                hr = Double.random(in: 145...155) + hrShift
                cadence = Double.random(in: 160...165) + cadenceShift
            }
        }

        // Biomechanical relationships:
        // Lower turnover & beginner stage = higher vertical oscillation and longer ground contact time
        let baseOsc = 10.4 - (progress * 2.4)
        let baseGCT = 275.0 - (progress * 42.0)
        let baseStride = 0.94 + (progress * 0.26)

        let osc = cadence > 0 ? max(6.8, baseOsc + Double.random(in: -0.4...0.4)) : 0.0
        let gct = cadence > 0 ? max(210.0, baseGCT + Double.random(in: -8...8)) : 0.0
        let stride = cadence > 0 ? max(0.85, baseStride + ((distance - 150) / 600.0)) : 0.0

        return (distanceMeters: distance, heartRate: max(100.0, hr), cadence: max(0, cadence), oscillation: osc, gct: gct, stride: stride)
    }
}
