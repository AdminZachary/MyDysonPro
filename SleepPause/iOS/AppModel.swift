import Foundation
import SwiftUI
import UIKit
import MediaPlayer

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var isArmed = false {
        // Adaptive ANC never switches modes while tonight's sleep watch is active.
        didSet { ZoneManager.shared.adaptive.sleepWatchActive = isArmed }
    }
    @Published private(set) var lastOnset: Date?
    @Published private(set) var watchPaired = false
    @Published private(set) var watchAppInstalled = false
    @Published private(set) var watchReachable = false

    @Published var writeToHealth: Bool = UserDefaults.standard.bool(forKey: "writeToHealth") {
        didSet { UserDefaults.standard.set(writeToHealth, forKey: "writeToHealth") }
    }
    @Published var pauseAppleMusic: Bool = (UserDefaults.standard.object(forKey: "pauseAppleMusic") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(pauseAppleMusic, forKey: "pauseAppleMusic") }
    }

    private let pauser = MediaPauser()
    private let health = HealthWriter()
    private let eventLog = EventLog()
    private var handledIDs: [String] = []

    private init() {
        log = eventLog.entries
        let connector = PhoneConnector.shared
        connector.onMessage = { [weak self] msg, channel in
            Task { @MainActor in self?.handle(msg, channel: channel) }
        }
        connector.onStateChange = { [weak self] in
            Task { @MainActor in self?.refreshWatchState() }
        }
        connector.activate()
        if let ts = UserDefaults.standard.object(forKey: "lastOnset") as? Double {
            lastOnset = Date(timeIntervalSince1970: ts)
        }
    }

    // MARK: Nightly flow

    func applyScreenshotFixture(armed: Bool) {
        isArmed = armed
        if let ts = UserDefaults.standard.object(forKey: "lastOnset") as? Double {
            lastOnset = Date(timeIntervalSince1970: ts)
        }
        watchPaired = true
        watchAppInstalled = true
        watchReachable = true
        add("示例：昨晚检测到入睡，降噪保持开启")
    }

    /// Arm the silent audio keep-alive on the phone and launch the watch workout.
    func startTonight() async {
        do {
            try pauser.arm()
            if FocusManager.shared.session.isActive { FocusManager.shared.stop() }   // sleep owns ANC tonight
            isArmed = true
            if let w = ZoneAutomations.shared.bedtimeCheck() { add(w) }
            add("iPhone 已进入守候（静音保活，音乐照常播放）")
        } catch {
            add("iPhone 守候失败：\(error.localizedDescription)")
        }
        _ = await health.requestAuthorization()
        do {
            try await health.startWatchApp()
            add("已请求在 Apple Watch 上开始监测")
        } catch {
            add("无法自动启动手表 App（\(error.localizedDescription)）——请在手表上手动点“开始今晚监测”")
        }
    }

    func stopTonight() {
        pauser.disarm()
        isArmed = false
        PhoneConnector.shared.sendStopToWatch()
        add("已停止守候")
    }

    func testPauseNow() {
        let result = pauser.pauseOthers(pauseAppleMusic: pauseAppleMusic, rearmAfter: isArmed)
        add("测试暂停：\(result)")
    }

    /// Lets you lock the phone and verify that pausing also works in the background.
    func testPauseLater(seconds: Double = 20) {
        if !isArmed {
            try? pauser.arm()
            isArmed = true
        }
        add("\(Int(seconds)) 秒后测试暂停——现在可以锁屏并播放音乐")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            let result = self.pauser.pauseOthers(pauseAppleMusic: self.pauseAppleMusic, rearmAfter: true)
            self.add("延时测试暂停：\(result)")
        }
    }

    func requestMusicAuthorization() {
        MPMediaLibrary.requestAuthorization { status in
            Task { @MainActor in
                AppModel.shared.add("Apple Music 授权：\(status == .authorized ? "已允许" : "未允许")")
            }
        }
    }

    func requestHealthAuthorization() async {
        let ok = await health.requestAuthorization()
        add(ok ? "已请求健康权限" : "健康权限请求失败")
    }

    // MARK: Messages from the watch

    func handle(_ msg: SleepMessage, channel: String) {
        // sendMessage may fail and be retried via transferUserInfo -> de-duplicate by id.
        guard !handledIDs.contains(msg.id) else { return }
        handledIDs.append(msg.id)
        if handledIDs.count > 50 { handledIDs.removeFirst() }

        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "SleepPause.handle")
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }

        let hr = msg.currentHR.map { " 当前心率 \(Int($0))" } ?? ""
        let base = msg.baselineHR.map { " 基线 \(Int($0))" } ?? ""
        switch msg.type {
        case .sleepOnset:
            lastOnset = msg.date
            UserDefaults.standard.set(msg.date.timeIntervalSince1970, forKey: "lastOnset")
            ZoneAutomations.shared.recordOnset(msg.date)
            let sounds = SleepSoundPlayer.shared
            let hold = sounds.isPlaying ? sounds.fadeSeconds + 3 : 3
            let result = pauser.pauseOthers(pauseAppleMusic: pauseAppleMusic, rearmAfter: false, releaseAfter: hold)
            if sounds.isPlaying {
                sounds.fadeOutAndStop()
                add("助眠声音将在 \(Int(sounds.fadeSeconds)) 秒内慢慢淡出（降噪保持开启）")
            }
            isArmed = false
            add("😴 检测到入睡（\(channel)\(base)\(hr)）→ \(result)", date: msg.date)
            if ZoneSettings.shared.moduleEnabled {
                add(ZoneManager.shared.handleSleepOnset())
            }
        case .testPause:
            let result = pauser.pauseOthers(pauseAppleMusic: pauseAppleMusic, rearmAfter: isArmed)
            add("手表发来测试（\(channel)）→ \(result)")
        case .sessionStarted:
            SleepExtrasStore.shared.sessionStarted(msg.date)
            add("手表开始监测（\(channel)）", date: msg.date)
        case .woke:
            add("⏰ 手表智能闹钟叫醒（\(channel)）", date: msg.date)
            // stillMinutes carries "minutes before the deadline" for smart-alarm wakes (0 = deadline)
            let early = (msg.stillMinutes ?? 0) >= 1
            SleepExtrasStore.shared.makeMorningSummary(wake: msg.date, onset: lastOnset,
                                                       alarmDeadline: msg.date.addingTimeInterval((msg.stillMinutes ?? 0) * 60),
                                                       alarmEarly: early)
        case .sessionStopped:
            add("手表结束监测（\(channel)）", date: msg.date)
            SleepExtrasStore.shared.makeMorningSummary(wake: msg.date, onset: lastOnset)
            if writeToHealth, let onset = lastOnset, onset < msg.date,
               msg.date.timeIntervalSince(onset) < 16 * 3600 {
                Task {
                    do {
                        try await health.writeSleep(from: onset, to: msg.date)
                        add("已写入健康：睡眠 \(onset.formatted(date: .omitted, time: .shortened))–\(msg.date.formatted(date: .omitted, time: .shortened))")
                    } catch {
                        add("写入健康失败：\(error.localizedDescription)")
                    }
                }
            }
        case .status:
            break
        }
    }

    // MARK: Dyson Zone wear (UNVERIFIED characteristic 2DD12004)

    private var unwornTask: Task<Void, Never>?

    /// Removing the headphones while the sleep watch is armed stops tonight's watch
    /// after a 60 s debounce (put back on within 60 s → nothing happens).
    func zoneWornChanged(_ worn: Bool) {
        unwornTask?.cancel()
        guard !worn, isArmed, ZoneSettings.shared.wearStopsWatch else { return }
        add("Zone 已摘下，60 秒内未戴回将停止今晚监测")
        unwornTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, self.isArmed, ZoneManager.shared.worn == false else { return }
            self.add("Zone 已摘下 → 停止今晚监测")
            self.stopTonight()
        }
    }

    // MARK: Helpers

    func refreshWatchState() {
        guard !ScreenshotMode.isActive else { return }
        let c = PhoneConnector.shared
        watchPaired = c.isPaired
        watchAppInstalled = c.isWatchAppInstalled
        watchReachable = c.isReachable
    }

    func add(_ text: String, date: Date = Date()) {
        eventLog.add(text, date: date)
        log = eventLog.entries
    }

    func clearLog() {
        eventLog.clear()
        log = []
    }
}
