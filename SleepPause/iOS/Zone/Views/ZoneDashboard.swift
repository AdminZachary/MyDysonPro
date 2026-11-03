import SwiftUI

/// At-a-glance Zone home: breathing air orb, animated noise-dose ring, battery / ANC / wear chips.
/// Every value degrades to "–" and unverified sources carry a badge.
struct ZoneDashboard: View {
    @ObservedObject var zone = ZoneManager.shared
    @ObservedObject var noise = NoiseExposureStore.shared
    @ObservedObject var auto = ZoneAutomations.shared
    var onLogin: () -> Void

    private var snapshot: ZoneSnapshot { auto.currentSnapshot() }

    var body: some View {
        switch zone.state {
        case .needsLogin:
            StatePanel(symbol: "person.badge.key.fill", title: "登录一次就好",
                       message: "用 MyDyson 账号取回 Zone 的蓝牙密钥，只保存在这台 iPhone 的钥匙串里。",
                       actionTitle: "登录 Dyson 账号", action: onLogin).card()
        case .bluetoothOff(let why):
            StatePanel(symbol: "antenna.radiowaves.left.and.right.slash", title: why,
                       message: "到“设置 → 蓝牙”打开蓝牙，并允许 SleepPause 使用蓝牙。", tint: Palette.yellow).card(tint: Palette.yellow)
        case .busyElsewhere:
            StatePanel(symbol: "rectangle.2.swap", title: "Zone 被其他 App 占用",
                       message: "彻底退出 MyDyson（上滑关掉），Zone 同一时间只接受一个控制端。", tint: Palette.yellow).card(tint: Palette.yellow)
        case .failed(let msg):
            StatePanel(symbol: "exclamationmark.triangle.fill", title: "连接失败", message: msg, tint: Palette.red,
                       actionTitle: "重试", action: { zone.bootstrap() }).card(tint: Palette.red)
        case .searching, .connecting, .authenticating, .disabled:
            HStack(spacing: 14) {
                ProgressView()
                VStack(alignment: .leading) {
                    Text(zone.state.label).font(.headline)
                    Text("请打开 Zone 并靠近手机").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "headphones").font(.title).symbolEffect(.variableColor.iterative, options: .repeating)
            }.card()
        case .ready:
            ready
        }
    }

    /// Which quick control is expanded out of its chip (glass morph on iOS 26+).
    private enum Expanded: Hashable { case anc, fan }
    @State private var expanded: Expanded?
    @Namespace private var glassNS

    private var ready: some View {
        let s = snapshot
        let noiseLevel = s.ambientDb.map(ZoneSnapshot.noiseLevel)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AirOrb(level: s.airLevel, label: s.airLevel.map { "空气" + Palette.levelNames[$0] } ?? "空气 –",
                       sublabel: s.no2Ppb.map { String(format: "NO₂ %.0f ppb", $0) })
                Spacer(minLength: 8)
                DoseBar(percent: noise.today.dosePercent).frame(maxWidth: 180)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.ambientDb.map { String(format: "%.0f", $0) } ?? "–")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("dB 环境").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                LevelMark(level: noiseLevel)
                Spacer(minLength: 8)
                if !s.layoutVerified && (s.ambientDb != nil || s.airLevel != nil) { UnverifiedBadge(text: "201D 未验证") }
            }
            // Controls only: glass buttons. Status chips stay flat.
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(symbol: batterySymbol(s.battery), text: s.batteryText,
                             tint: (s.battery ?? 100) <= 20 ? Palette.red : Palette.blue)
                        Button { toggle(.anc) } label: {
                            Chip(symbol: "waveform.circle", text: s.ancLabel ?? "降噪 –", tint: Palette.blue)
                                .touchTarget()
                        }
                        .buttonStyle(.plain).glassID("anc", in: glassNS)
                        .accessibilityHint("展开降噪模式")
                        Button { toggle(.fan) } label: {
                            Chip(symbol: "fan", text: zone.fanActual.map { "风扇 \($0)" } ?? "风扇 –", tint: Palette.blue)
                                .touchTarget()
                        }
                        .buttonStyle(.plain).glassID("fan", in: glassNS)
                        .accessibilityHint("展开风扇档位")
                        if let w = s.worn {
                            Chip(symbol: w ? "checkmark" : "xmark", text: w ? "已佩戴*" : "未佩戴*", tint: Palette.secondaryInk)
                        }
                        if let f = s.focusPhase { Chip(symbol: "timer", text: f, tint: Palette.blue) }
                    }
                    .padding(.vertical, 2)
                }
                if expanded == .anc {
                    controlGrid(glassID: "anc.menu") {
                        ForEach(ZoneANCMode.allCases, id: \.self) { m in
                            Button(m.label) { zone.setANC(m, manual: true); Haptics.select(); toggle(nil) }
                                .glassButton(prominent: zone.ancMode == m)
                                .tint(Palette.blue)
                                .touchTarget()
                        }
                    }
                }
                if expanded == .fan {
                    controlGrid(glassID: "fan.menu") {
                        ForEach(0..<4, id: \.self) { l in
                            Button(["关", "静息", "轻度", "中度"][l]) { ZoneAutomations.shared.userSetFan(l); Haptics.select(); toggle(nil) }
                                .glassButton(prominent: zone.fanSpeed == l)
                                .tint(Palette.blue)
                                .touchTarget()
                        }
                    }
                }
            }
            if s.worn != nil { Text("* 佩戴状态来自未验证的 2004 字段").font(.caption2).foregroundStyle(Palette.secondaryInk) }
            if let n = auto.lastBoostNote { Text(n).font(.caption).foregroundStyle(Palette.secondaryInk) }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func controlGrid<Content: View>(glassID: String, @ViewBuilder content: () -> Content) -> some View {
        GlassGroup(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                content()
            }
            .glassID(glassID, in: glassNS)
        }
    }

    private func toggle(_ e: Expanded?) {
        withAnimation(.bouncy) { expanded = (e == nil || expanded == e) ? nil : e }
        Haptics.tap()
    }

    private func batterySymbol(_ b: Int?) -> String {
        guard let b else { return "battery.0percent" }
        return b > 75 ? "battery.100percent" : b > 50 ? "battery.75percent" : b > 25 ? "battery.50percent" : "battery.25percent"
    }
}
