import Foundation

/// Streaks + badges (Streaks app "don't break the chain", Forest / HabitStreak milestones).
struct DayRecord: Equatable {
    var day: Date                  // start of day
    var sleepDetected = false
    var onsetMinuteOfDay: Int?     // local minutes since midnight of the onset
    var focusMinutes: Double = 0
    var noiseMinutes = 0           // minutes of Zone noise data that day (⚠️ 201D)
    var dosePercent: Double?       // ⚠️ 201D
    var cleanCommutes = 0          // routes with mean NO₂ < 21 ppb (⚠️ 201D)
}

enum StreakKind: String, CaseIterable, Codable {
    case sleep, focus, quiet
    var label: String { switch self { case .sleep: return "守护睡眠"; case .focus: return "专注"; case .quiet: return "安静日" } }
    var symbol: String { switch self { case .sleep: return "moon.stars.fill"; case .focus: return "timer"; case .quiet: return "ear.fill" } }
    var usesUnverifiedData: Bool { self == .quiet }

    func qualifies(_ r: DayRecord) -> Bool {
        switch self {
        case .sleep: return r.sleepDetected
        case .focus: return r.focusMinutes >= 25
        case .quiet: return r.noiseMinutes >= 60 && (r.dosePercent ?? 999) < 50
        }
    }
}

struct Streak: Equatable { var current: Int; var best: Int }

enum Achievement: String, CaseIterable, Codable {
    case firstNight, sleepWeek, earlyBird, firstFocus, focusTen, focusWeek, quietDay, quietWeek, cleanCommute

    var title: String {
        switch self {
        case .firstNight: return "第一晚"
        case .sleepWeek: return "七夜守护"
        case .earlyBird: return "早睡达人"
        case .firstFocus: return "第一个番茄"
        case .focusTen: return "十番茄"
        case .focusWeek: return "专注一周"
        case .quietDay: return "安静的一天"
        case .quietWeek: return "安静一周"
        case .cleanCommute: return "清新通勤"
        }
    }
    var detail: String {
        switch self {
        case .firstNight: return "第一次检测到入睡"
        case .sleepWeek: return "连续 7 晚检测到入睡"
        case .earlyBird: return "累计 5 晚在 23:30 前入睡"
        case .firstFocus: return "完成一次 25 分钟专注"
        case .focusTen: return "累计专注 250 分钟"
        case .focusWeek: return "连续 7 天专注 ≥25 分钟"
        case .quietDay: return "戴 Zone ≥1 小时且噪音剂量 <50%"
        case .quietWeek: return "连续 7 个安静日"
        case .cleanCommute: return "一次通勤平均 NO₂ < 21 ppb"
        }
    }
    var symbol: String {
        switch self {
        case .firstNight: return "moon.fill"
        case .sleepWeek: return "moon.stars.fill"
        case .earlyBird: return "sunrise.fill"
        case .firstFocus: return "timer"
        case .focusTen: return "flame.fill"
        case .focusWeek: return "calendar.badge.checkmark"
        case .quietDay: return "ear.fill"
        case .quietWeek: return "leaf.fill"
        case .cleanCommute: return "aqi.low"
        }
    }
    var usesUnverifiedData: Bool { self == .quietDay || self == .quietWeek || self == .cleanCommute }
}

enum AchievementEngine {
    /// Current streak counts back from today if today qualifies, else from yesterday (today isn't over yet).
    static func streak(qualifying days: Set<Date>, today: Date, calendar: Calendar) -> Streak {
        let set = Set(days.map { calendar.startOfDay(for: $0) })
        let t = calendar.startOfDay(for: today)
        var cursor = set.contains(t) ? t : calendar.date(byAdding: .day, value: -1, to: t)!
        var current = 0
        while set.contains(cursor) { current += 1; cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var best = 0, run = 0
        var prev: Date?
        for d in set.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return Streak(current: current, best: max(best, current))
    }

    static func streaks(_ records: [DayRecord], today: Date, calendar: Calendar) -> [StreakKind: Streak] {
        var out: [StreakKind: Streak] = [:]
        for k in StreakKind.allCases {
            out[k] = streak(qualifying: Set(records.filter { k.qualifies($0) }.map(\.day)), today: today, calendar: calendar)
        }
        return out
    }

    static func unlocked(_ records: [DayRecord], today: Date, calendar: Calendar) -> Set<Achievement> {
        let s = streaks(records, today: today, calendar: calendar)
        var a = Set<Achievement>()
        if records.contains(where: \.sleepDetected) { a.insert(.firstNight) }
        if (s[.sleep]?.best ?? 0) >= 7 { a.insert(.sleepWeek) }
        if records.filter({ r in r.onsetMinuteOfDay.map { $0 >= 18 * 60 && $0 < 23 * 60 + 30 } ?? false }).count >= 5 { a.insert(.earlyBird) }
        if records.contains(where: { $0.focusMinutes >= 25 }) { a.insert(.firstFocus) }
        if records.reduce(0, { $0 + $1.focusMinutes }) >= 250 { a.insert(.focusTen) }
        if (s[.focus]?.best ?? 0) >= 7 { a.insert(.focusWeek) }
        if records.contains(where: { StreakKind.quiet.qualifies($0) }) { a.insert(.quietDay) }
        if (s[.quiet]?.best ?? 0) >= 7 { a.insert(.quietWeek) }
        if records.contains(where: { $0.cleanCommutes > 0 }) { a.insert(.cleanCommute) }
        return a
    }
}
