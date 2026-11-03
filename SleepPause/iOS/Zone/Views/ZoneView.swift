import SwiftUI

struct ZoneView: View {
    @ObservedObject var zone = ZoneManager.shared
    @ObservedObject var settings = ZoneSettings.shared
    @ObservedObject var noise = NoiseExposureStore.shared
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Form {
                if settings.moduleEnabled {
                    Section { ZoneDashboard(onLogin: { showLogin = true }).floatingRow() }
                } else {
                    Section {
                        StatePanel(symbol: "headphones", title: "连接你的 Dyson Zone（可选）",
                                   message: "看空气和噪音、自动降噪、污染时加大风扇、入睡时关风扇。不开启也不影响睡眠暂停。",
                                   actionTitle: "启用 Zone 模块", action: { settings.moduleEnabled = true; Haptics.success() })
                        .card()
                        .floatingRow()
                    }
                }
                Section {
                    Toggle("启用 Dyson Zone 模块（非官方）", isOn: $settings.moduleEnabled)
                        .onChange(of: settings.moduleEnabled) { _, on in on ? zone.bootstrap() : zone.shutdown() }
                    Label("Zone 同一时间只接受一个控制端：使用本功能时请彻底退出 MyDyson（或关闭它的后台）。",
                          systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.red)
                }
                if settings.moduleEnabled {
                    statusSection
                    controlSection
                    readingSection
                    sleepSection
                    adaptiveSection
                    noiseSection
                    ZoneExtrasSection()
                    Section("账号") {
                        Button(ZoneKeychain.load() == nil ? "登录 Dyson 账号" : "重新登录") { showLogin = true }
                        Button("退出并删除密钥", role: .destructive) { zone.forgetAccount() }
                    }
                    Section("Zone 日志") {
                        ForEach(Array(zone.log.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                    }
                }
            }
            .navigationTitle("Dyson Zone")
            .paperBackdrop(Palette.blue)
            .minimizingNavigationBar()
            .refreshable { if !zone.isReady { zone.bootstrap() } }
            .sheet(isPresented: $showLogin) { ZoneLoginView() }
        }
    }

    private var statusSection: some View {
        Section("状态") {
            LabeledContent("连接", value: zone.state.label)
            LabeledContent("电量", value: zone.batteryPercent.map { "\($0)%" } ?? "–")
            LabeledContent("佩戴（2004，未验证）", value: zone.worn.map { $0 ? "已戴上" : "已摘下" } ?? "–")
            LabeledContent("面罩（2005，未验证）", value: visorText)
            LabeledContent("风扇实际档位", value: zone.fanActual.map(String.init) ?? "–")
            if zone.state == .needsLogin { Button("登录 Dyson 账号") { showLogin = true } }
        }
    }

    private var visorText: String {
        switch zone.visor { case 0: return "未安装"; case 1: return "在位"; case 2: return "下翻"; case 3: return "无效"; default: return "–" }
    }

    private var controlSection: some View {
        Section("控制") {
            Picker("降噪", selection: Binding(get: { zone.ancMode ?? .anc }, set: { zone.setANC($0, manual: true); Haptics.select() })) {
                ForEach(ZoneANCMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Text("风扇")
                Spacer(minLength: 4)
                GlassGroup(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(0..<4, id: \.self) { l in
                            Button(["关", "静息", "轻度", "中度"][l]) { ZoneAutomations.shared.userSetFan(l); Haptics.select() }
                                .glassButton(prominent: zone.fanSpeed == l)
                                .tint(Palette.blue)
                                .touchTarget()
                        }
                    }
                }
            }
        }.disabled(!zone.isReady)
    }

    private var readingSection: some View {
        Section {
            if let r = zone.lastReading {
                LabeledContent("环境噪音", value: String(format: "%.1f dB", r.ambientDb))
                LabeledContent("耳内 / 音频", value: String(format: "%.1f / %.1f dB", r.inEarDb, r.audioDb))
                LabeledContent("NO₂", value: String(format: "%.0f ppb（AQI %.0f）", r.no2Ppb, r.no2AQI))
                LabeledContent("VOC", value: String(format: "%.0f ppb", r.vocPpb))
                LabeledContent("温度 / 湿度", value: String(format: "%.1f°C / %.0f%%", r.temperatureC, r.humidityPercent))
                if !r.looksPlausible {
                    Text("⚠️ 数值超出合理范围：字段布局可能不对").foregroundStyle(.red).font(.footnote)
                }
            } else {
                Text("暂无读数").foregroundStyle(.secondary)
            }
            if let raw = zone.lastRawAQ { Text("原始 201D：\(raw)").font(.caption.monospaced()).textSelection(.enabled) }
        } header: {
            Text("读数（2DD1201D）")
        } footer: {
            Text(ZoneAQLayout.current.isVerified ? "布局：\(ZoneAQLayout.current.name)"
                 : "⚠️ 未验证布局：\(ZoneAQLayout.current.name)。字段顺序是根据 MyDyson 推断的，等 ZoneProbe 报告确认后再修正。原始字节都已记录。")
        }
    }

