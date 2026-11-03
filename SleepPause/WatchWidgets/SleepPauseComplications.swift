import WidgetKit
import SwiftUI

// Watch-face complications / Smart Stack: monitoring state + next smart alarm. Tap opens the app.

@main
struct SleepPauseComplications: WidgetBundle {
    var body: some Widget { SleepStatusComplication() }
}

struct WatchEntry: TimelineEntry {
    var date: Date
    var status: WatchStatusSnapshot?
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), status: WatchStatusSnapshot(phase: .monitoring, since: Date(), alarm: nil, updated: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WatchEntry(date: Date(), status: WatchStatusSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        completion(Timeline(entries: [WatchEntry(date: Date(), status: WatchStatusSnapshot.load())],
                            policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct SleepStatusComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepStatus", provider: WatchProvider()) { e in
            ComplicationView(entry: e)
                .containerBackground(Color(red: 0x11 / 255, green: 0x0C / 255, blue: 0x0A / 255), for: .widget)
        }
        .configurationDisplayName("SleepPause")
        .description("监测状态和智能闹钟")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchEntry

    var body: some View {
        let s = entry.status ?? WatchStatusSnapshot(phase: .idle, since: nil, alarm: nil, updated: entry.date)
        switch family {
        case .accessoryInline:
            Label(s.alarm.map { "\(s.title) · ⏰\($0.formatted(date: .omitted, time: .shortened))" } ?? s.title, systemImage: s.symbol)
        case .accessoryCorner:
            Image(systemName: s.symbol).font(.title3).widgetAccentable()
                .widgetLabel { Text(s.title) }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("SleepPause", systemImage: s.symbol).font(.headline).widgetAccentable()
                Text(s.title + (s.since.map { " \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                if let a = s.alarm { Text("智能闹钟 \(a.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: s.symbol).font(.title2).widgetAccentable()
            }
        }
    }
}
