import Foundation

/// Tiny status shared between the watch app and its complications (App Group).
struct WatchStatusSnapshot: Codable, Equatable {
    enum Phase: String, Codable { case idle, monitoring, asleep, alarm }
    var phase: Phase
    var since: Date?
    var alarm: Date?          // next smart-alarm deadline, if enabled
    var updated: Date

    var title: String {
        switch phase {
        case .idle: return "未开始"
        case .monitoring: return "监测中"
        case .asleep: return "已入睡"
        case .alarm: return "该起床了"
        }
    }
    var symbol: String {
        switch phase {
        case .idle: return "moon"
        case .monitoring: return "moon.zzz"
        case .asleep: return "moon.zzz.fill"
        case .alarm: return "alarm.waves.left.and.right"
        }
    }

    static let key = "watch.status"
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "SleepPauseAppGroup") as? String }

    func save() {
        guard let g = Self.groupID, let d = UserDefaults(suiteName: g), let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: Self.key)
    }

    static func load() -> WatchStatusSnapshot? {
        guard let g = groupID, let data = UserDefaults(suiteName: g)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchStatusSnapshot.self, from: data)
    }
}
