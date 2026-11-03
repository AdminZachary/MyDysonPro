import Foundation
import Combine

/// All Zone-related toggles. Everything Zone is OFF until the user enables the module.
@MainActor
final class ZoneSettings: ObservableObject {
    static let shared = ZoneSettings()
    private let d = UserDefaults.standard

    @Published var moduleEnabled: Bool { didSet { d.set(moduleEnabled, forKey: "zone.enabled") } }
    // 1) sleep actions
    @Published var sleepFanOff: Bool { didSet { d.set(sleepFanOff, forKey: "zone.sleepFanOff") } }
    @Published var sleepANCOff: Bool { didSet { d.set(sleepANCOff, forKey: "zone.sleepANCOff.v2") } }
    @Published var wearStopsWatch: Bool { didSet { d.set(wearStopsWatch, forKey: "zone.wearStopsWatch") } }
    // 3) noise / health
    @Published var writeNoiseToHealth: Bool { didSet { d.set(writeNoiseToHealth, forKey: "zone.noiseToHealth") } }
    @Published var noiseAlerts: Bool { didSet { d.set(noiseAlerts, forKey: "zone.noiseAlerts") } }
    // 4) commute
    @Published var commuteRecording: Bool { didSet { d.set(commuteRecording, forKey: "zone.commute") } }
    // 5) adaptive ANC
    @Published var adaptiveEnabled: Bool { didSet { d.set(adaptiveEnabled, forKey: "zone.adaptive") } }
    @Published var adaptive: AdaptiveANCConfig {
        didSet { d.set(try? JSONEncoder().encode(adaptive), forKey: "zone.adaptiveConfig") }
    }
    @Published var cloudHost: String { didSet { d.set(cloudHost, forKey: "zone.cloudHost") } }
    // extras
    @Published var fanBoostEnabled: Bool { didSet { d.set(fanBoostEnabled, forKey: "zone.fanBoost") } }
    @Published var fanBoost: FanBoostConfig {
        didSet { d.set(try? JSONEncoder().encode(fanBoost), forKey: "zone.fanBoostConfig") }
    }
    @Published var batteryAlerts: Bool { didSet { d.set(batteryAlerts, forKey: "zone.batteryAlerts") } }
    @Published var liveActivityAuto: Bool { didSet { d.set(liveActivityAuto, forKey: "zone.liveActivityAuto") } }
    @Published var weeklyReport: Bool { didSet { d.set(weeklyReport, forKey: "zone.weeklyReport") } }
    @Published var focus: FocusConfig {
        didSet { d.set(try? JSONEncoder().encode(focus), forKey: "zone.focusConfig") }
    }

    private init() {
        func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        moduleEnabled = b("zone.enabled", false)
        sleepFanOff = b("zone.sleepFanOff", true)
        sleepANCOff = b("zone.sleepANCOff.v2", false)   // 默认不关降噪（用户要求）
        wearStopsWatch = b("zone.wearStopsWatch", false)   // off by default: 2DD12004 is UNVERIFIED
        writeNoiseToHealth = b("zone.noiseToHealth", false)
        noiseAlerts = b("zone.noiseAlerts", true)
        commuteRecording = b("zone.commute", false)
        adaptiveEnabled = b("zone.adaptive", false)
        adaptive = (d.data(forKey: "zone.adaptiveConfig")).flatMap { try? JSONDecoder().decode(AdaptiveANCConfig.self, from: $0) }
            ?? AdaptiveANCConfig()
        cloudHost = d.string(forKey: "zone.cloudHost") ?? ZoneCloud.defaultHost
        fanBoostEnabled = b("zone.fanBoost", false)          // off by default: depends on unverified 201D
        fanBoost = d.data(forKey: "zone.fanBoostConfig").flatMap { try? JSONDecoder().decode(FanBoostConfig.self, from: $0) }
            ?? FanBoostConfig()
        batteryAlerts = b("zone.batteryAlerts", true)
        liveActivityAuto = b("zone.liveActivityAuto", true)
        weeklyReport = b("zone.weeklyReport", true)
        focus = d.data(forKey: "zone.focusConfig").flatMap { try? JSONDecoder().decode(FocusConfig.self, from: $0) }
            ?? FocusConfig()
    }
}
