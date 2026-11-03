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
                .environment(\.colorScheme, .dark)      // dark-first: gradient background, light text
                .containerBackground(for: .widget) { LevelPalette.background(entry.snapshot?.airLevel) }
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
        switch family {
        case .accessoryInline:
            Text(s.map { "\($0.airText) · \($0.noiseText)" } ?? "Zone –")
        case .accessoryCircular:
            Gauge(value: Double(s?.battery ?? 0), in: 0...100) { Image(systemName: "headphones") }
                currentValueLabel: { Text(s?.battery.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Zone \(s?.batteryText ?? "–")").font(.headline)
                Text("\(s?.airText ?? "空气 –") · \(s?.noiseText ?? "–")")
                if let p = s?.focusPhase, let end = s?.focusEndsAt { Text("\(p) ") + Text(end, style: .timer) }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: s?.airLevel.map { $0 <= 1 ? "leaf.fill" : "aqi.high" } ?? "headphones")
                        .font(.title3).widgetAccentable()
                    Text(s?.batteryText ?? "–").bold()
                    Spacer()
                    Text(s?.ancLabel ?? "–").font(.caption)
                }
                HStack {
                    levelMark(s?.airLevel)
                    Text(s?.airText ?? "空气 –")
                }
                HStack {
                    levelMark(s?.ambientDb.map(ZoneSnapshot.noiseLevel))
                    Text("噪音 \(s?.noiseText ?? "–")")
                }
                if family == .systemMedium, let d = s?.dosePercent {
                    Text(String(format: "今日噪音剂量 %.0f%%", d)).font(.caption)
                }
                if let s, !s.layoutVerified, s.airLevel != nil || s.ambientDb != nil {
                    Text("读数布局未验证").font(.caption2).foregroundStyle(.secondary)
                }
                if stale { Text(s == nil ? "打开 App 连接 Zone" : "数据已过期").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

extension ZoneWidgetView {
    /// Full colour: a coloured dot. Accented / vibrant: a 4-step bar glyph so the level survives desaturation.
    @ViewBuilder
    func levelMark(_ level: Int?) -> some View {
        if renderingMode == .fullColor {
            Circle().fill(levelColor(level)).frame(width: 10, height: 10)
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
            HStack {
                VStack(alignment: .leading) {
                    Text(context.attributes.title).font(.headline)
                    Text(s.spokenSummary).font(.caption).lineLimit(2)
                }
                Spacer()
                if let p = s.focusPhase, let end = s.focusEndsAt {
                    VStack { Text(p).font(.caption); Text(end, style: .timer).monospacedDigit() }
                }
            }
            .padding()
            .foregroundStyle(.white)
            .background(LevelPalette.background(s.airLevel))
            .activityBackgroundTint(LevelPalette.night)
        } dynamicIsland: { context in
            let s = context.state.snapshot
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.airText, systemImage: "aqi.medium").foregroundStyle(levelColor(s.airLevel))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(s.noiseText, systemImage: "ear")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("电量 \(s.batteryText) · \(s.ancLabel ?? "–")")
                        Spacer()
                        if let end = s.focusEndsAt { Text(end, style: .timer).monospacedDigit() }
                    }.font(.caption)
                }
            } compactLeading: {
                Image(systemName: "aqi.medium").foregroundStyle(levelColor(s.airLevel))
            } compactTrailing: {
                Text(s.ambientDb.map { String(format: "%.0f", $0) } ?? "–")
            } minimal: {
                Circle().fill(levelColor(s.airLevel))
            }
        }
    }
}
