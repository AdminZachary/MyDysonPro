import Foundation

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
}

/// Small persisted event log (last 200 entries).
final class EventLog {
    private let key = "SleepPause.log"
    private(set) var entries: [LogEntry] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(_ text: String, date: Date = Date()) {
        entries.insert(LogEntry(date: date, text: text), at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }
}
