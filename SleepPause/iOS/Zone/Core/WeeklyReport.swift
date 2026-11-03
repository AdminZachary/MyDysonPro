import Foundation

/// Weekly summary (inspired by bloop / DeciBar weekly sound-dose insights).
struct WeeklyReport: Equatable {
    struct DayDose: Equatable { var day: Date; var dosePercent: Double }

    var weekStart: Date
    var noiseMinutes: Int
    var minutesAbove85: Int
    var days: [DayDose]
    var commuteCount: Int
    var commuteMeanNO2: Double?
    var cleanestRoute: String?
    var focusMinutes: Int
    var focusSessions: Int
    var sleepOnsets: Int
    var medianOnsetMinuteOfDay: Int?   // minutes after 12:00 shifted so 23:30 < 00:30
    var layoutVerified: Bool

    var averageDose: Double? { days.isEmpty ? nil : days.map(\.dosePercent).reduce(0, +) / Double(days.count) }
    var loudestDay: DayDose? { days.max { $0.dosePercent < $1.dosePercent } }

    /// Previous full Monday–Sunday week relative to `now`.
    static func previousWeek(now: Date, calendar: Calendar) -> DateInterval {
        var cal = calendar; cal.firstWeekday = 2
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!
        return DateInterval(start: cal.date(byAdding: .day, value: -7, to: thisWeek.start)!, end: thisWeek.start)
    }

    static func build(week: DateInterval, noiseMinutes: [(start: Date, leq: Double)], routes: [CommuteRoute],
                      focus: [(date: Date, minutes: Double)], onsets: [Date], calendar: Calendar,
                      layoutVerified: Bool) -> WeeklyReport {
        let nm = noiseMinutes.filter { week.contains($0.start) && $0.leq.isFinite }
        var energyByDay: [Date: Double] = [:]
        for m in nm { energyByDay[calendar.startOfDay(for: m.start), default: 0] += pow(10, m.leq / 10) * 60 }
        let ref = ExposureAccumulator.referenceSeconds * pow(10, ExposureAccumulator.criterionDb / 10)
        let days = energyByDay.map { DayDose(day: $0.key, dosePercent: $0.value / ref * 100) }.sorted { $0.day < $1.day }

        let rs = routes.filter { week.contains($0.start) }
        let no2 = rs.flatMap { $0.points.compactMap(\.no2Ppb) }
        let means = rs.compactMap { r -> (String, Double)? in CommuteStats.of(r, metric: .no2).mean.map { (r.name, $0) } }

        let f = focus.filter { week.contains($0.date) }
        let on = onsets.filter { week.contains($0) }
        let shifted = on.map { d -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return ((c.hour ?? 0) * 60 + (c.minute ?? 0) + 12 * 60) % (24 * 60)   // noon-based
        }.sorted()

        return WeeklyReport(
            weekStart: week.start, noiseMinutes: nm.count, minutesAbove85: nm.filter { $0.leq >= 85 }.count,
            days: days, commuteCount: rs.count,
            commuteMeanNO2: no2.isEmpty ? nil : no2.reduce(0, +) / Double(no2.count),
            cleanestRoute: means.min { $0.1 < $1.1 }?.0,
            focusMinutes: Int(f.reduce(0) { $0 + $1.minutes }.rounded()), focusSessions: f.count,
            sleepOnsets: on.count,
            medianOnsetMinuteOfDay: shifted.isEmpty ? nil : (shifted[shifted.count / 2] + 12 * 60) % (24 * 60),
            layoutVerified: layoutVerified)
    }

    var isEmpty: Bool { noiseMinutes == 0 && commuteCount == 0 && focusSessions == 0 && sleepOnsets == 0 }

    func summaryLines() -> [String] {
        var out: [String] = []
        if let a = averageDose, let l = loudestDay {
            let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"
            out.append(String(format: "噪音：平均每日剂量 %.0f%%，最吵是%@（%.0f%%），≥85 dB 共 %d 分钟", a, f.string(from: l.day), l.dosePercent, minutesAbove85))
        }
        if commuteCount > 0 {
            var s = "通勤：\(commuteCount) 次"
            if let n = commuteMeanNO2 { s += String(format: "，平均 NO₂ %.0f ppb", n) }
            if let c = cleanestRoute { s += "，最干净的路线是“\(c)”" }
            out.append(s)
        }
        if focusSessions > 0 { out.append("专注：\(focusSessions) 次，共 \(focusMinutes) 分钟") }
        if sleepOnsets > 0 {
            var s = "睡眠：检测到入睡 \(sleepOnsets) 次"
            if let m = medianOnsetMinuteOfDay { s += String(format: "，中位入睡时间 %02d:%02d", m / 60, m % 60) }
            out.append(s)
        }
        if !layoutVerified && (noiseMinutes > 0 || commuteCount > 0) { out.append("（噪音/空气数据来自未验证的 201D 布局）") }
        return out
    }

    /// Send at most once per week, on/after Monday `hour`:00 local time.
    static func shouldSend(now: Date, lastSentWeekStart: Date?, hour: Int = 9, calendar: Calendar) -> Bool {
        var cal = calendar; cal.firstWeekday = 2
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)!.start
        guard let sendAt = cal.date(byAdding: .hour, value: hour, to: weekStart), now >= sendAt else { return false }
        return lastSentWeekStart.map { $0 < weekStart } ?? true
    }
}
