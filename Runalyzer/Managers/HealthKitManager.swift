[Output truncated for brevity]

 let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }

        // No predicate, just get the absolute latest globally
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let vo2 = sample.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }

    /// Extract data from a workout to create a RunRecord
    func extractRunRecord(from workout: HKWorkout) async throws -> RunRecord {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0

        // 1. Fetch Raw Averages (for the 'Raw Totals' mode)
        let rawAvgPace = Self.calculatePace(duration: duration, distance: distance)
        let rawAvgHeartRate = try await fetchAverageQuantity(for: workout, quantityTypeIdentifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        let totalSteps = try await fetchSumQuantity(for: workout, quantityTypeIdentifier: .stepCount, unit: HKUnit.count())
        let rawAvgCadence = Self.calculateCadence(duration: duration, steps: totalSteps)

        // 2. Concurrent Time-Based Bucketing for Working Averages
        var workingAvgHeartRate: Int?
        var workingAvgCadence: Int?
        var workingAvgPace: Double?
        var runTypeRaw = "unknown"
        var tags: [String] = []

        if let runMetrics = try? await FramboiseEngine.fetchMetricsConcurrently(for: workout, healthStore: healthStore) {
            let rawHR = runMetrics.heartRateBuckets.map { $0.value }
            let rawCadence = runMetrics.cadenceBuckets.map { $0.value }
            let rawPace = runMetrics.paceBuckets.map { $0.value }

            let trimmedHR = FramboiseEngine.trimOutliers(from: rawHR)
            let trimmedCadence = FramboiseEngine.trimOutliers(from: rawCadence)
            let trimmedPace = FramboiseEngine.trimOutliers(from: rawPace)

            workingAvgHeartRate = trimmedHR.isEmpty ? nil : Int(round(trimmedHR.reduce(0, +) / Double(trimmedHR.count)))
            workingAvgCadence = trimmedCadence.isEmpty ? nil : Int(round(trimmedCadence.reduce(0, +) / Double(trimmedCadence.count)))
            workingAvgPace = trimmedPace.isEmpty ? nil : (trimmedPace.reduce(0, +) / Double(trimmedPace.count))

            let type = FramboiseEngine.classifyRun(paceBuckets: trimmedPace, heartRateBuckets: trimmedHR)
            switch type {
            case .steady: runTypeRaw = "steady"
            case .intervals: runTypeRaw = "intervals"
            case .unknown: runTypeRaw = "unknown"
            }

            if let paceTag = FramboiseEngine.checkPaceVariance(paceBuckets: trimmedPace) {
                tags.append(paceTag)
            }
            if let cadenceTag = FramboiseEngine.checkCadenceFading(cadenceBuckets: trimmedCadence) {
                tags.append(cadenceTag)
            }
        }

        // Query average vertical oscillation (in cm)
        let verticalOscillation = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .runningVerticalOscillation,
            unit: HKUnit.meterUnit(with: .centi)
        )

        // Query average VO2 Max
        let vo2Max = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .vo2Max,
            unit: HKUnit(from: "ml/kg*min")
        )

        // Query average Ground Contact Time (in ms)
        let groundContactTime = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .runningGroundContactTime,
            unit: HKUnit.secondUnit(with: .milli)
        )

        // Query average Stride Length (in m)
        let strideLength = try await fetchAverageQuantity(
            for: workout,
            quantityTypeIdentifier: .runningStrideLength,
            unit: HKUnit.meter()
        )

        let record = RunRecord(
            id: workout.uuid,
            date: workout.startDate,
            distance: distance,
            duration: duration,
            avgPace: rawAvgPace,
            avgHeartRate: Int(rawAvgHeartRate),
            avgCadence: rawAvgCadence,
            verticalOscillation: verticalOscillation,
            vo2Max: vo2Max,
            groundContactTime: groundContactTime,
            strideLength: strideLength
        )
        record.workingAvgPace = workingAvgPace
        record.workingAvgHeartRate = workingAvgHeartRate
        record.workingAvgCadence = workingAvgCadence
        record.runTypeRaw = runTypeRaw
        record.framboiseTags = tags

        return record
    }

    // MARK: - Calculation Helpers

    static func calculatePace(duration: TimeInterval, distance: Double) -> Double {
        if distance > 0 && duration > 0 {
            // (duration in seconds / 60) / (distance in meters / 1000)
            return (duration / 60.0) / (distance / 1000.0)
        }
        return 0.0
    }

    static func calculateCadence(duration: TimeInterval, steps: Double) -> Int {
        if duration > 0 {
            // Steps per minute
            return Int(steps / (duration / 60.0))
        }
        return 0
    }

    // MARK: - Private Helpers

    private func fetchAverageQuantity(
        for workout: HKWorkout,
        quantityTypeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier) else {
            return 0.0
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error = error {
                    print("HKStatisticsQuery warning for \(quantityTypeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }

                guard let averageQuantity = result?.averageQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }

                continuation.resume(returning: averageQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchSumQuantity(
        for workout: HKWorkout,
        quantityTypeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier) else {
            return 0.0
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                // HealthKit throws "No data available for the specified predicate" if the sample type wasn't tracked for the workout.
                // We shouldn't fail the entire workout sync; we should just return 0.0.
                if let error = error {
                    print("HKStatisticsQuery warning for \(quantityTypeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }

                guard let sumQuantity = result?.sumQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }

                continuation.resume(returning: sumQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
