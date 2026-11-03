import SwiftUI
import MapKit

struct CommuteMapView: View {
    @ObservedObject var rec = CommuteRecorder.shared
    @ObservedObject var settings = ZoneSettings.shared
    @State private var metric: CommuteMetric = .no2
    @State private var selected: UUID?

    private var shown: CommuteRoute? {
        if let a = rec.active { return a }
        return rec.routes.first { $0.id == selected } ?? rec.routes.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map {
                    if let r = shown {
                        // colored polyline: one segment per pair of points, colored by the later point
                        ForEach(Array(zip(r.points, r.points.dropFirst()).enumerated()), id: \.offset) { _, pair in
                            MapPolyline(coordinates: [coord(pair.0), coord(pair.1)])
                                .stroke(color(for: pair.1), lineWidth: 6)
                        }
                        // heat dots
                        ForEach(Array(r.points.enumerated()), id: \.offset) { _, p in
                            MapCircle(center: coord(p), radius: 25).foregroundStyle(color(for: p).opacity(0.25))
                        }
                    }
                    UserAnnotation()
                }
                .frame(minHeight: 300)
                .overlay(alignment: .bottom) { mapControls.padding(12) }

                Form {
                    Section {
                        Toggle("通勤记录（仅开启时记录位置）", isOn: $settings.commuteRecording)
                            .onChange(of: settings.commuteRecording) { _, on in on ? rec.start() : rec.stop() }
                        Text(rec.status).font(.caption)
                        Picker("指标", selection: $metric) {
                            ForEach(CommuteMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        if !ZoneAQLayout.current.isVerified {
                            Text("读数来自未验证的 201D 布局").font(.caption).foregroundStyle(Palette.red)
                        }
                    }
                    Section("路线对比") {
                        ForEach(rec.routes) { r in
                            let s = CommuteStats.of(r, metric: metric)
                            Button {
                                selected = r.id
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(r.name).bold()
                                    Text(String(format: "%.0f 分钟 · %.1f km · 平均 %@ · 最高 %@ · 偏高占比 %@",
                                                s.durationMinutes, s.distanceKm, fmt(s.mean), fmt(s.maximum),
                                                s.fractionBad.map { String(format: "%.0f%%", $0 * 100) } ?? "–"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions { Button("删除", role: .destructive) { rec.delete(r) } }
                        }
                    }
                }
            }
            .navigationTitle("通勤污染地图")
        }
    }

    /// Floating glass controls over the map: record toggle + level legend (one glass container).
    private var mapControls: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    settings.commuteRecording.toggle()     // the Toggle's onChange starts / stops the recorder
                    Haptics.select()
                } label: {
                    Label(settings.commuteRecording ? "停止记录" : "记录通勤",
                          systemImage: settings.commuteRecording ? "stop.circle.fill" : "record.circle")
                        .symbolEffect(.pulse, options: .repeating, isActive: settings.commuteRecording)
                }
                .glassButton(prominent: settings.commuteRecording)
                .tint(Palette.red)
                .touchTarget()
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { level in
                        LevelMark(level: level, showsName: false)
                    }
                    Text(metric.label).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline, lineWidth: 1))
                .accessibilityLabel("圆点好，方块一般，三角偏高，叉号差")
            }
        }
    }

    private func coord(_ p: CommutePoint) -> CLLocationCoordinate2D { .init(latitude: p.lat, longitude: p.lon) }
    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "–" }
    private func color(for p: CommutePoint) -> Color {
        guard let v = metric.value(p) else { return .gray }
        return Palette.level(metric.level(v))
    }
}
