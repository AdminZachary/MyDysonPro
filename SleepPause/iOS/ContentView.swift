import SwiftUI

/// Sleep tab: calm night hero, morning summary, sleep sounds, streaks — then the original controls.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var extras = SleepExtrasStore.shared
    @ObservedObject var sounds = SleepSoundPlayer.shared
    @State private var showAchievements = false

    var body: some View {
        NavigationStack {
            List {
                Section { hero.floatingRow() }
                if let m = extras.morning, Date().timeIntervalSince(m.wake) < 18 * 3600 {
                    Section { MorningCard(summary: m).floatingRow() }
                }
                Section { SleepSoundsCard().floatingRow() }
                Section { streakStrip.floatingRow() }

                Section {
                    Button("立即测试暂停") { model.testPauseNow(); Haptics.tap() }
                    Button("20 秒后测试（先锁屏再等）") { model.testPauseLater() }
                } header: {
                    Text("测试（用 Dyson Zone 播放音乐时试一下）")
                } footer: {
                    Text("先用音乐 / Spotify / 播客等通过 Dyson Zone 播放，再点测试，确认会停。")
                }

                Section("选项") {
                    Toggle("同时直接暂停 Apple Music", isOn: $model.pauseAppleMusic)
                    Button("授权 Apple Music 控制") { model.requestMusicAuthorization() }
                    Toggle("把入睡时间写入“健康”", isOn: $model.writeToHealth)
                    Button("授权健康数据") { Task { await model.requestHealthAuthorization() } }
                }

                Section("Apple Watch") {
                    status("已配对", model.watchPaired)
                    status("手表 App 已安装", model.watchAppInstalled)
                    status("当前可直连", model.watchReachable)
                    Button("刷新") { model.refreshWatchState() }
                }

                Section {
                    if model.log.isEmpty {
                        Text("还没有记录。今晚点“开始今晚”试试。").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.log) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.text).font(.footnote)
                            Text(e.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("日志")
                        Spacer()
                        Button("清空") { model.clearLog() }.font(.caption)
                    }
                }
            }
            .navigationTitle("SleepPause")
            .vividBackdrop(Palette.dusk)
            .minimizingNavigationBar()
            .onAppear { model.refreshWatchState(); extras.refreshAchievements(notify: false) }
            .sheet(isPresented: $showAchievements) { AchievementsView() }
            .sensoryFeedback(.success, trigger: extras.justUnlocked)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isArmed ? "守候中" : "今晚").font(.largeTitle.bold())
                    Text(model.isArmed ? "睡着后自动暂停播放，降噪保持开启" : "戴上手表，点开始，安心入睡")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: model.isArmed ? "moon.zzz.fill" : "moon.stars.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.moon)
                    .symbolEffect(.pulse, options: .repeating, isActive: model.isArmed)
                    .symbolEffect(.bounce, value: model.isArmed)
            }
            if let onset = model.lastOnset {
                Label("上次入睡 \(onset.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            Button {
                if model.isArmed { model.stopTonight(); Haptics.tap() }
                else { Task { await model.startTonight(); Haptics.success() } }
            } label: {
                Label(model.isArmed ? "停止守候" : "开始今晚（同时启动手表）",
                      systemImage: model.isArmed ? "stop.fill" : "bed.double.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .glassButton(prominent: true)          // .glassProminent on iOS 26+: the one tinted primary action
            .controlSize(.large)
            .tint(model.isArmed ? Color.red.opacity(0.85) : Palette.moon.opacity(0.9))
            .foregroundStyle(model.isArmed ? Color.white : Palette.night)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.nightGradient))
        .overlay(alignment: .topTrailing) {
            // a few "stars"
            Canvas { ctx, size in
                for (x, y, r) in [(0.62, 0.18, 1.6), (0.78, 0.36, 1.1), (0.55, 0.42, 0.9), (0.88, 0.12, 1.3)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: size.width * x, y: size.height * y, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.7)))
                }
            }.allowsHitTesting(false)
        }
        .animation(.smooth, value: model.isArmed)
    }

    // MARK: Streaks

    private var streakStrip: some View {
        Button { showAchievements = true } label: {
            HStack(spacing: 12) {
                ForEach(StreakKind.allCases, id: \.self) { k in
                    let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                    VStack(spacing: 4) {
                        Image(systemName: k.symbol).font(.title3)
                            .foregroundStyle(s.current > 0 ? Palette.focus : .secondary)
                            .symbolEffect(.bounce, value: s.current)
                        Text("\(s.current)").font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
                        Text(k.label + (k.usesUnverifiedData ? "*" : "")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("连续天数与成就")
    }

    private func status(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}

struct MorningCard: View {
    var summary: MorningSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: summary.wake)
                Text("早上好").font(.headline)
                Spacer()
                if let r = summary.latencyRating { Chip(symbol: "bolt.heart", text: r, tint: .orange) }
            }
            Text(summary.headline).font(.title3.bold())
            ForEach(summary.lines, id: \.self) { l in
                Label(l, systemImage: l.contains("噪音") ? "ear" : l.contains("闹钟") ? "alarm" : "bed.double")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if summary.noiseLeq != nil && !summary.noiseVerified { UnverifiedBadge(text: "噪音来自未验证的 201D") }
        }
        .card()
    }
}

struct SleepSoundsCard: View {
    @ObservedObject var sounds = SleepSoundPlayer.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: sounds.color.symbol).font(.title2).foregroundStyle(.indigo)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: sounds.isPlaying)
                VStack(alignment: .leading) {
                    Text("助眠声音").font(.headline)
                    Text(sounds.isFading ? "正在淡出…" : sounds.isPlaying ? "播放中，睡着后自动淡出" : "实时生成，不循环")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    sounds.isPlaying ? sounds.fadeOutAndStop(seconds: 3) : sounds.start()
                    Haptics.tap()
                } label: {
                    Image(systemName: sounds.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 40))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain).foregroundStyle(.indigo)
                .glassSurface(Circle(), interactive: true)
                .accessibilityLabel(sounds.isPlaying ? "停止助眠声音" : "播放助眠声音")
            }
            Picker("声音", selection: $sounds.color) {
                ForEach(NoiseColor.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $sounds.volume, in: 0.05...0.8)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Stepper("入睡后 \(Int(sounds.fadeSeconds)) 秒淡出", value: $sounds.fadeSeconds, in: 15...600, step: 15).font(.subheadline)
            Picker("没检测到入睡时", selection: $sounds.timerMinutes) {
                Text("一直播放").tag(0.0); Text("30 分钟后淡出").tag(30.0); Text("60 分钟").tag(60.0); Text("90 分钟").tag(90.0)
            }.font(.subheadline)
        }
        .card()
    }
}

struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var extras = SleepExtrasStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ForEach(StreakKind.allCases, id: \.self) { k in
                            let s = extras.streaks[k] ?? Streak(current: 0, best: 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(k.label, systemImage: k.symbol).font(.caption.bold())
                                Text("\(s.current) 天").font(.title2.bold()).monospacedDigit()
                                Text("最长 \(s.best) 天").font(.caption2).foregroundStyle(.secondary)
                            }.card()
                        }
                    }
                    Text("成就").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(Achievement.allCases, id: \.self) { a in
                            let date = extras.unlocked[a]
                            VStack(spacing: 6) {
                                Image(systemName: date == nil ? "lock.fill" : a.symbol)
                                    .font(.system(size: 30))
                                    .foregroundStyle(date == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.levelGradient(0)))
                                    .symbolEffect(.bounce, value: extras.justUnlocked == a)
                                    .frame(height: 36)
                                Text(a.title).font(.subheadline.bold())
                                Text(a.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                if a.usesUnverifiedData { UnverifiedBadge() }
                                if let date { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .card()
                            .opacity(date == nil ? 0.6 : 1)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("* 安静日和清新通勤依赖未验证的 201D 读数；读不到时只是不会解锁，不影响其他成就。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(VividBackdrop(color: .green))
            .navigationTitle("连续与成就")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
