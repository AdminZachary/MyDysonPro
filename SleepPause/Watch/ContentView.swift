import SwiftUI

/// Bedtime-first watch UI: calm dark gradient, a live stillness ring and a heart-rate-vs-target bar.
struct ContentView: View {
    @EnvironmentObject var monitor: SleepMonitor
    @EnvironmentObject var settings: SleepSettings

    var body: some View {
        NavigationStack {
            Group {
                if monitor.alarmFiring { WakeView() }
                else if monitor.isRunning || isDetected { BedtimeView() }
                else { IdleView() }
            }
            .containerBackground(for: .navigation) {
                LinearGradient(colors: [Color.indigo, Color.black], startPoint: .top, endPoint: .bottom)
            }
            .foregroundStyle(.primary)
            .tint(.indigo)
        }
    }

    private var isDetected: Bool { if case .detected = monitor.state { return true }; return false }
}

struct IdleView: View {
    @EnvironmentObject var monitor: SleepMonitor
    @EnvironmentObject var settings: SleepSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                if case .error(let msg) = monitor.state {
                    Text(msg).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button { monitor.start() } label: {
                    Label("开始今晚监测", systemImage: "bed.double.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .watchGlassButton(prominent: true)
                .tint(.indigo)
                NavigationLink { AlarmSettingsView() } label: {
                    Label(settings.alarm.enabled ? String(format: "智能闹钟 %02d:%02d", settings.alarm.hour, settings.alarm.minute) : "智能闹钟：关",
                          systemImage: settings.alarm.enabled ? "alarm.fill" : "alarm")
                }
                Button("测试暂停 iPhone 音乐") { monitor.sendTest() }.font(.footnote)
                NavigationLink("阈值设置") { SettingsView() }.font(.footnote)
            }
        }
        .navigationTitle("SleepPause")
    }
}

