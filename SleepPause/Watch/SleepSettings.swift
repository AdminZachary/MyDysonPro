import Foundation
import Combine

/// User-tunable thresholds, persisted in UserDefaults on the watch.
@MainActor
final class SleepSettings: ObservableObject {
    static let shared = SleepSettings()
    private let defaults = UserDefaults.standard

    @Published var stillMinutes: Double { didSet { defaults.set(stillMinutes, forKey: "stillMinutes") } }
    @Published var hrDropPercent: Double { didSet { defaults.set(hrDropPercent, forKey: "hrDropPercent") } }
    @Published var baselineMinutes: Double { didSet { defaults.set(baselineMinutes, forKey: "baselineMinutes") } }
    @Published var movementThresholdG: Double { didSet { defaults.set(movementThresholdG, forKey: "movementThresholdG") } }
    @Published var requireHeartRate: Bool { didSet { defaults.set(requireHeartRate, forKey: "requireHeartRate") } }
    @Published var endSessionAfterDetection: Bool { didSet { defaults.set(endSessionAfterDetection, forKey: "endSessionAfterDetection") } }
    /// Smart wake alarm. When enabled the workout session keeps running until the alarm.
    @Published var alarm: SmartAlarmConfig {
        didSet { defaults.set(try? JSONEncoder().encode(alarm), forKey: "smartAlarm") }
    }

    private init() {
        let store = UserDefaults.standard
        let config = SleepDetectorConfig()
        func dbl(_ key: String, _ fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        stillMinutes = dbl("stillMinutes", config.stillMinutes)
        hrDropPercent = dbl("hrDropPercent", config.hrDropPercent)
        baselineMinutes = dbl("baselineMinutes", config.baselineMinutes)
        movementThresholdG = dbl("movementThresholdG", config.movementThresholdG)
        requireHeartRate = bool("requireHeartRate", config.requireHeartRate)
        endSessionAfterDetection = bool("endSessionAfterDetection", true)
        alarm = store.data(forKey: "smartAlarm").flatMap { try? JSONDecoder().decode(SmartAlarmConfig.self, from: $0) }
            ?? SmartAlarmConfig()
    }

    var config: SleepDetectorConfig {
        var c = SleepDetectorConfig()
        c.stillMinutes = stillMinutes
        c.hrDropPercent = hrDropPercent
        c.baselineMinutes = baselineMinutes
        c.movementThresholdG = movementThresholdG
        c.requireHeartRate = requireHeartRate
        return c
    }

    func resetToDefaults() {
        let d = SleepDetectorConfig()
        stillMinutes = d.stillMinutes
        hrDropPercent = d.hrDropPercent
        baselineMinutes = d.baselineMinutes
        movementThresholdG = d.movementThresholdG
        requireHeartRate = d.requireHeartRate
        endSessionAfterDetection = true
    }
}
