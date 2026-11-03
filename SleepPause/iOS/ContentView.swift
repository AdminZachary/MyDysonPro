import SwiftUI

/// Sleep tab. Always the warm night palette: dim paper, amber accent, no blue-white.
/// The one primary action sits in the bottom thumb zone.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var extras = SleepExtrasStore.shared
    @ObservedObject var sounds = SleepSoundPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAchievements = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if let m = extras.morning, Date().timeIntervalSince(m.wake) < 18 * 3600 {
                        MorningCard(summary: m)
                    }
                    SleepSoundsCard()
                    streakStrip
                    testCard
                    optionsCard
                    watchCard
                    logCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle("SleepPause")
            .nightBackdrop()
            .foregroundStyle(Night.ink)
            .tint(Night.accent)
            .toolbarBackground(Night.ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .minimizingNavigationBar()
            .safeAreaInset(edge: .bottom, spacing: 0) { primaryAction }
            .onAppear { model.refreshWatchState(); extras.refreshAchievements(notify: false) }
            .sheet(isPresented: $showAchievements) { AchievementsView() }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.35), trigger: extras.justUnlocked)
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isArmed ? "守候中" : "今晚")
                        .font(.largeTitle.weight(.bold))
                    Text(model.isArmed ? "睡着后自动暂停播放，降噪保持开启" : "戴上手表，点下面的开始，安心入睡")
                        .font(.body)
                        .foregroundStyle(Night.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Circle()
                    .fill(model.isArmed ? Night.accent : Night.surface)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Night.accent, lineWidth: 2))
                    .accessibilityHidden(true)
            }
            if let onset = model.lastOnset {
                Label("上次入睡 \(onset.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Night.muted)
            }
        }
        .nightCard()
        .animation(reduceMotion ? nil : .smooth, value: model.isArmed)
    }

    private var primaryAction: some View {
        VStack(spacing: 0) {
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
            .buttonStyle(.borderedProminent)
            .tint(model.isArmed ? Night.danger : Night.accent)
            .foregroundStyle(Night.onAccent)
            .touchTarget()
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Night.ground)
            .accessibilityHint(model.isArmed ? "结束今晚的入睡监测" : "开始今晚的入睡监测，降噪保持开启")
        }
    }

    private var streakStrip: some View {
        Button { showAchievements = true; Haptics.night() } label: {
            HStack(alignment: .top, spacing: 12) {
                ForEach(StreakKind.allCases, id: \.self) { k in
                    let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: k.symbol).font(.body)
                            .foregroundStyle(s.current > 0 ? Night.accent : Night.muted)
                        Text("\(s.current)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(k.label + (k.usesUnverifiedData ? "*" : ""))
                            .font(.caption2)
                            .foregroundStyle(Night.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right").foregroundStyle(Night.muted).padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .touchTarget()
        .nightCard()
        .accessibilityLabel("连续天数与成就")
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("测试").font(.headline)
            Text("先用音乐通过耳机播放，再试一次，确认会停。")
                .font(.footnote).foregroundStyle(Night.muted)
            Button("立即测试暂停") { model.testPauseNow(); Haptics.night() }
                .buttonStyle(.bordered).tint(Night.accent).touchTarget()
            Button("20 秒后测试（先锁屏再等）") { model.testPauseLater(); Haptics.night() }
                .buttonStyle(.bordered).tint(Night.muted).touchTarget()
        }
        .nightCard()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选项").font(.headline)
            Toggle("同时直接暂停 Apple Music", isOn: $model.pauseAppleMusic)
            Button("授权 Apple Music 控制") { model.requestMusicAuthorization(); Haptics.night() }
                .touchTarget()
            Toggle("把入睡时间写入“健康”", isOn: $model.writeToHealth)
            Button("授权健康数据") { Task { await model.requestHealthAuthorization() }; Haptics.night() }
                .touchTarget()
        }
        .nightCard()
    }

    private var watchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Watch").font(.headline)
            status("已配对", model.watchPaired)
            status("手表 App 已安装", model.watchAppInstalled)
            status("当前可直连", model.watchReachable)
            Button("刷新") { model.refreshWatchState(); Haptics.night() }.touchTarget()
        }
        .nightCard()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志").font(.headline)
                Spacer()
                Button("清空") { model.clearLog(); Haptics.night() }.font(.subheadline).touchTarget()
            }
            if model.log.isEmpty {
                Text("还没有记录。今晚点下面的开始试试。").font(.footnote).foregroundStyle(Night.muted)
            }
            ForEach(model.log) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text(e.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2).foregroundStyle(Night.muted)
                }
            }
        }
        .nightCard()
    }

    private func status(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Night.accent : Night.muted)
                .accessibilityLabel(ok ? "是" : "否")
        }
    }
}

struct MorningCard: View {
    var summary: MorningSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("早上好").font(.headline)
                Spacer()
                if let r = summary.latencyRating {
                    Text(r)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Night.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Night.accent, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            Text(summary.headline).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            ForEach(summary.lines, id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(Night.muted).fixedSize(horizontal: false, vertical: true)
            }
            if summary.noiseLeq != nil && !summary.noiseVerified { UnverifiedBadge(text: "噪音来自未验证的 201D") }
        }
        .nightCard()
    }
}

struct SleepSoundsCard: View {
    @ObservedObject var sounds = SleepSoundPlayer.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("助眠声音").font(.headline)
                    Text(sounds.isFading ? "正在淡出…" : sounds.isPlaying ? "播放中，睡着后自动淡出" : "实时生成，不循环")
                        .font(.caption).foregroundStyle(Night.muted)
                    Text(sounds.color.label).font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                Button {
                    sounds.isPlaying ? sounds.fadeOutAndStop(seconds: 3) : sounds.start()
                    Haptics.night()
                } label: {
                    Image(systemName: sounds.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Night.accent, in: Circle())
                        .foregroundStyle(Night.onAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sounds.isPlaying ? "停止助眠声音" : "播放助眠声音")
            }
            Picker("声音", selection: $sounds.color) {
                ForEach(NoiseColor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(Night.muted)
                Slider(value: $sounds.volume, in: 0.05...0.8)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Night.muted)
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
        .nightCard()
    }
}

struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var extras = SleepExtrasStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(StreakKind.allCases, id: \.self) { k in
                            let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(k.label).font(.caption.weight(.bold)).foregroundStyle(Night.muted)
                                Text("\(s.current) 天")
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text("最长 \(s.best) 天").font(.caption2).foregroundStyle(Night.muted)
                            }
                            .nightCard()
                        }
                    }
                    Text("成就").font(.title3.weight(.bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(Achievement.allCases, id: \.self) { a in
                            let date = extras.unlocked[a]
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: date == nil ? "square" : "circle.fill")
                                    .foregroundStyle(date == nil ? Night.muted : Night.accent)
                                Text(a.title).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                Text(a.detail).font(.caption2).foregroundStyle(Night.muted).fixedSize(horizontal: false, vertical: true)
                                if a.usesUnverifiedData { UnverifiedBadge() }
                                if let date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2).foregroundStyle(Night.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                            .nightCard()
                            .opacity(date == nil ? 0.7 : 1)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("* 安静日和清新通勤依赖未验证的 201D 读数；读不到时只是不会解锁，不影响其他成就。")
                        .font(.caption).foregroundStyle(Night.muted)
                }
                .padding(20)
            }
            .background(Night.ground)
            .foregroundStyle(Night.ink)
            .navigationTitle("连续与成就")
            .toolbarBackground(Night.ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.touchTarget() } }
        }
        .preferredColorScheme(.dark)
    }
}
