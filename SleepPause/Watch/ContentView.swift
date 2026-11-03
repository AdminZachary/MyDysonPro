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
            .containerBackground(WatchPalette.night.gradient, for: .navigation)
        }
    }

    private var isDetected: Bool { if case .detected = monitor.state { return true }; return false }
}

enum WatchPalette {
    static let night = Color(red: 0.06, green: 0.06, blue: 0.18)
    static let moon = Color(red: 0.78, green: 0.80, blue: 1.00)
    static let still = Color(red: 0.45, green: 0.55, blue: 1.00)
    static let heart = Color(red: 0.98, green: 0.40, blue: 0.50)
}

struct IdleView: View {
    @EnvironmentObject var monitor: SleepMonitor
    @EnvironmentObject var settings: SleepSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").font(.system(size: 40)).foregroundStyle(WatchPalette.moon)
                    .symbolEffect(.pulse, options: .repeating)
                if case .error(let msg) = monitor.state {
                    Text(msg).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button { monitor.start() } label: {
                    Label("开始今晚监测", systemImage: "bed.double.fill").frame(maxWidth: .infinity)
                }
                .watchGlassButton(prominent: true)
                .tint(WatchPalette.still)
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
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: stillFraction)
                        .stroke(WatchPalette.still.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.2), value: stillFraction)
                    VStack(spacing: 0) {
                        Image(systemName: isMoving ? "figure.wave" : "moon.zzz.fill")
                            .foregroundStyle(isMoving ? .orange : WatchPalette.moon)
                            .symbolEffect(.pulse, options: .repeating, isActive: !isMoving)
                            .contentTransition(.symbolEffect(.replace))
                        Text("\(Int(monitor.status?.stillMinutes ?? 0))/\(Int(settings.stillMinutes))")
                            .font(.title3.bold()).monospacedDigit()
                        Text("静止分钟").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                heartBar
                if let a = monitor.alarmDeadline {
                    Label("\(a.addingTimeInterval(-settings.alarm.windowMinutes * 60).formatted(date: .omitted, time: .shortened))–\(a.formatted(date: .omitted, time: .shortened)) 叫醒",
                          systemImage: "alarm").font(.caption2).foregroundStyle(.secondary)
                }
                Button(role: .destructive) { monitor.stop() } label: { Text("停止监测") }
                    .watchGlassButton(prominent: false)       // untinted glass: calm at night
                    .font(.footnote).padding(.top, 4)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    @ViewBuilder private var header: some View {
        switch monitor.state {
        case .detected(let d):
            Label("已入睡 \(d.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.seal.fill")
                .font(.footnote).foregroundStyle(WatchPalette.moon)
        default:
            if case .collectingBaseline? = monitor.status?.phase {
                Text("采集清醒心率基线…").font(.footnote).foregroundStyle(.yellow)
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
                Image(systemName: "heart.fill").foregroundStyle(WatchPalette.heart)
                    .symbolEffect(.pulse, options: .repeating.speed(0.6))
                Text(cur.map { "\(Int($0))" } ?? "–").font(.headline).monospacedDigit()
                Text(target.map { "目标 ≤\(Int($0))" } ?? "基线采集中").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: met ? "checkmark.circle.fill" : "circle.dotted").foregroundStyle(met ? .green : .secondary)
            }
            GeometryReader { g in
                let lo = (target ?? 50) - 15, hi = (base ?? 80) + 10
                let x = cur.map { CGFloat(($0 - lo) / max(1, hi - lo)) } ?? 0
                let tx = target.map { CGFloat(($0 - lo) / max(1, hi - lo)) } ?? 0.5
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(WatchPalette.heart.opacity(0.7)).frame(width: max(6, min(1, max(0, x)) * g.size.width))
                    Rectangle().fill(.white).frame(width: 2).offset(x: min(1, max(0, tx)) * g.size.width)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .watchGlass()                                       // clear glass lens, barely there on the dark bedtime screen
        .accessibilityElement(children: .combine)
    }
}

struct WakeView: View {
    @EnvironmentObject var monitor: SleepMonitor
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 44)).foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeating)
            Text("早上好").font(.title2.bold())
            Text("在浅睡时叫醒你").font(.footnote).foregroundStyle(.secondary)
            Button { monitor.dismissAlarm() } label: { Text("我醒了").frame(maxWidth: .infinity) }
                .watchGlassButton(prominent: true)
                .tint(.orange)
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
