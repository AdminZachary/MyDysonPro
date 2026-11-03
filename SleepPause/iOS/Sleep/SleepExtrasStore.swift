import Foundation
import UserNotifications

/// Morning summary + streaks/achievements, built from data the app already has.
@MainActor
final class SleepExtrasStore: ObservableObject {
    static let shared = SleepExtrasStore()

    @Published private(set) var morning: MorningSummary?
    @Published private(set) var streaks: [StreakKind: Streak] = [:]
    @Published private(set) var unlocked: [Achievement: Date] = [:]
    @Published var justUnlocked: Achievement?

    /// Recent detected sleep-onset times, oldest first, for the Health-style chart.
    var recentOnsets: [Date] {
        let raw = (d.array(forKey: "sleep.onsets") as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        return Array(raw.suffix(14))
    }

    private let d = UserDefaults.standard
    private init() {
        if let data = d.data(forKey: "morning.last"), let m = try? JSONDecoder().decode(MorningSummary.self, from: data) { morning = m }
        if let data = d.data(forKey: "achievements"), let u = try? JSONDecoder().decode([String: Date].self, from: data) {
            for (k, v) in u { if let a = Achievement(rawValue: k) { unlocked[a] = v } }
        }
        refreshAchievements(notify: false)
    }

    // MARK: Morning summary

    func sessionStarted(_ date: Date) { d.set(date.timeIntervalSince1970, forKey: "session.start") }

    func makeMorningSummary(wake: Date, onset: Date?, alarmDeadline: Date? = nil, alarmEarly: Bool = false) {
        let start = (d.object(forKey: "session.start") as? Double).map { Date(timeIntervalSince1970: $0) }
        guard let onset, wake.timeIntervalSince(onset) > 30 * 60 else { return }   // a real night only
        let merged = NoiseExposureStore.shared.mergedAll
        let night = merged.filter { $0.start >= onset && $0.start < wake }
        let verified = !night.contains { $0.origin == .zone }
        let m = MorningSummary.build(bedStart: start, onset: onset, wake: wake,
                                     noise: night.map { ($0.start, $0.leq) },
                                     layoutVerified: verified,
                                     alarmDeadline: alarmDeadline, alarmEarly: alarmEarly,
                                     noiseLabel: NoiseMerge.primaryLabel(night))
        if let old = morning, old.onset == m.onset { return }        // one summary per night
        morning = m
        if let data = try? JSONEncoder().encode(m) { d.set(data, forKey: "morning.last") }
        let c = UNMutableNotificationContent()
        c.title = "早上好 ☀️"
        c.body = m.headline + "\n" + m.lines.dropFirst(m.latencyMinutes == nil ? 0 : 1).prefix(2).joined(separator: "\n")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "morning", content: c, trigger: nil))
        refreshAchievements(notify: true)
    }

    // MARK: Achievements

    func records(now: Date = Date()) -> [DayRecord] {
        let cal = Calendar.current
        var byDay: [Date: DayRecord] = [:]
        func rec(_ day: Date) -> DayRecord { byDay[day] ?? DayRecord(day: day) }
        // The night "belongs" to the day you went to sleep: shift by 6 h so 00:30 counts for the previous evening.
        let onsets = (d.array(forKey: "sleep.onsets") as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        for o in onsets {
            let day = cal.startOfDay(for: o.addingTimeInterval(-6 * 3600))
            var r = rec(day); r.sleepDetected = true
            let c = cal.dateComponents([.hour, .minute], from: o)
            r.onsetMinuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            byDay[day] = r
        }
        for f in FocusManager.shared.log {
            let day = cal.startOfDay(for: f.date); var r = rec(day); r.focusMinutes += f.minutes; byDay[day] = r
        }
        let ref = ExposureAccumulator.referenceSeconds * pow(10, ExposureAccumulator.criterionDb / 10)
        var energy: [Date: Double] = [:]
        for m in NoiseExposureStore.shared.mergedAll {
            let day = cal.startOfDay(for: m.start); var r = rec(day); r.noiseMinutes += 1; byDay[day] = r
            energy[day, default: 0] += pow(10, m.leq / 10) * 60
        }
        for (day, e) in energy { byDay[day]?.dosePercent = e / ref * 100 }
        for route in CommuteRecorder.shared.routes {
            if let mean = CommuteStats.of(route, metric: .no2).mean, mean < 21 {
                let day = cal.startOfDay(for: route.start); var r = rec(day); r.cleanCommutes += 1; byDay[day] = r
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    func refreshAchievements(notify: Bool = true) {
        let now = Date()
        let recs = records(now: now)
        streaks = AchievementEngine.streaks(recs, today: now, calendar: .current)
        let got = AchievementEngine.unlocked(recs, today: now, calendar: .current)
        let new = got.subtracting(unlocked.keys)
        guard !new.isEmpty else { return }
        for a in new { unlocked[a] = now }
        let enc = Dictionary(uniqueKeysWithValues: unlocked.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(enc) { d.set(data, forKey: "achievements") }
        guard notify, let first = new.sorted(by: { $0.rawValue < $1.rawValue }).first else { return }
        justUnlocked = first
        let c = UNMutableNotificationContent()
        c.title = "🏅 解锁成就：\(first.title)"
        c.body = first.detail
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ach.\(first.rawValue)", content: c, trigger: nil))
    }
}
