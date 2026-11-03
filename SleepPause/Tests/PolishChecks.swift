import Foundation

func runPolishChecks() -> Int {
    var fails = 0
    func ck(_ c: Bool, _ m: String) { print(c ? "PASS  \(m)" : "FAIL  \(m)"); if !c { fails += 1 } }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    func d(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }

    // --- Smart alarm
    var cfg = SmartAlarmConfig(); cfg.enabled = true; cfg.hour = 7; cfg.minute = 0; cfg.windowMinutes = 30
    var sa = SmartAlarmPlanner(config: cfg, start: d(2, 23), calendar: cal)
    ck(sa.deadline == d(3, 7), "smart alarm: deadline is next morning")
    ck(SmartAlarmPlanner.nextDeadline(after: d(3, 5), hour: 7, minute: 0, calendar: cal) == d(3, 7), "smart alarm: same-day deadline")
    var decisions: [SmartAlarmDecision] = []
    var t = d(3, 6)
    while t < d(3, 6, 50) {
        sa.addEpoch(end: t, movement: 0.005)
        let x = sa.evaluate(at: t); if x != .none { decisions.append(x) }
        t = t.addingTimeInterval(30)
    }
    ck(!decisions.contains(where: { if case .wake = $0 { return true }; return false }), "smart alarm: still sleeper not woken early")
    ck(decisions.filter { $0 == .gentleTap }.count == 4, "smart alarm: gentle taps every 5 min in window (got \(decisions.count))")
    // single twitch must not wake (false-start guard)
    sa.addEpoch(end: d(3, 6, 50), movement: 0.2)
    ck(sa.evaluate(at: d(3, 6, 50)) != .wake(early: true), "smart alarm: one twitch ignored")
    sa.addEpoch(end: d(3, 6, 50).addingTimeInterval(30), movement: 0.1)
    sa.addEpoch(end: d(3, 6, 51), movement: 0.08)
    ck(sa.evaluate(at: d(3, 6, 51)) == .wake(early: true), "smart alarm: sustained movement -> early wake")
    ck(sa.evaluate(at: d(3, 7)) == .none, "smart alarm: fires once")
    var sb = SmartAlarmPlanner(config: cfg, start: d(2, 23), calendar: cal)
    ck(sb.evaluate(at: d(3, 6)) == .none && sb.evaluate(at: d(3, 7)) == .wake(early: false), "smart alarm: deadline fallback")
    var off = SmartAlarmPlanner(config: SmartAlarmConfig(), start: d(2, 23), calendar: cal)
    ck(off.evaluate(at: d(3, 8)) == .none, "smart alarm: disabled -> nothing")
    let e = SleepOnsetDetector(config: SleepDetectorConfig(), startDate: d(2, 23))
    e.addEpoch(movementIndex: 0.07, endingAt: d(2, 23, 1))
    ck(e.lastMovementIndex == 0.07 && e.recentEpochs.count == 1, "detector exposes recent epochs")
    e.reset(startDate: d(2, 23))
    ck(e.recentEpochs.isEmpty, "detector reset clears epochs")


    // --- Watch snapshot + message
    ck(SleepMessage(dictionary: SleepMessage(type: .woke, date: d(3, 7)).dictionary)?.type == .woke, "woke message round trip")
    let ws = WatchStatusSnapshot(phase: .asleep, since: d(2, 23), alarm: d(3, 7), updated: d(2, 23))
    ck(ws.title == "已入睡" && (try? JSONDecoder().decode(WatchStatusSnapshot.self, from: JSONEncoder().encode(ws))) == ws, "watch snapshot codable")

    // --- Noise synth
    func stats(_ c: NoiseColor) -> (rms: Double, diff: Double, peak: Double) {
        var s = NoiseSynth(color: c)
        var prev: Float = 0, sum = 0.0, dsum = 0.0, peak = 0.0
        for _ in 0..<48_000 { let v = s.next(); sum += Double(v * v); dsum += Double(abs(v - prev)); peak = max(peak, Double(abs(v))); prev = v }
        return ((sum / 48_000).squareRoot(), dsum / 48_000, peak)
    }
    let w = stats(.white), p = stats(.pink), b = stats(.brown)
    ck(w.peak <= 1 && p.peak <= 1 && b.peak <= 1, "noise: bounded to [-1, 1]")
    ck(w.rms > 0.1 && p.rms > 0.03 && b.rms > 0.03, "noise: audible level (w \(String(format: "%.2f", w.rms)) p \(String(format: "%.2f", p.rms)) b \(String(format: "%.2f", b.rms)))")
    ck(b.diff / b.rms < p.diff / p.rms && p.diff / p.rms < w.diff / w.rms, "noise: brown darker than pink darker than white")
    var buf = [Float](repeating: 9, count: 64)
    var s2 = NoiseSynth(color: .pink)
    buf.withUnsafeMutableBufferPointer { s2.fill($0.baseAddress!, count: 64, gain: 0) }
    ck(buf.allSatisfy { $0 == 0 }, "noise: fill applies gain")
    let f = FadeEnvelope(from: 0.4, to: 0, start: d(2, 23), duration: 60)
    let g = stride(from: 0.0, through: 60, by: 5).map { f.gain(at: d(2, 23).addingTimeInterval($0)) }
    ck(abs(g.first! - 0.4) < 1e-9 && abs(g.last!) < 1e-9 && zip(g, g.dropFirst()).allSatisfy { $0 >= $1 }, "fade: smooth monotonic 0.4 -> 0")
    ck(abs(f.gain(at: d(2, 23).addingTimeInterval(30)) - 0.2) < 1e-9 && f.isFinished(at: d(2, 23, 1)), "fade: midpoint + finished")

    // --- Morning summary
    let noise: [(start: Date, leq: Double)] = (0..<120).map { (d(2, 23, 30).addingTimeInterval(Double($0) * 60), $0 < 10 ? 60 : 40) }
    let ms = MorningSummary.build(bedStart: d(2, 23), onset: d(2, 23, 12), wake: d(3, 6, 48), noise: noise,
                                  layoutVerified: false, alarmDeadline: d(3, 7), alarmEarly: true)
    ck(ms.latencyMinutes == 12 && ms.latencyRating == "正常", "morning: latency 12 min normal")
    ck(ms.sleepMinutes == 456 && ms.headline == "12 分钟入睡，睡了 7 小时 36 分", "morning: headline (\(ms.headline))")
    ck(ms.noisyMinutes == 10 && ms.noiseSampleMinutes == 120 && abs((ms.noiseMax ?? 0) - 60) < 1e-9, "morning: overnight noise stats")
    ck(ms.smartAlarmEarlyMinutes == 12 && ms.lines.contains { $0.contains("提前 12 分钟") }, "morning: smart alarm early")
    ck(ms.lines.contains { $0.contains("未验证") }, "morning: unverified flag")
    let ms2 = MorningSummary.build(bedStart: nil, onset: nil, wake: d(3, 7), noise: [], layoutVerified: false, alarmDeadline: nil, alarmEarly: false)
    ck(ms2.headline == "早上好" && ms2.lines == ["没有夜间噪音数据（需要整夜连接并佩戴 Zone）"], "morning: graceful with no data")

    // --- Streaks & achievements
    let today = d(10, 12)
    let days = [3, 4, 5, 7, 8, 9, 10].map { cal.startOfDay(for: d($0, 1)) }
    let st = AchievementEngine.streak(qualifying: Set(days), today: today, calendar: cal)
    ck(st.current == 4 && st.best == 4, "streak: current 4 (7–10), best 4")
    let st2 = AchievementEngine.streak(qualifying: Set(days.dropLast()), today: today, calendar: cal)
    ck(st2.current == 3, "streak: today not done yet keeps yesterday's streak")
    var recs: [DayRecord] = (1...7).map { i in
        DayRecord(day: cal.startOfDay(for: d(i, 1)), sleepDetected: true, onsetMinuteOfDay: 23 * 60, focusMinutes: i == 1 ? 25 : 0)
    }
    recs.append(DayRecord(day: cal.startOfDay(for: d(8, 1)), noiseMinutes: 90, dosePercent: 20))
    let un = AchievementEngine.unlocked(recs, today: d(8, 12), calendar: cal)
    ck(un.isSuperset(of: [.firstNight, .sleepWeek, .earlyBird, .firstFocus, .quietDay]) && !un.contains(.focusTen) && !un.contains(.quietWeek),
       "achievements: unlocked set")
    ck(!StreakKind.quiet.qualifies(DayRecord(day: today, noiseMinutes: 10, dosePercent: 1)), "quiet day needs ≥60 min of data")
    ck(Achievement.quietDay.usesUnverifiedData && !Achievement.firstNight.usesUnverifiedData, "achievements: unverified flags")
    return fails
}