    private var sleepSection: some View {
        Section {
            Toggle("入睡时关闭风扇", isOn: $settings.sleepFanOff)
            Toggle("入睡时关闭降噪（默认关）", isOn: $settings.sleepANCOff)
            Toggle("摘下耳机时停止今晚监测（2004 未验证）", isOn: $settings.wearStopsWatch)
            Button("测试：执行入睡时的 Zone 动作") { AppModel.shared.add(zone.handleSleepOnset()) }
        } header: { Text("睡眠联动") } footer: {
            Text("默认只关风扇、保持降噪。Zone 未连接时会跳过并记入日志，不影响 iPhone 暂停音乐。")
        }
    }

    private var adaptiveSection: some View {
        Section {
            Toggle("按环境噪音自动切换降噪", isOn: $settings.adaptiveEnabled)
            Stepper(String(format: "嘈杂 ≥ %.0f dB → 降噪", settings.adaptive.loudThresholdDb),
                    value: $settings.adaptive.loudThresholdDb, in: 55...90, step: 1)
            Stepper(String(format: "安静 ≤ %.0f dB → %@", settings.adaptive.quietThresholdDb, settings.adaptive.quietMode.label),
                    value: $settings.adaptive.quietThresholdDb, in: 35...(settings.adaptive.loudThresholdDb - 3), step: 1)
            Picker("安静时使用", selection: $settings.adaptive.quietMode) {
                ForEach([ZoneANCMode.transparency, .conversation, .off], id: \.self) { Text($0.label).tag($0) }
            }
            Stepper("手动切换后暂停 \(Int(settings.adaptive.manualOverrideMinutes)) 分钟",
                    value: $settings.adaptive.manualOverrideMinutes, in: 5...180, step: 5)
            if zone.adaptive.isOverridden(at: Date()) {
                Button("恢复自动（取消手动暂停）") { zone.adaptive.clearOverride() }
            }
            if zone.adaptive.isSleepHeld(at: Date()) {
                Text("睡眠中：自动切换已暂停，保持当前降噪模式").font(.footnote).foregroundStyle(.secondary)
                if !zone.adaptive.sleepWatchActive {
                    Button("醒了，恢复自动切换") { zone.adaptive.clearSleepHold() }
                }
            }
        } header: { Text("自适应降噪（DIY）") } footer: {
            Text("两个阈值之间是迟滞区，保持当前模式；按 20 秒中位数判断，切换后至少保持 60 秒。今晚监测进行中、以及检测到入睡后 12 小时内不会自动切换。依赖未验证的 201D 布局。")
        }
    }

    private var noiseSection: some View {
        Section {
            LabeledContent("今日噪音剂量", value: String(format: "%.0f%%", noise.today.dosePercent))
            LabeledContent("今日 LEX,8h", value: noise.today.lex8h.map { String(format: "%.1f dB", $0) } ?? "–")
            Toggle("写入“健康”·环境声音", isOn: $settings.writeNoiseToHealth)
                .onChange(of: settings.writeNoiseToHealth) { _, on in if on { Task { await noise.requestPermissions() } } }
            Toggle("剂量达到 100% 时通知", isOn: $settings.noiseAlerts)
                .onChange(of: settings.noiseAlerts) { _, on in if on { Task { await noise.requestPermissions() } } }
            Text(noise.healthStatus).font(.caption).foregroundStyle(.secondary)
            ShareLink("导出原始 201D 记录", item: noise.rawLogURL)
        } header: { Text("噪音暴露") } footer: {
            Text("按 85 dB·8 小时、3 dB 交换率计算；只统计佩戴时（若佩戴状态可用）。数值依赖未验证的布局，且不确定 Zone 是否为 A 计权，仅供参考。")
        }
    }
}
