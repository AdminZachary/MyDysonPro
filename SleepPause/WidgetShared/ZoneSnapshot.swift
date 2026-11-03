import Foundation

/// Small state snapshot shared by the app, widgets and the Live Activity (via an App Group).
/// Foundation-only so it is unit-tested on Linux.
struct ZoneSnapshot: Codable, Hashable {
    var date: Date
    var connected: Bool
    var battery: Int?
    var ancLabel: String?
    var worn: Bool?               // ⚠️ 2DD12004, unverified
    var ambientDb: Double?        // ⚠️ 2DD1201D inferred layout
    var no2Ppb: Double?
    var vocPpb: Double?
    var temperatureC: Double?
    var layoutVerified: Bool
    var dosePercent: Double?
    var focusPhase: String?       // FocusPhase.label
    var focusEndsAt: Date?
    /// False for AirPods and other headphones: widgets hide air, ANC and fan.
    var showsAir: Bool = true
    var doseLabel: String? = nil

    static let placeholder = ZoneSnapshot(date: Date(), connected: true, battery: 72, ancLabel: "降噪", worn: true,
                                          ambientDb: 62, no2Ppb: 18, vocPpb: 120, temperatureC: 23,
                                          layoutVerified: false, dosePercent: 35, focusPhase: nil, focusEndsAt: nil)

    /// 0 good … 3 bad (same bands as the commute map).
    static func no2Level(_ v: Double) -> Int { v < 21 ? 0 : v < 53 ? 1 : v < 100 ? 2 : 3 }
    static func vocLevel(_ v: Double) -> Int { v < 250 ? 0 : v < 500 ? 1 : v < 1000 ? 2 : 3 }
    static func noiseLevel(_ v: Double) -> Int { v < 55 ? 0 : v < 70 ? 1 : v < 85 ? 2 : 3 }
    static let levelNames = ["好", "一般", "偏高", "差"]

    /// Worst of NO₂ / VOC, or nil if neither is available.
    var airLevel: Int? {
        let l = [no2Ppb.map(Self.no2Level), vocPpb.map(Self.vocLevel)].compactMap { $0 }
        return l.max()
    }

    var airText: String {
        guard let l = airLevel else { return "空气 –" }
        return "空气" + Self.levelNames[l]
    }
    var noiseText: String { ambientDb.map { String(format: "%.0f dB", $0) } ?? "– dB" }
    var batteryText: String { battery.map { "\($0)%" } ?? "–%" }

    /// One line for Siri / inline widgets / notifications.
    var spokenSummary: String {
        if !showsAir {
            var parts: [String] = []
            if let d = dosePercent { parts.append(String(format: "今日噪音剂量 %.0f%%", d)) }
            if let label = doseLabel { parts.append(label) }
            if let a = ambientDb { parts.append(String(format: "最近 %.0f 分贝", a)) }
            return parts.isEmpty ? "暂无耳机噪音数据" : parts.joined(separator: "，")
        }
        guard connected else { return "Zone 未连接" }
        var parts: [String] = []
        if let l = airLevel {
            var s = "空气\(Self.levelNames[l])"
            if let n = no2Ppb { s += String(format: "（NO₂ %.0f ppb）", n) }
            parts.append(s)
        }
        if let a = ambientDb { parts.append(String(format: "环境噪音 %.0f 分贝", a)) }
        if let b = battery { parts.append("电量 \(b)%") }
        if parts.isEmpty { return "Zone 已连接，暂时没有读数" }
        return parts.joined(separator: "，") + (layoutVerified || (airLevel == nil && ambientDb == nil) ? "" : "（读数布局未验证）")
    }

    func isStale(at now: Date, after seconds: TimeInterval = 15 * 60) -> Bool { now.timeIntervalSince(date) > seconds }
}

enum SharedStore {
    /// App Group id comes from Info.plist key `SleepPauseAppGroup` (= group.$(BASE_BUNDLE_ID)).
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "SleepPauseAppGroup") as? String }
    static let key = "zone.snapshot"

    static var defaults: UserDefaults? { groupID.flatMap { UserDefaults(suiteName: $0) } }

    static func save(_ s: ZoneSnapshot) {
        guard let d = defaults, let data = try? JSONEncoder().encode(s) else { return }
        d.set(data, forKey: key)
    }

    static func load() -> ZoneSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ZoneSnapshot.self, from: data)
    }
}
