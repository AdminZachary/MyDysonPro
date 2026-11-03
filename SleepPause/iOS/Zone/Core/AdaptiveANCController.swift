import Foundation

/// DIY "adaptive audio": picks ANC when it's loud, a quiet-mode (transparency/conversation/off)
/// when it's quiet, with hysteresis, a smoothing window, a minimum dwell time and manual override.
struct AdaptiveANCConfig: Equatable, Codable {
    var loudThresholdDb: Double = 70      // ambient >= this (smoothed) -> ANC
    var quietThresholdDb: Double = 58     // ambient <= this (smoothed) -> quietMode
    var quietMode: ZoneANCMode = .transparency
    var smoothingSeconds: Double = 20     // median over this window
    var minDwellSeconds: Double = 60      // never switch more often than this
    var manualOverrideMinutes: Double = 30
}

final class AdaptiveANCController {
    var config: AdaptiveANCConfig
    private var samples: [(Date, Double)] = []
    private var lastSwitch: Date?
    private var overrideUntil: Date?

    init(config: AdaptiveANCConfig = AdaptiveANCConfig()) { self.config = config }

    /// Call when the user changes ANC by hand (app, button on the headphones, Shortcuts).
    func noteManualChange(at now: Date) {
        overrideUntil = now.addingTimeInterval(config.manualOverrideMinutes * 60)
    }

    func clearOverride() { overrideUntil = nil }

    func isOverridden(at now: Date) -> Bool { (overrideUntil ?? .distantPast) > now }

    // MARK: Sleep hold — never auto-switch ANC while tonight's sleep watch is active,
    // nor for `sleepHoldHours` after sleep onset. The current mode is simply kept.
    var sleepWatchActive = false
    private(set) var sleepHoldUntil: Date?
    static let sleepHoldHours = 12.0

    func beginSleepHold(at now: Date, hours: Double = AdaptiveANCController.sleepHoldHours) {
        sleepHoldUntil = now.addingTimeInterval(hours * 3600)
    }

    func clearSleepHold() { sleepHoldUntil = nil }

    func isSleepHeld(at now: Date) -> Bool { sleepWatchActive || (sleepHoldUntil ?? .distantPast) > now }

    /// A focus (Pomodoro) session owns the ANC mode while it runs.
    var focusActive = false

    func smoothedLevel(at now: Date) -> Double? {
        let from = now.addingTimeInterval(-config.smoothingSeconds)
        let v = samples.filter { $0.0 >= from && $0.0 <= now }.map { $0.1 }.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    /// Feed one ambient reading; returns the mode to switch to, or nil to stay.
    func update(ambientDb: Double, at now: Date, current: ZoneANCMode?) -> ZoneANCMode? {
        guard ambientDb.isFinite, (0...140).contains(ambientDb) else { return nil }
        samples.append((now, ambientDb))
        samples.removeAll { $0.0 < now.addingTimeInterval(-max(config.smoothingSeconds, 1) * 3) }
        if isOverridden(at: now) || isSleepHeld(at: now) || focusActive { return nil }
        if let last = lastSwitch, now.timeIntervalSince(last) < config.minDwellSeconds { return nil }
        // need a reasonably filled window before acting
        guard let first = samples.first?.0, now.timeIntervalSince(first) >= config.smoothingSeconds * 0.5,
              let level = smoothedLevel(at: now) else { return nil }

        var target: ZoneANCMode?
        if level >= config.loudThresholdDb { target = .anc }
        else if level <= config.quietThresholdDb { target = config.quietMode }
        // between thresholds: hysteresis band -> keep current
        guard let t = target, t != current else { return nil }
        lastSwitch = now
        return t
    }
}
