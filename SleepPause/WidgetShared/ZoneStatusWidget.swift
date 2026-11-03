import SwiftUI
import WidgetKit

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

struct ZoneStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoneStatus", provider: ZoneProvider()) { entry in
            ZoneWidgetView(entry: entry)
                .containerBackground(for: .widget) { LevelPalette.canvas }
        }
        .configurationDisplayName("Zone 空气与噪音")
        .description("电量、降噪模式、空气和环境噪音。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ZoneWidgetView: View {
    /// Set when the app renders this view for a screenshot. WidgetKit's environment key is read-only outside a widget.
    var familyOverride: WidgetFamily? = nil
    var renderingOverride: WidgetRenderingMode? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    /// `.accented` on a tinted Home Screen: colour is stripped, so the level also uses a symbol.
    @Environment(\.widgetRenderingMode) private var environmentRendering
    var entry: ZoneEntry

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var renderingMode: WidgetRenderingMode { renderingOverride ?? environmentRendering }

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

    /// Full colour: the Health symbol. Accented rendering: a variable bar so the level still reads.
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
