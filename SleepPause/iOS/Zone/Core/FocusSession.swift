import Foundation

/// Pomodoro-style focus session: focus with ANC, breaks with transparency; pauses automatically
/// when the headphones come off (only if the UNVERIFIED 2DD12004 worn flag is available).
struct FocusConfig: Codable, Equatable {
    var focusMinutes: Double = 25
    var shortBreakMinutes: Double = 5
    var longBreakMinutes: Double = 15
    var cyclesBeforeLongBreak: Int = 4
    var pauseWhenUnworn = true
    var focusANC: ZoneANCMode = .anc
    var breakANC: ZoneANCMode = .transparency
    var focusFanLevel: Int? = nil     // nil = leave the fan alone
}

enum FocusPhase: String, Codable {
    case idle, focus, shortBreak, longBreak
    var label: String {
        switch self { case .idle: return "未开始"; case .focus: return "专注"
        case .shortBreak: return "短休息"; case .longBreak: return "长休息" }
    }
    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

struct FocusSession: Codable, Equatable {
    var config = FocusConfig()
    private(set) var phase: FocusPhase = .idle
    private(set) var phaseEndsAt: Date?
    private(set) var pausedRemaining: TimeInterval?     // non-nil while paused
    private(set) var pausedBecauseUnworn = false
    private(set) var completedFocusCycles = 0
    private(set) var focusedSeconds: TimeInterval = 0   // actually spent focusing (excl. pauses)
    private var lastTick: Date?

    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { phase != .idle }

    func duration(of p: FocusPhase) -> TimeInterval {
        switch p {
        case .idle: return 0
        case .focus: return config.focusMinutes * 60
        case .shortBreak: return config.shortBreakMinutes * 60
        case .longBreak: return config.longBreakMinutes * 60
        }
    }

    func remaining(at now: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        return max(0, (phaseEndsAt ?? now).timeIntervalSince(now))
    }

    mutating func start(at now: Date) {
        phase = .focus; phaseEndsAt = now.addingTimeInterval(duration(of: .focus))
        pausedRemaining = nil; pausedBecauseUnworn = false
        completedFocusCycles = 0; focusedSeconds = 0; lastTick = now
    }

    mutating func stop(at now: Date) {
        _ = accumulate(now)
        phase = .idle; phaseEndsAt = nil; pausedRemaining = nil; pausedBecauseUnworn = false; lastTick = nil
    }

    mutating func pause(at now: Date, unworn: Bool = false) {
        guard isActive, !isPaused else { return }
        _ = accumulate(now)
        pausedRemaining = remaining(at: now); phaseEndsAt = nil; pausedBecauseUnworn = unworn
    }

    mutating func resume(at now: Date) {
        guard let r = pausedRemaining else { return }
        phaseEndsAt = now.addingTimeInterval(r); pausedRemaining = nil; pausedBecauseUnworn = false; lastTick = now
    }

    /// Worn flag from the Zone (nil = unknown => never auto-pause). Returns true if state changed.
    @discardableResult
    mutating func wornChanged(_ worn: Bool?, at now: Date) -> Bool {
        guard config.pauseWhenUnworn, let worn, isActive else { return false }
        if !worn, !isPaused { pause(at: now, unworn: true); return true }
        if worn, isPaused, pausedBecauseUnworn { resume(at: now); return true }
        return false
    }

    /// Advance the clock. Returns the new phase when a transition happened.
    mutating func tick(at now: Date) -> FocusPhase? {
        guard isActive, !isPaused else { return nil }
        _ = accumulate(now)
        guard let end = phaseEndsAt, now >= end else { return nil }
        let next: FocusPhase
        if phase == .focus {
            completedFocusCycles += 1
            next = completedFocusCycles % max(1, config.cyclesBeforeLongBreak) == 0 ? .longBreak : .shortBreak
        } else {
            next = .focus
        }
        phase = next
        phaseEndsAt = end.addingTimeInterval(duration(of: next))
        lastTick = now
        return next
    }

    private mutating func accumulate(_ now: Date) -> TimeInterval {
        defer { lastTick = now }
        guard phase == .focus, !isPaused, let last = lastTick else { return 0 }
        let end = phaseEndsAt.map { min($0, now) } ?? now
        let dt = max(0, end.timeIntervalSince(last))
        focusedSeconds += dt
        return dt
    }
}
