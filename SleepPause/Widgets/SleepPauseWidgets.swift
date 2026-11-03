import WidgetKit
import SwiftUI
import ActivityKit

// Home-screen widgets live in WidgetShared/ZoneStatusWidget.swift so the app can
// render the same view for simulator screenshots. The Live Activity stays here.

@main
struct SleepPauseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZoneStatusWidget()
        ZoneLiveActivityWidget()
    }
}

private func levelColor(_ l: Int?) -> Color { LevelPalette.color(l) }

struct ZoneLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZoneActivityAttributes.self) { context in
            let s = context.state.snapshot
            HStack(alignment: .center, spacing: 12) {
                if s.showsAir {
                    LevelMark(level: s.airLevel, showsName: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline)
                    Text(s.showsAir ? s.spokenSummary : (s.doseLabel ?? s.spokenSummary))
                        .font(.caption).lineLimit(3).minimumScaleFactor(0.8)
                    if !s.showsAir, let dose = s.dosePercent {
                        Text(String(format: "剂量 %.0f%%", dose)).font(.headline).monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                Text(s.ambientDb.map { String(format: "%.0f", $0) } ?? "–")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if let p = s.focusPhase, let end = s.focusEndsAt {
                    VStack(alignment: .trailing) { Text(p).font(.caption); Text(end, style: .timer).monospacedDigit() }
                }
            }
            .padding()
            .foregroundStyle(LevelPalette.ink)
            .background(LevelPalette.canvas)
            .activityBackgroundTint(LevelPalette.canvas)
        } dynamicIsland: { context in
            let s = context.state.snapshot
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if s.showsAir {
                        Label(s.airText, systemImage: "aqi.medium").foregroundStyle(levelColor(s.airLevel))
                    } else {
                        Label(s.doseLabel ?? "耳机", systemImage: "headphones")
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(s.showsAir ? s.noiseText : (s.dosePercent.map { String(format: "%.0f%%", $0) } ?? "–"), systemImage: "ear")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(s.showsAir ? "电量 \(s.batteryText) · \(s.ancLabel ?? "–")" : (s.doseLabel ?? "耳机播放音量"))
                        Spacer()
                        if let end = s.focusEndsAt { Text(end, style: .timer).monospacedDigit() }
                    }.font(.caption)
                }
            } compactLeading: {
                Image(systemName: s.showsAir ? "aqi.medium" : "headphones")
                    .foregroundStyle(s.showsAir ? levelColor(s.airLevel) : LevelPalette.ink)
            } compactTrailing: {
                Text(s.ambientDb.map { String(format: "%.0f", $0) } ?? "–")
            } minimal: {
                Image(systemName: s.showsAir ? LevelPalette.symbol(s.airLevel) : "headphones")
            }
        }
    }
}
