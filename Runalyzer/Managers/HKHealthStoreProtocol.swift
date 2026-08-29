import Foundation
import HealthKit

protocol HKHealthStoreProtocol {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws
    func execute(_ query: HKQuery)
}

extension HKHealthStore: HKHealthStoreProtocol {}
