import Foundation

func runExtrasChecks() -> Int {
    var fails = 0
    func ck(_ c: Bool, _ m: String) { print(c ? "PASS  \(m)" : "FAIL  \(m)"); if !c { fails += 1 } }
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // --- Fan boost
    let fb = FanBoostController()
    var level = 1
    var acts: [FanBoostAction] = []
    func feed(_ no2: Double?, _ voc: Double?, _ from: Double, _ to: Double, held: Bool = false, visor: Bool? = true) {
        var t = from
        while t < to {
            if let a = fb.update(no2: no2, voc: voc, at: at(t), currentLevel: level, held: held, visorAttached: visor) {
                acts.append(a)
                switch a { case .boost(let l, _): level = l; case .restore(let l): level = l }
            }
            t += 5
        }
    }
    feed(10, 100, 0, 60)
    ck(acts.isEmpty, "fan boost: clean air -> nothing")
    feed(80, 100, 60, 75)
    ck(acts.isEmpty, "fan boost: short spike (<20 s) ignored")
    feed(80, 100, 75, 120)
    ck(level == 3 && acts.count == 1, "fan boost: sustained NO2 spike -> level 3")
    feed(10, 100, 120, 200)
    ck(level == 3, "fan boost: min boost time respected")
    feed(10, 100, 200, 260)
    ck(level == 1 && acts.last == .restore(to: 1), "fan boost: clear air -> restore previous level")
    feed(80, 100, 260, 400)
    ck(level == 1, "fan boost: cooldown after restore")
    feed(nil, nil, 400, 900)
    ck(level == 1, "fan boost: missing data -> no action")
    feed(80, 900, 900, 1000, held: true)
    ck(level == 1, "fan boost: never during sleep hold")
    feed(80, 900, 1000, 1100, visor: false)
    ck(level == 1, "fan boost: visor not attached -> no action")
    feed(10, 900, 1100, 1200)
    ck(level == 3, "fan boost: VOC alone triggers")
    fb.noteManualChange(); level = 2
    feed(10, 100, 1200, 1500)
    ck(level == 2, "fan boost: manual change wins (no restore)")

    // --- Adaptive focus hold
    let ac = AdaptiveANCController()
    ac.focusActive = true
    var m: ZoneANCMode? = .anc
    for i in 0..<60 { if let x = ac.update(ambientDb: 40, at: at(Double(i) * 2), current: m) { m = x } }
    ck(m == .anc, "adaptive paused during focus")

    // --- Focus session
    var fs = FocusSession()
    fs.config.focusMinutes = 25; fs.config.shortBreakMinutes = 5; fs.config.longBreakMinutes = 15; fs.config.cyclesBeforeLongBreak = 2
    fs.start(at: at(0))
    ck(fs.phase == .focus && abs(fs.remaining(at: at(60)) - 1440) < 0.001, "focus: starts 25 min")
    var seq: [FocusPhase] = []
    var t = 0.0
    while t <= 25 * 60 { if let p = fs.tick(at: at(t)) { seq.append(p) }; t += 1 }
    ck(seq == [.shortBreak], "focus: -> short break")
    ck(fs.wornChanged(false, at: at(1600)) && fs.isPaused, "focus: unworn pauses")
    let r1 = fs.remaining(at: at(1700))
    ck(fs.tick(at: at(5000)) == nil && fs.remaining(at: at(5000)) == r1, "focus: paused timer frozen")
    ck(fs.wornChanged(true, at: at(5000)) && !fs.isPaused, "focus: worn resumes")
    ck(fs.wornChanged(nil, at: at(5001)) == false, "focus: unknown worn -> no change")
    t = 5000
    while t <= 5000 + r1 + 25 * 60 + 2 { if let p = fs.tick(at: at(t)) { seq.append(p) }; t += 1 }
    ck(seq == [.shortBreak, .focus, .longBreak], "focus: long break after 2 cycles")
    ck(abs(fs.focusedSeconds - 50 * 60) < 3, "focus: counts only focused time (got \(Int(fs.focusedSeconds)))")
    fs.stop(at: at(t + 10))
    ck(fs.phase == .idle, "focus: stop")

    // --- Battery policy
    var bp = BatteryAlertPolicy()
    let seqB = [50, 25, 20, 19, 15, 10, 9, 8, 40, 20].map { bp.update(percent: $0) }
    ck(seqB == [nil, nil, 20, nil, nil, 10, nil, nil, nil, 20], "battery alerts fire once per threshold, re-arm after charge")
    var bp2 = BatteryAlertPolicy()
    ck(bp2.update(percent: 8) == 10 && bp2.update(percent: 7) == nil, "battery: jump below both -> single alert")
    ck(BatteryAlertPolicy.bedtimeWarning(percent: 25) != nil && BatteryAlertPolicy.bedtimeWarning(percent: 60) == nil
       && BatteryAlertPolicy.bedtimeWarning(percent: nil) == nil, "bedtime battery warning")

    // --- Weekly report
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!   // Wed
    let wk = WeeklyReport.previousWeek(now: now, calendar: cal)
    ck(cal.component(.weekday, from: wk.start) == 2 && cal.component(.day, from: wk.start) == 26, "weekly: previous Mon 26 Oct")
    let mon = wk.start
    var noise: [(start: Date, leq: Double)] = []
    for i in 0..<240 { noise.append((mon.addingTimeInterval(9 * 3600 + Double(i) * 60), 88)) }     // 4 h @ 88 dB ≈ 100 %
    noise.append((mon.addingTimeInterval(-3600), 99))                                           // outside week
    let route = CommuteRoute(name: "地铁", start: mon.addingTimeInterval(8 * 3600),
                             points: [CommutePoint(lat: 0, lon: 0, date: mon, no2Ppb: 40, vocPpb: nil, ambientDb: nil)])
    let route2 = CommuteRoute(name: "骑车", start: mon.addingTimeInterval(86400 + 8 * 3600),
                              points: [CommutePoint(lat: 0, lon: 0, date: mon, no2Ppb: 20, vocPpb: nil, ambientDb: nil)])
    let onsets = [23 * 60 + 30, 24 * 60 + 30, 23 * 60 + 50].map { mon.addingTimeInterval(Double($0) * 60) }
    let rep = WeeklyReport.build(week: wk, noiseMinutes: noise, routes: [route, route2],
                                 focus: [(mon.addingTimeInterval(36000), 25), (mon.addingTimeInterval(40000), 50)],
                                 onsets: onsets, calendar: cal, layoutVerified: false)
    ck(rep.noiseMinutes == 240 && rep.minutesAbove85 == 240, "weekly: noise minutes in week only")
    ck(rep.days.count == 1 && abs(rep.days[0].dosePercent - 100) < 1, "weekly: 4 h @ 88 dB ≈ 100 % dose (got \(rep.days.first?.dosePercent ?? -1))")
    ck(rep.commuteCount == 2 && rep.commuteMeanNO2 == 30 && rep.cleanestRoute == "骑车", "weekly: commute + cleanest route")
    ck(rep.focusMinutes == 75 && rep.focusSessions == 2, "weekly: focus totals")
    ck(rep.sleepOnsets == 3 && rep.medianOnsetMinuteOfDay == 23 * 60 + 50, "weekly: median onset across midnight 23:50")
    ck(rep.summaryLines().contains { $0.contains("未验证") }, "weekly: unverified note")
    let monday9 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9, minute: 5))!
    let monday8 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))!
    ck(WeeklyReport.shouldSend(now: monday9, lastSentWeekStart: nil, calendar: cal)
       && !WeeklyReport.shouldSend(now: monday8, lastSentWeekStart: nil, calendar: cal), "weekly: send on Monday after 9:00")
    var c2 = cal; c2.firstWeekday = 2
    let thisWeek = c2.dateInterval(of: .weekOfYear, for: monday9)!.start
    ck(!WeeklyReport.shouldSend(now: now, lastSentWeekStart: thisWeek, calendar: cal), "weekly: once per week")

    // --- Snapshot
    var s = ZoneSnapshot.placeholder
    s.no2Ppb = 60; s.vocPpb = 100
    ck(s.airLevel == 2 && s.airText == "空气偏高", "snapshot: worst of NO2/VOC")
    s.no2Ppb = nil; s.vocPpb = nil; s.ambientDb = nil
    ck(s.airLevel == nil && s.airText == "空气 –" && s.noiseText == "– dB", "snapshot: missing data shows dashes")
    ck(s.spokenSummary == "电量 72%", "snapshot: summary without unverified data")
    s.ambientDb = 61
    ck(s.spokenSummary.contains("61 分贝") && s.spokenSummary.contains("未验证"), "snapshot: summary flags unverified layout")
    s.connected = false
    ck(s.spokenSummary == "Zone 未连接", "snapshot: disconnected")
    let enc = try? JSONDecoder().decode(ZoneSnapshot.self, from: JSONEncoder().encode(ZoneSnapshot.placeholder))
    ck(enc == ZoneSnapshot.placeholder, "snapshot: codable round trip")
    return fails
}
