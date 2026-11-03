import SwiftUI

/// Sleep tab, in the Health Sleep style: inset grouped list, indigo symbols,
/// a large title, and one primary action in the bottom safe area.
/// Armed nights dim the system dark appearance instead of swapping in a custom palette.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var extras = SleepExtrasStore.shared
    @ObservedObject var sounds = SleepSoundPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAchievements = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section { hero }
                if let m = extras.morning, Date().timeIntervalSince(m.wake) < 18 * 3600 {
                    Section { MorningCard(summary: m) }
                }
                Section { SleepSoundsCard() }
                Section { NoiseDoseCard() }
                Section {
                    SleepOnsetChart(onsets: extras.recentOnsets)
                } header: {
                    Label("入睡时刻", systemImage: "moon.zzz.fill").foregroundStyle(.indigo)
                }
                Section { streakStrip }
                Section { testCard }
                Section { optionsCard.id("headphones") }
                Section { watchCard }
                Section { logCard }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("睡眠")
            .navigationBarTitleDisplayMode(.large)
            .nightBackdrop()
            .tint(.indigo)
            .minimizingNavigationBar()
            .safeAreaInset(edge: .bottom, spacing: 0) { primaryAction }
            .brightness(model.isArmed ? -0.08 : 0)
            .onAppear {
                model.refreshWatchState()
                extras.refreshAchievements(notify: false)
                guard ScreenshotMode.screen == "headphones" else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo("headphones", anchor: .top)
                }
            }
            .sheet(isPresented: $showAchievements) { AchievementsView() }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.35), trigger: extras.justUnlocked)
            }
        }
        .modifier(SleepAppearance())
        .animation(reduceMotion ? nil : .smooth, value: model.isArmed)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("睡眠", systemImage: model.isArmed ? "moon.zzz.fill" : "bed.double.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(model.isArmed ? "守候中" : "准备好了")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(model.isArmed ? "睡着后自动暂停播放，降噪保持开启" : "戴上手表，点下面的开始，安心入睡")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onset = model.lastOnset {
                Label("上次入睡 \(onset.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryAction: some View {
        Button {
            if model.isArmed { model.stopTonight(); Haptics.night() }
            else { Task { await model.startTonight(); Haptics.night() } }
        } label: {
            Label(model.isArmed ? "停止守候" : "开始今晚（同时启动手表）",
                  systemImage: model.isArmed ? "stop.fill" : "bed.double.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .glassButton(prominent: true)
        .tint(model.isArmed ? .red : .indigo)
        .touchTarget()
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityHint(model.isArmed ? "结束今晚的入睡监测" : "开始今晚的入睡监测，降噪保持开启")
    }

    private var streakStrip: some View {
        Button { showAchievements = true; Haptics.night() } label: {
            HStack(alignment: .top, spacing: 12) {
                ForEach(StreakKind.allCases, id: \.self) { k in
                    let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(k.label, systemImage: k.symbol)
                            .font(.caption)
                            .foregroundStyle(k == .focus ? Color.orange : Color.indigo)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel(k.label)
                        Text("\(s.current)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(k.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .touchTarget()
        .accessibilityLabel("连续天数与成就")
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("测试").font(.headline)
            Text("先用音乐通过耳机播放，再试一次，确认会停。")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("立即测试暂停") { model.testPauseNow(); Haptics.night() }
                .buttonStyle(.bordered).tint(.indigo).touchTarget()
            Button("20 秒后测试（先锁屏再等）") { model.testPauseLater(); Haptics.night() }
                .buttonStyle(.bordered).touchTarget()
        }
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选项").font(.headline)
            HeadphonePicker()
            Toggle("同时直接暂停 Apple Music", isOn: $model.pauseAppleMusic)
            Button("授权 Apple Music 控制") { model.requestMusicAuthorization(); Haptics.night() }
                .touchTarget()
            Toggle("把入睡时间写入“健康”", isOn: $model.writeToHealth)
            Button("授权健康数据") { Task { await model.requestHealthAuthorization() }; Haptics.night() }
                .touchTarget()
        }
    }

    private var watchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Watch", systemImage: "applewatch")
                .font(.headline)
                .foregroundStyle(.indigo)
            status("已配对", model.watchPaired)
            status("手表 App 已安装", model.watchAppInstalled)
            status("当前可直连", model.watchReachable)
            Button("刷新") { model.refreshWatchState(); Haptics.night() }.touchTarget()
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志").font(.headline)
                Spacer()
                Button("清空") { model.clearLog(); Haptics.night() }.font(.subheadline).touchTarget()
            }
            if model.log.isEmpty {
                Text("还没有记录。今晚点下面的开始试试。").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.log) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text(e.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func status(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color.indigo : Color.secondary)
                .accessibilityLabel(ok ? "是" : "否")
        }
    }
}

/// Health Sleep is dark. Screenshot runs of the other screens keep the simulator appearance.
private struct SleepAppearance: ViewModifier {
    func body(content: Content) -> some View {
        if ScreenshotMode.isActive && ScreenshotMode.screen != "sleep" {
            content
        } else {
            content.preferredColorScheme(.dark)
        }
    }
}

struct MorningCard: View {
    var summary: MorningSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("早上好", systemImage: "sun.max.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack {
                Text(summary.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let r = summary.latencyRating {
                    Text(r)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }
            ForEach(summary.lines, id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if summary.noiseLeq != nil && !summary.noiseVerified { UnverifiedBadge(text: "噪音来自未验证的 201D") }
        }
    }
}

struct SleepSoundsCard: View {
    @ObservedObject var sounds = SleepSoundPlayer.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("助眠声音", systemImage: sounds.color.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Text(sounds.color.label)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(sounds.isFading ? "正在淡出…" : sounds.isPlaying ? "播放中，睡着后自动淡出" : "实时生成，不循环")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    sounds.isPlaying ? sounds.fadeOutAndStop(seconds: 3) : sounds.start()
                    Haptics.night()
                } label: {
                    Image(systemName: sounds.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.indigo)
                .accessibilityLabel(sounds.isPlaying ? "停止助眠声音" : "播放助眠声音")
            }
            Picker("声音", selection: $sounds.color) {
                ForEach(NoiseColor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $sounds.volume, in: 0.05...0.8)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Stepper("入睡后 \(Int(sounds.fadeSeconds)) 秒淡出", value: $sounds.fadeSeconds, in: 15...600, step: 15)
                .font(.subheadline)
            Picker("没检测到入睡时", selection: $sounds.timerMinutes) {
                Text("一直播放").tag(0.0)
                Text("30 分钟后淡出").tag(30.0)
                Text("60 分钟").tag(60.0)
                Text("90 分钟").tag(90.0)
            }
            .font(.subheadline)
        }
    }
}

struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var extras = SleepExtrasStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StreakKind.allCases, id: \.self) { k in
                        let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                        HStack {
                            Label(k.label, systemImage: k.symbol)
                                .foregroundStyle(k == .focus ? Color.orange : Color.indigo)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(s.current) 天")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                Text("最长 \(s.best) 天")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("成就") {
                    ForEach(Achievement.allCases, id: \.self) { a in
                        let date = extras.unlocked[a]
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: a.symbol)
                                .font(.title3)
                                .foregroundStyle(date == nil ? Color.secondary : Color.indigo)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title).font(.headline)
                                Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                if a.usesUnverifiedData { UnverifiedBadge() }
                                if let date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .opacity(date == nil ? 0.7 : 1)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Text("清新通勤依赖未验证的 201D 读数；读不到时只是不会解锁。安静日用耳机播放音量或环境噪音，不需要 Zone。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("连续与成就")
            .navigationBarTitleDisplayMode(.large)
            .tint(.indigo)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.touchTarget() } }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}