/// Calm, dim, glanceable. The ring fills as you stay still; the bar shows heart rate vs the target.
struct BedtimeView: View {
    @EnvironmentObject var monitor: SleepMonitor
    @EnvironmentObject var settings: SleepSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                VStack(spacing: 2) {
                    Text("\(Int(monitor.status?.stillMinutes ?? 0))")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("/ \(Int(settings.stillMinutes)) 静止分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: isMoving ? "figure.walk" : "moon.zzz.fill")
                            .foregroundStyle(isMoving ? Color.red : Color.indigo)
                        Text(isMoving ? "在动" : "静止")
                            .font(.caption2.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.indigo).frame(width: max(8, geo.size.width * stillFraction))
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("静止进度")
                heartBar
                if let a = monitor.alarmDeadline {
                    Label("\(a.addingTimeInterval(-settings.alarm.windowMinutes * 60).formatted(date: .omitted, time: .shortened))–\(a.formatted(date: .omitted, time: .shortened)) 叫醒",
                          systemImage: "alarm").font(.caption2).foregroundStyle(.secondary)
                }
                Button(role: .destructive) { monitor.stop() } label: {
                    Text("停止监测").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var header: some View {
        switch monitor.state {
        case .detected(let d):
            Label("已入睡 \(d.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.seal.fill")
                .font(.footnote).foregroundStyle(.indigo)
        default:
            if case .collectingBaseline? = monitor.status?.phase {
                Text("采集清醒心率基线…").font(.footnote).foregroundStyle(.indigo)
            } else {
                Text("监测中 · 放轻松").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var stillFraction: Double {
        min(1, (monitor.status?.stillMinutes ?? 0) / max(1, settings.stillMinutes))
    }
    private var isMoving: Bool { (monitor.movement ?? 0) > settings.movementThresholdG }

    /// Heart rate relative to the sleep target (baseline × (1 − drop %)).
    private var heartBar: some View {
        let base = monitor.status?.baselineHR
        let cur = monitor.status?.currentHR ?? monitor.lastHR
        let target = base.map { $0 * (1 - settings.hrDropPercent / 100) }
        let met = monitor.status?.hrConditionMet ?? false
        return VStack(spacing: 3) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(.indigo)
                Text(cur.map { "\(Int($0))" } ?? "–").font(.headline).monospacedDigit()
                Text(target.map { "目标 ≤\(Int($0))" } ?? "基线采集中").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: met ? "checkmark.circle.fill" : "circle.dotted").foregroundStyle(met ? Color.indigo : Color.secondary)
            }
            GeometryReader { g in
                let lo = (target ?? 50) - 15, hi = (base ?? 80) + 10
                let x = cur.map { CGFloat(($0 - lo) / max(1, hi - lo)) } ?? 0
                let tx = target.map { CGFloat(($0 - lo) / max(1, hi - lo)) } ?? 0.5
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.indigo).frame(width: max(6, min(1, max(0, x)) * g.size.width))
                    Rectangle().fill(.primary).frame(width: 2).offset(x: min(1, max(0, tx)) * g.size.width)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct WakeView: View {
    @EnvironmentObject var monitor: SleepMonitor
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(.orange).accessibilityHidden(true)
            Text("早上好").font(.title2.bold())
            Text("在浅睡时叫醒你").font(.footnote).foregroundStyle(.secondary)
            Button { monitor.dismissAlarm() } label: {
                Text("我醒了").frame(maxWidth: .infinity, minHeight: 44)
            }
            .watchGlassButton(prominent: true)
            .tint(.indigo)
        }
    }
}

struct AlarmSettingsView: View {
    @EnvironmentObject var settings: SleepSettings
    var body: some View {
        Form {
            Toggle("智能闹钟", isOn: $settings.alarm.enabled)
            if settings.alarm.enabled {
                Stepper(String(format: "%02d 点", settings.alarm.hour), value: $settings.alarm.hour, in: 0...23)
                Stepper(String(format: "%02d 分", settings.alarm.minute), value: $settings.alarm.minute, in: 0...55, step: 5)
                Stepper("窗口 \(Int(settings.alarm.windowMinutes)) 分", value: $settings.alarm.windowMinutes, in: 10...60, step: 5)
                Toggle("窗口内每 5 分钟轻拍", isOn: Binding(get: { settings.alarm.gentleTapMinutes != nil },
                                                    set: { settings.alarm.gentleTapMinutes = $0 ? 5 : nil }))
                Text("在窗口内检测到持续翻身/活动（约 1.5 分钟）就用轻柔震动叫醒；最晚在设定时间叫醒。开启后监测会持续整晚，更耗电。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("智能闹钟")
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SleepSettings

    var body: some View {
        Form {
            Stepper("静止 \(Int(settings.stillMinutes)) 分钟", value: $settings.stillMinutes, in: 3...45, step: 1)
            Stepper("心率下降 \(Int(settings.hrDropPercent))%", value: $settings.hrDropPercent, in: 0...30, step: 1)
            Stepper("基线 \(Int(settings.baselineMinutes)) 分钟", value: $settings.baselineMinutes, in: 2...15, step: 1)
            Stepper("动作阈值 \(String(format: "%.3f", settings.movementThresholdG)) g",
                    value: $settings.movementThresholdG, in: 0.005...0.1, step: 0.005)
            Toggle("需要心率条件", isOn: $settings.requireHeartRate)
            Toggle("检测后结束会话", isOn: $settings.endSessionAfterDetection)
            Button("恢复默认") { settings.resetToDefaults() }
            Text("修改在下次开始监测时生效。开启智能闹钟时，会话会持续到早上。").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("设置")
    }
}


// MARK: - Liquid Glass on watchOS 26+ (fallbacks for watchOS 10–25)
// watchOS 26 already renders standard buttons / lists / toolbars as glass; these helpers only add the
// prominent variant for the one primary action and a clear lens for the heart-rate panel.
extension View {
    @ViewBuilder
    func watchGlassButton(prominent: Bool) -> some View {
        if #available(watchOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    @ViewBuilder
    func watchGlass() -> some View {
        if #available(watchOS 26.0, *) {
            glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
        }
    }
}
