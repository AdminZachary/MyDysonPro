import Charts
import SwiftUI

/// Health-style trend of today's merged noise minutes.
struct NoiseTrendChart: View {
    var minutes: [NoiseMinute]

    var body: some View {
        if minutes.isEmpty {
            Text("今天还没有曲线").font(.caption).foregroundStyle(.secondary)
        } else {
            Chart(minutes, id: \.start) { sample in
                LineMark(
                    x: .value("时间", sample.start),
                    y: .value("分贝", sample.leq)
                )
                .foregroundStyle(by: .value("来源", sample.origin.detail))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale(
                [NoiseOrigin.headphone.detail, NoiseOrigin.zone.detail, NoiseOrigin.watch.detail],
                range: [Color.orange, Color.teal, Color.indigo]
            )
            .chartYScale(domain: 30...110)
            .frame(minHeight: 160)
            .accessibilityLabel("今日噪音曲线")
        }
    }
}

/// Weekly noise dose, one bar per day, like a Health trend.
struct WeeklyDoseChart: View {
    var days: [WeeklyReport.DayDose]

    var body: some View {
        Chart(days, id: \.day) { day in
            BarMark(
                x: .value("日", day.day, unit: .day),
                y: .value("剂量", day.dosePercent)
            )
            .foregroundStyle(day.dosePercent >= 100 ? Color.red : Color.orange)
        }
        .chartYAxisLabel("%")
        .frame(minHeight: 160)
        .accessibilityLabel("上周每日噪音剂量")
    }
}

/// Recent sleep-onset times. The vertical axis is the clock hour.
struct SleepOnsetChart: View {
    var onsets: [Date]

    var body: some View {
        if onsets.isEmpty {
            Text("还没有入睡记录").font(.caption).foregroundStyle(.secondary)
        } else {
            Chart(onsets, id: \.timeIntervalSince1970) { date in
                PointMark(
                    x: .value("日期", date, unit: .day),
                    y: .value("时刻", Self.hour(date))
                )
                .foregroundStyle(.indigo)
                .symbolSize(60)
            }
            .chartYScale(domain: 0...24)
            .chartYAxisLabel("时")
            .frame(minHeight: 160)
            .accessibilityLabel("最近入睡时刻")
        }
    }

    private static func hour(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }
}
