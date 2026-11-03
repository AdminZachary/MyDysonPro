import Foundation

/// Where a one-minute noise sample came from.
/// Headphone playback is the level at the ear while audio plays.
/// Zone and Apple Watch samples are ambient noise, not playback level.
enum NoiseOrigin: String, Codable, CaseIterable {
    case headphone
    case zone
    case watch

    /// Short name used in the UI. Ambient sources share “环境噪音”.
    var title: String {
        switch self {
        case .headphone: return "耳机播放音量"
        case .zone, .watch: return "环境噪音"
        }
    }

    /// Title plus the device, so Zone and the Watch are not confused.
    var detail: String {
        switch self {
        case .headphone: return "耳机播放音量"
        case .zone: return "环境噪音（Zone）"
        case .watch: return "环境噪音（Apple Watch）"
        }
    }

    /// HealthKit samples are measured by Apple. The Zone 201D layout is not.
    var verified: Bool { self != .zone }
}

struct NoiseMinute: Equatable {
    var start: Date
    var leq: Double
    var origin: NoiseOrigin
}

/// Merges headphone, Zone and Watch minutes into the single series used for dose,
/// the morning summary, the weekly noise section and the quiet-day streak.
///
/// Precedence, per clock minute — never summed:
/// 1. Headphone playback (`headphoneAudioExposure`) wins. That is the level at the ear.
/// 2. Otherwise the Zone's ambient SPL, when that minute has a Zone sample.
/// 3. Otherwise Apple Watch environmental noise (`environmentalAudioExposure`).
///
/// A minute that already has headphone audio does not also add Zone or Watch energy.
/// The Zone reading is still available to the UI as its own series.
enum NoiseMerge {
    static func floorToMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// Expand HealthKit samples into one level per minute. A sample is the level held
    /// from its start until its end. Spans are capped so a bad sample cannot fill a day.
    static func minutes(from samples: [(start: Date, end: Date, db: Double)],
                        origin: NoiseOrigin,
                        calendar: Calendar = .current,
                        maxSpan: TimeInterval = 3 * 3600) -> [NoiseMinute] {
        var levels: [Date: Double] = [:]
        for sample in samples {
            guard sample.db.isFinite, sample.db > 0, sample.db < 150 else { continue }
            let end = min(max(sample.end, sample.start), sample.start.addingTimeInterval(maxSpan))
            var cursor = floorToMinute(sample.start, calendar: calendar)
            while cursor < end {
                levels[cursor] = sample.db
                guard let next = calendar.date(byAdding: .minute, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return levels.map { NoiseMinute(start: $0.key, leq: $0.value, origin: origin) }
    }

    /// One minute, one level. Later arguments do not override earlier winners:
    /// pass watch, then zone, then headphone so headphone wins.
    static func merged(headphone: [NoiseMinute], zone: [NoiseMinute], watch: [NoiseMinute],
                       calendar: Calendar = .current) -> [NoiseMinute] {
        var byMinute: [Date: NoiseMinute] = [:]
        func put(_ rows: [NoiseMinute], _ origin: NoiseOrigin) {
            for row in rows where row.leq.isFinite && row.leq > 0 && row.leq < 150 {
                let key = floorToMinute(row.start, calendar: calendar)
                byMinute[key] = NoiseMinute(start: key, leq: row.leq, origin: origin)
            }
        }
        put(watch, .watch)
        put(zone, .zone)
        put(headphone, .headphone)
        return byMinute.values.sorted { $0.start < $1.start }
    }

    /// NIOSH-style dose for one minute = 60 s at that Leq. Same reference as `ExposureAccumulator`.
    static func dosePercent(_ minutes: [NoiseMinute]) -> Double {
        let energy = minutes.reduce(0.0) { $0 + pow(10, $1.leq / 10) * 60 }
        let ref = ExposureAccumulator.referenceSeconds * pow(10, ExposureAccumulator.criterionDb / 10)
        return 100 * energy / ref
    }

    /// The label for a merged series. Mixed minutes name the winner and say the rest was not added.
    static func primaryLabel(_ minutes: [NoiseMinute]) -> String {
        let counts = Dictionary(grouping: minutes, by: \.origin).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return "噪音" }
        if counts.count == 1 { return top.title }
        return "\(top.title)优先"
    }

    static func caption(_ minutes: [NoiseMinute]) -> String {
        if minutes.isEmpty { return "今日还没有耳机或环境噪音" }
        let counts = Dictionary(grouping: minutes, by: \.origin).mapValues(\.count)
        let parts = NoiseOrigin.allCases.compactMap { origin -> String? in
            guard let n = counts[origin], n > 0 else { return nil }
            return "\(origin.detail) \(n) 分钟"
        }
        return parts.joined(separator: " · ")
    }

    static var rule: String {
        "同一分钟只计一种，不把耳机音量和环境噪音相加。优先耳机播放音量，其次 Zone 环境噪音，最后是 Apple Watch 环境噪音。"
    }
}

/// Which headphones the person uses. Stored as a string so widgets and Shortcuts
/// can read it without touching the main-actor settings object.
enum HeadphoneKind: String, Codable, CaseIterable {
    case zone
    case airpods
    case other

    var title: String {
        switch self {
        case .zone: return "Dyson Zone"
        case .airpods: return "AirPods / Beats"
        case .other: return "其他蓝牙或有线耳机"
        }
    }

    var usesZone: Bool { self == .zone }

    var note: String {
        switch self {
        case .zone:
            return "可以看空气、噪音、风扇和降噪。入睡时默认保持降噪开启。"
        case .airpods:
            return "Apple 不让第三方 App 控制降噪，也不能读取入耳检测。系统自己的“摘下暂停”仍然有效。这里用“健康”里的耳机播放音量估算剂量。"
        case .other:
            return "睡眠暂停、智能闹钟、助眠声音和专注都可用。噪音剂量来自“健康”里的耳机播放音量；如果手表的噪音 App 有记录，也会用作环境噪音。"
        }
    }

    /// A hint from the current audio route. Callers must not write this over the saved choice.
    static func suggest(portType: String, portName: String) -> HeadphoneKind? {
        let name = portName.lowercased()
        if name.contains("zone") || name.contains("dyson") { return .zone }
        if name.contains("airpod") || name.contains("beats") { return .airpods }
        let wiredOrBluetooth: Set<String> = ["BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE", "Headphones"]
        if wiredOrBluetooth.contains(portType) { return .other }
        return nil
    }
}

enum HeadphonePreference {
    static let key = "headphones.kind"

    static func current(defaults: UserDefaults = .standard) -> HeadphoneKind {
        if let raw = defaults.string(forKey: key), let kind = HeadphoneKind(rawValue: raw) { return kind }
        return defaults.bool(forKey: "zone.enabled") ? .zone : .other
    }

    static func usesZone(defaults: UserDefaults = .standard) -> Bool { current(defaults: defaults).usesZone }
}
