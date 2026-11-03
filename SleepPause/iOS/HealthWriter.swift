import Foundation
import HealthKit

/// Optional: writes the detected sleep period (onset -> monitoring stop) to Apple Health.
final class HealthWriter {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [sleepType, HKObjectType.workoutType(), HKQuantityType(.environmentalAudioExposure)],
                                                 read: [sleepType, HKQuantityType(.heartRate), HKQuantityType(.environmentalAudioExposure), HKQuantityType(.headphoneAudioExposure)])
            return true
        } catch {
            return false
        }
    }

    func writeSleep(from start: Date, to end: Date) async throws {
        guard end > start else { return }
        let sample = HKCategorySample(type: sleepType,
                                      value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                      start: start, end: end,
                                      metadata: [HKMetadataKeyWasUserEntered: false,
                                                 "SleepPauseSource": "SleepPause"])
        try await store.save(sample)
    }

    /// Launches the watch app and starts its workout session (iPhone -> Watch).
    func startWatchApp() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.startWatchApp(with: config) { success, error in
                if let error { cont.resume(throwing: error) }
                else if !success { cont.resume(throwing: NSError(domain: "SleepPause", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "startWatchApp 返回失败"])) }
                else { cont.resume() }
            }
        }
    }
}
