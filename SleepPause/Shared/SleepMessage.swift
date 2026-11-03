import Foundation

/// Messages exchanged between the watch and iPhone over WatchConnectivity.
/// Kept Foundation-only so it can be unit-checked on any platform.
enum SleepMessageType: String {
    case sleepOnset      // watch -> phone: user fell asleep, pause media now
    case sessionStarted  // watch -> phone: overnight monitoring started
    case sessionStopped  // watch -> phone: monitoring stopped
    case testPause       // watch -> phone: test the pause path
    case status          // watch -> phone: periodic status (optional)
    case woke            // watch -> phone: smart alarm fired / user woke (morning summary)
}

struct SleepMessage: Equatable {
    var type: SleepMessageType
    var date: Date
    var baselineHR: Double?
    var currentHR: Double?
    var stillMinutes: Double?
    var id: String = UUID().uuidString

    static let typeKey = "type"
    static let dateKey = "date"
    static let baselineKey = "baselineHR"
    static let currentKey = "currentHR"
    static let stillKey = "stillMinutes"
    static let idKey = "id"

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            Self.typeKey: type.rawValue,
            Self.dateKey: date.timeIntervalSince1970,
            Self.idKey: id,
        ]
        if let baselineHR { d[Self.baselineKey] = baselineHR }
        if let currentHR { d[Self.currentKey] = currentHR }
        if let stillMinutes { d[Self.stillKey] = stillMinutes }
        return d
    }

    init(type: SleepMessageType, date: Date = Date(), baselineHR: Double? = nil,
         currentHR: Double? = nil, stillMinutes: Double? = nil) {
        self.type = type
        self.date = date
        self.baselineHR = baselineHR
        self.currentHR = currentHR
        self.stillMinutes = stillMinutes
    }

    init?(dictionary d: [String: Any]) {
        guard let raw = d[Self.typeKey] as? String,
              let type = SleepMessageType(rawValue: raw),
              let ts = d[Self.dateKey] as? Double else { return nil }
        self.type = type
        self.date = Date(timeIntervalSince1970: ts)
        self.baselineHR = d[Self.baselineKey] as? Double
        self.currentHR = d[Self.currentKey] as? Double
        self.stillMinutes = d[Self.stillKey] as? Double
        self.id = (d[Self.idKey] as? String) ?? UUID().uuidString
    }
}
