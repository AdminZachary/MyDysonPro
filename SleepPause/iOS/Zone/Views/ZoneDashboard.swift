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
                       message: "到“设置 → 蓝牙”打开蓝牙，并允许 SleepPause 使用蓝牙。", tint: .orange).card(tint: .orange)
        case .busyElsewhere:
            StatePanel(symbol: "rectangle.2.swap", title: "Zone 被其他 App 占用",
                       message: "彻底退出 MyDyson（上滑关掉），Zone 同一时间只接受一个控制端。", tint: .orange).card(tint: .orange)
        case .failed(let msg):
            StatePanel(symbol: "exclamationmark.triangle.fill", title: "连接失败", message: msg, tint: .red,
                       actionTitle: "重试", action: { zone.bootstrap() }).card(tint: .red)
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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                BreathingOrb(level: s.airLevel, label: s.airLevel.map { "空气" + Palette.levelNames[$0] } ?? "空气 –",
                             sublabel: s.no2Ppb.map { String(format: "NO₂ %.0f ppb", $0) })
                Spacer(minLength: 0)
                DoseRing(percent: noise.today.dosePercent)
            }
            HStack(spacing: 8) {
                Image(systemName: "ear").foregroundStyle(.white)
                Text(s.ambientDb.map { String(format: "环境 %.0f dB", $0) } ?? "环境噪音 –")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                if let noiseLevel { Circle().fill(Palette.level(noiseLevel)).frame(width: 8, height: 8) }
                Spacer()
                if !s.layoutVerified && (s.ambientDb != nil || s.airLevel != nil) { UnverifiedBadge(text: "201D 未验证") }
            }
            .foregroundStyle(.white)
            // Functional layer: all chips + quick controls share ONE glass container so they
            // sample the same backdrop and can merge / split.
            GlassGroup(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(symbol: batterySymbol(s.battery), text: s.batteryText,
                                 tint: (s.battery ?? 100) <= 20 ? .red : .green)
                            Button { toggle(.anc) } label: {
                                Chip(symbol: "waveform.circle", text: s.ancLabel ?? "降噪 –", tint: .indigo)
                            }
                            .buttonStyle(.plain).glassID("anc", in: glassNS)
                            .accessibilityHint("展开降噪模式")
                            Button { toggle(.fan) } label: {
                                Chip(symbol: "fan", text: zone.fanActual.map { "风扇 \($0)" } ?? "风扇 –", tint: .teal)
                            }
                            .buttonStyle(.plain).glassID("fan", in: glassNS)
                            .accessibilityHint("展开风扇档位")
                            if let w = s.worn {
                                Chip(symbol: w ? "person.fill.checkmark" : "person.fill.xmark", text: w ? "已佩戴*" : "未佩戴*", tint: .gray)
                            }
                            if let f = s.focusPhase { Chip(symbol: "timer", text: f, tint: Palette.focus) }
                        }
                        .padding(.vertical, 2)
                    }
                    if expanded == .anc {
                        HStack(spacing: 8) {
                            ForEach(ZoneANCMode.allCases, id: \.self) { m in
                                Button(m.label) { zone.setANC(m, manual: true); Haptics.select(); toggle(nil) }
                                    .glassButton(prominent: zone.ancMode == m)
                                    .tint(.indigo)
                            }
                        }
                        .glassID("anc.menu", in: glassNS)
                        .transition(.blurReplace)
                    }
                    if expanded == .fan {
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { l in
                                Button(["关", "静息", "轻度", "中度"][l]) { ZoneAutomations.shared.userSetFan(l); Haptics.select(); toggle(nil) }
                                    .glassButton(prominent: zone.fanSpeed == l)
                                    .tint(.teal)
                            }
                        }
                        .glassID("fan.menu", in: glassNS)
                        .transition(.blurReplace)
                    }
                }
            }
            if s.worn != nil { Text("* 佩戴状态来自未验证的 2004 字段").font(.caption2).foregroundStyle(.white.opacity(0.75)) }
            if let n = auto.lastBoostNote { Label(n, systemImage: "wind").font(.caption).foregroundStyle(.white.opacity(0.8)) }
        }
        .padding(16)
        // Content layer (not glass): a vivid air-level gradient the glass chips can refract.
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.levelBackdrop(s.airLevel)))
        .environment(\.colorScheme, .dark)      // white text on the vivid backdrop in light mode too
        .animation(.smooth, value: s.airLevel)
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
