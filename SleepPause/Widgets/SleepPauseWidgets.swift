import WidgetKit
import SwiftUI
import ActivityKit

// Home-screen + lock-screen widgets (inspired by Paku / CAPod widgets) and the
// Live Activity / Dynamic Island for air + noise (inspired by Paku / SoundGuard).
// Data comes from the app via the App Group snapshot; when the Zone reading is missing
// everything shows "–" instead of failing.

@main
struct SleepPauseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZoneStatusWidget()
        ZoneLiveActivityWidget()
    }
}

struct ZoneEntry: TimelineEntry {
    var date: Date
    var snapshot: ZoneSnapshot?
}

struct ZoneProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZoneEntry { ZoneEntry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (ZoneEntry) -> Void) {
        completion(ZoneEntry(date: Date(), snapshot: context.isPreview ? .placeholder : SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ZoneEntry>) -> Void) {
        let e = ZoneEntry(date: Date(), snapshot: SharedStore.load())
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private func levelColor(_ l: Int?) -> Color { LevelPalette.color(l) }

struct ZoneStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoneStatus", provider: ZoneProvider()) { entry in
            ZoneWidgetView(entry: entry)
                .containerBackground(for: .widget) { LevelPalette.canvas }
        }
        .configurationDisplayName("Zone 空气与噪音")
        .description("电量、降噪模式、空气和环境噪音。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        // systemSmall also shows up in StandBy (charging + landscape) — designed dark-first for the bedside.
    }
}

struct ZoneWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// `.accented` on an iOS 26/27 Home Screen with the clear / tinted look (and on StandBy night mode):
    /// colour is stripped, so levels must also read without colour.
    /// https://developer.apple.com/documentation/widgetkit/widgetrenderingmode
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: ZoneEntry

    var body: some View {
        let s = entry.snapshot
        let stale = s?.isStale(at: entry.date) ?? true
        let fullColor = renderingMode == .fullColor
        switch family {
        case .accessoryInline:
            if s?.showsAir == false {
                Text((s?.doseLabel ?? "耳机播放音量") + " " + (s?.dosePercent.map { String(format: "%.0f%%", $0) } ?? "–"))
            } else {
                Text(s.map { "\($0.airText) · \($0.noiseText)" } ?? "Zone –")
            }
        case .accessoryCircular:
            Gauge(value: Double(s?.battery ?? 0), in: 0...100) { Image(systemName: "headphones") }
                currentValueLabel: { Text(s?.battery.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            if s?.showsAir == false {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s?.doseLabel ?? "耳机播放音量").font(.headline)
                    Text(s?.dosePercent.map { String(format: "剂量 %.0f%%", $0) } ?? "剂量 –")
                    if let db = s?.ambientDb { Text(String(format: "%.0f dB", db)) }
                }
            } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zone \(s?.batteryText ?? "–")").font(.headline)
                HStack(spacing: 6) {
                    if fullColor { LevelMark(level: s?.airLevel, showsName: false) }
                    Text(s?.airText ?? "空气 –")
                }
                Text(s?.noiseText ?? "–")
                if let p = s?.focusPhase, let end = s?.focusEndsAt { Text("\(p) ") + Text(end, style: .timer) }
            }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                if s?.showsAir == false {
                    Text(s?.dosePercent.map { String(format: "%.0f%%", $0) } ?? "–")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text(s?.doseLabel ?? "耳机播放音量")
                        .font(.caption.weight(.semibold))
                    if let db = s?.ambientDb {
                        Text(String(format: "%.0f dB", db))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(s?.battery.map { "\($0)" } ?? "–")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text("%").font(.caption).foregroundStyle(LevelPalette.secondary)
                    Spacer()
                    Text(s?.ancLabel ?? "–").font(.caption.weight(.semibold))
                }
                HStack(spacing: 6) {
                    levelMark(s?.airLevel, fullColor: fullColor)
                    Text(s?.airText ?? "空气 –").font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 6) {
                    levelMark(s?.ambientDb.map(ZoneSnapshot.noiseLevel), fullColor: fullColor)
                    Text(s?.ambientDb.map { String(format: "%.0f dB", $0) } ?? "– dB")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                if family == .systemMedium, let d = s?.dosePercent {
                    Text(String(format: "今日噪音剂量 %.0f%%", d)).font(.caption)
                }
                if let s, !s.layoutVerified, s.airLevel != nil || s.ambientDb != nil {
                    Text("读数布局未验证").font(.caption2).foregroundStyle(LevelPalette.secondary)
                }
                if stale { Text(s == nil ? "打开 App 连接" : "数据已过期").font(.caption2).foregroundStyle(LevelPalette.secondary) }
                }
            }
            .foregroundStyle(LevelPalette.ink)
        }
    }
}

extension ZoneWidgetView {
    /// Full colour: geometric mark. Accented / vibrant: a 4-step bar so the level survives desaturation.
    @ViewBuilder
    func levelMark(_ level: Int?, fullColor: Bool) -> some View {
        if fullColor {
            LevelMark(level: level, showsName: false).widgetAccentable()
        } else {
            Image(systemName: "chart.bar.fill", variableValue: level.map { Double($0 + 1) / 4 } ?? 0)
                .font(.caption).widgetAccentable()
        }
    }
}

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
            }             compactLeading: {
                Image(systemName: s.showsAir ? "aqi.medium" : "headphones")
                    .foregroundStyle(s.showsAir ? levelColor(s.airLevel) : LevelPalette.ink)
            } compactTrailing: {
                Text(s.ambientDb.map { String(format: "%.0f", $0) } ?? "–")
            }             minimal: {
                if s.showsAir {
                    Circle().fill(levelColor(s.airLevel))
                } else {
                    Image(systemName: "headphones")
                }
            }
        }
    }
}
