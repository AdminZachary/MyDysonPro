import Foundation

/// Smart wake alarm for the watch: inside a window before the deadline, wake on the first
/// *sustained* movement (light sleep / surfacing), otherwise at the deadline. Optional gentle
/// "taps" every few minutes in the window nudge you out of deep sleep.
/// Ideas from Remwake (window + false-start guard), AutoWake/AutoSleep ("sleep cycle buster" taps)
/// and rusel95/SleepPhaseWakeApp (accelerometer-based wake window). Pure logic, unit-tested.
struct SmartAlarmConfig: Codable, Equatable {
    var enabled = false
    var hour = 7
    var minute = 0
    var windowMinutes: Double = 30
    var movementThreshold: Double = 0.03     // g, per-epoch movement index that counts as "moving"
    var activeEpochsNeeded = 3               // of the last `lookbackEpochs` epochs (false-start guard)
    var lookbackEpochs = 5                   // 5 × 30 s = 2.5 min
    var gentleTapMinutes: Double? = 5        // nil = no taps before waking
}

enum SmartAlarmDecision: Equatable {
    case none
    case gentleTap
    case wake(early: Bool)    // early = woke in light sleep before the deadline
}

struct SmartAlarmPlanner: Equatable {
    var config: SmartAlarmConfig
    private(set) var deadline: Date
    private(set) var fired: Date?
    private var lastTap: Date?
    private var epochs: [(end: Date, movement: Double)] = []

    static func == (a: SmartAlarmPlanner, b: SmartAlarmPlanner) -> Bool {
        a.config == b.config && a.deadline == b.deadline && a.fired == b.fired
    }

    init(config: SmartAlarmConfig, start: Date, calendar: Calendar = .current) {
        self.config = config
        self.deadline = Self.nextDeadline(after: start, hour: config.hour, minute: config.minute, calendar: calendar)
    }

    var windowStart: Date { deadline.addingTimeInterval(-config.windowMinutes * 60) }

    /// Next occurrence of hour:minute strictly after `start` (alarms set at 23:00 for 07:00 → tomorrow).
    static func nextDeadline(after start: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: start)
        c.hour = hour; c.minute = minute; c.second = 0
        let today = calendar.date(from: c)!
        return today > start ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    mutating func addEpoch(end: Date, movement: Double) {
        if let last = epochs.last, end <= last.end { return }
        epochs.append((end, movement))
        if epochs.count > 60 { epochs.removeFirst(epochs.count - 60) }
    }

    mutating func evaluate(at now: Date) -> SmartAlarmDecision {
        guard config.enabled, fired == nil, now >= windowStart else { return .none }
        if now >= deadline { fired = now; return .wake(early: false) }
        let recent = epochs.filter { $0.end > windowStart && $0.end <= now }.suffix(config.lookbackEpochs)
        let active = recent.filter { $0.movement >= config.movementThreshold }.count
        if active >= config.activeEpochsNeeded { fired = now; return .wake(early: true) }
        if let every = config.gentleTapMinutes, every > 0 {
            if now.timeIntervalSince(lastTap ?? .distantPast) >= every * 60 { lastTap = now; return .gentleTap }
        }
        return .none
    }
}