struct NoiseDoseCard: View {
    @ObservedObject var noise = NoiseExposureStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoseBar(percent: noise.mergedToday.isEmpty ? nil : noise.mergedDosePercent)
            Text(LevelPalette.loudLabel(noise.mergedToday.map(\.leq).max()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(noise.doseCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NoiseTrendChart(minutes: noise.mergedToday)
            Text(NoiseMerge.rule)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let aside = noise.zoneAmbientAside {
                Text(aside)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if noise.mergedToday.contains(where: { $0.origin == .zone }) {
                UnverifiedBadge(text: "Zone 环境读数未验证")
            }
        }
        .task { await noise.refreshHealth() }
    }
}

struct HeadphonePicker: View {
    @ObservedObject private var headphones = HeadphoneSettings.shared
    var suggested: HeadphoneKind? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("我的耳机", systemImage: "headphones")
                .font(.headline)
                .foregroundStyle(.indigo)
            if let suggested, suggested != headphones.kind {
                Button("检测到\(suggested.title)，用这个建议") {
                    headphones.kind = suggested
                    Haptics.select()
                }
                .buttonStyle(.bordered)
                .touchTarget()
            }
            ForEach(HeadphoneKind.allCases, id: \.self) { kind in
                Button {
                    headphones.kind = kind
                    Haptics.select()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: headphones.kind == kind ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(headphones.kind == kind ? Color.indigo : Color.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.body.weight(.semibold))
                            Text(kind.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .touchTarget()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
