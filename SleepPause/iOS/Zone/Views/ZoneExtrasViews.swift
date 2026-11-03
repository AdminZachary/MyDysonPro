import SwiftUI

/// Settings for the extras, shown inside the Zone tab.
struct ZoneExtrasSection: View {
    @ObservedObject var settings = ZoneSettings.shared
    @ObservedObject var auto = ZoneAutomations.shared
    @ObservedObject var live = LiveActivityController.shared
    @State private var showReport = false

    var body: some View {
        Section {
            Toggle("污染时自动加大风扇（201D 未验证）", isOn: $settings.fanBoostEnabled)
            if settings.fanBoostEnabled {
                Stepper(String(format: "NO₂ ≥ %.0f ppb 时加速", settings.fanBoost.no2HighPpb),
                        value: $settings.fanBoost.no2HighPpb, in: 25...200, step: 5)
                Stepper(String(format: "VOC ≥ %.0f ppb 时加速", settings.fanBoost.vocHighPpb),
                        value: $settings.fanBoost.vocHighPpb, in: 200...2000, step: 50)
                Picker("加速到", selection: $settings.fanBoost.boostLevel) {
                    Text("轻度").tag(2); Text("中度").tag(3)
                }.pickerStyle(.segmented)
                if let n = auto.lastBoostNote { Text(n).font(.caption).foregroundStyle(.secondary) }
            }
        } header: { Text("污染加速") } footer: {
            Text("持续 20 秒超标才加速，空气恢复 20 秒且至少加速 2 分钟后调回原档位；你手动调风扇后以你的为准。面罩没装上、睡眠监测期间不会加速，也不会动降噪。")
        }

        Section {
            Toggle("电量低于 20% / 10% 时通知", isOn: $settings.batteryAlerts)
            Toggle("实时活动跟随专注自动开启", isOn: $settings.liveActivityAuto)
            if live.isRunning {
                Button("关闭实时活动 / 灵动岛") { live.stop() }
            } else {
                Button("在锁屏和灵动岛显示空气与噪音") { auto.startLiveActivity() }
            }
            if let e = live.lastError { Text(e).font(.caption).foregroundStyle(.red) }
            Toggle("每周一 9:00 推送上周报告", isOn: $settings.weeklyReport)
            Button("查看上周报告") { _ = auto.buildLastWeek(); showReport = true }
        } header: { Text("提醒、实时活动与周报") } footer: {
            Text("小组件：长按主屏幕或锁屏 → 添加小组件 → SleepPause。")
        }
        .sheet(isPresented: $showReport) { WeeklyReportView(report: auto.lastReport) }
    }
}

struct WeeklyReportView: View {
    @Environment(\.dismiss) private var dismiss
    var report: WeeklyReport?

    var body: some View {
        NavigationStack {
            List {
                if let r = report, !r.isEmpty {
                    Section("概要") { ForEach(r.summaryLines(), id: \.self) { Text($0) } }
                    if !r.days.isEmpty {
                        Section("每日噪音剂量") {
                            ForEach(r.days, id: \.day) { d in
                                HStack {
                                    Text(d.day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                                    ProgressView(value: min(d.dosePercent, 200), total: 200)
                                    Text(String(format: "%.0f%%", d.dosePercent)).monospacedDigit()
                                }
                            }
                        }
                    }
                } else {
                    Text("上周还没有数据。连上 Zone、用几天后再来看。").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("上周报告")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct FocusView: View {
    @ObservedObject var focus = FocusManager.shared
    @ObservedObject var settings = ZoneSettings.shared
    @ObservedObject var zone = ZoneManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let rem = Int(focus.session.remaining(at: ctx.date))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(focus.session.isPaused ? "\(focus.session.phase.label)（暂停）" : focus.session.phase.label)
                                .font(.headline)
                            Text(String(format: "%02d:%02d", rem / 60, rem % 60))
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text("已完成 \(focus.session.completedFocusCycles) 个番茄 · 今天专注 \(Int(focus.todayMinutes)) 分钟")
                                .font(.caption).foregroundStyle(Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !zone.isReady {
                        Text("Zone 未连接：计时照常进行，只是不会切换降噪/风扇。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("设置") {
                    Stepper("专注 \(Int(settings.focus.focusMinutes)) 分钟", value: $settings.focus.focusMinutes, in: 5...90, step: 5)
                    Stepper("短休息 \(Int(settings.focus.shortBreakMinutes)) 分钟", value: $settings.focus.shortBreakMinutes, in: 1...30)
                    Stepper("长休息 \(Int(settings.focus.longBreakMinutes)) 分钟", value: $settings.focus.longBreakMinutes, in: 5...45, step: 5)
                    Stepper("每 \(settings.focus.cyclesBeforeLongBreak) 个番茄长休息一次", value: $settings.focus.cyclesBeforeLongBreak, in: 2...8)
                    Picker("专注时", selection: $settings.focus.focusANC) {
                        ForEach(ZoneANCMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("休息时", selection: $settings.focus.breakANC) {
                        ForEach(ZoneANCMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("专注时风扇", selection: $settings.focus.focusFanLevel) {
                        Text("不改变").tag(Int?.none)
                        ForEach(0..<4) { Text(["关", "静息", "轻度", "中度"][$0]).tag(Int?.some($0)) }
                    }
                    Toggle("摘下耳机时暂停计时（2004 未验证）", isOn: $settings.focus.pauseWhenUnworn)
                }
                Section {
                    Text("专注期间暂停自动降噪切换；睡眠监测期间不能开始专注，开始“今晚监测”会自动结束专注。也可以在快捷指令里用“开始 Zone 专注”，配合系统的专注模式自动化。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("专注")
            .paperBackdrop(Palette.blue)
            .safeAreaInset(edge: .bottom, spacing: 0) { focusActions }
        }
    }

    /// One primary control in the thumb zone. Ending the session is a separate destructive button.
    private var focusActions: some View {
        VStack(spacing: 8) {
            if focus.session.isActive {
                Button(role: .destructive) { focus.stop(); Haptics.warning() } label: {
                    Label("结束", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .touchTarget()
            }
            Button {
                if focus.session.isActive { focus.togglePause(); Haptics.tap() }
                else { focus.start() }
            } label: {
                Label(focus.session.isActive ? (focus.session.isPaused ? "继续" : "暂停") : "开始专注",
                      systemImage: focus.session.isActive ? (focus.session.isPaused ? "play.fill" : "pause.fill") : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .glassButton(prominent: true)
            .tint(Palette.blue)
            .touchTarget()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.canvas)
    }
}
