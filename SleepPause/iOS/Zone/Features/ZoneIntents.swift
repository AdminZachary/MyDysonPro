import AppIntents
import Foundation

// Feature 2: Shortcuts / Siri actions. All of them need the Zone connected to THIS iPhone
// (MyDyson closed). They wait up to ~12 s for the BLE link.

enum ZoneANCModeEntity: String, AppEnum {
    case anc, conversation, transparency, off
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Zone 降噪模式"
    static var caseDisplayRepresentations: [ZoneANCModeEntity: DisplayRepresentation] = [
        .anc: "降噪", .conversation: "对话", .transparency: "通透", .off: "关闭",
    ]
    var mode: ZoneANCMode {
        switch self { case .anc: return .anc; case .conversation: return .conversation
        case .transparency: return .transparency; case .off: return .off }
    }
}

struct ZoneNotReady: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Zone 未连接：请确认已开机、已在 SleepPause 登录，并彻底退出 MyDyson。" }
}

struct GetZoneBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "获取 Zone 电量"
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard await ZoneManager.shared.waitUntilReady(), let b = ZoneManager.shared.batteryPercent else { throw ZoneNotReady() }
        return .result(value: b, dialog: "Zone 电量 \(b)%")
    }
}

struct GetZoneReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "获取 Zone 噪音和空气读数"
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let z = ZoneManager.shared
        guard await z.waitUntilReady() else { throw ZoneNotReady() }
        if z.lastReading == nil { try? await Task.sleep(nanoseconds: 3_000_000_000) }
        guard let r = z.lastReading else { throw ZoneNotReady() }
        let s = String(format: "环境噪音 %.0f dB，NO₂ %.0f ppb，VOC %.0f ppb，%.1f°C，湿度 %.0f%%%@",
                       r.ambientDb, r.no2Ppb, r.vocPpb, r.temperatureC, r.humidityPercent,
                       r.layoutVerified ? "" : "（数据布局未验证）")
        return .result(value: s, dialog: "\(s)")
    }
}

struct SetZoneANCIntent: AppIntent {
    static var title: LocalizedStringResource = "设置 Zone 降噪模式"
    @Parameter(title: "模式") var mode: ZoneANCModeEntity
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await ZoneManager.shared.waitUntilReady() else { throw ZoneNotReady() }
        ZoneManager.shared.setANC(mode.mode, manual: true)
        return .result(dialog: "已切换为\(mode.mode.label)")
    }
}

struct SetZoneFanIntent: AppIntent {
    static var title: LocalizedStringResource = "设置 Zone 风扇档位"
    @Parameter(title: "档位（0 关，1 静息，2 轻度，3 中度）", inclusiveRange: (0, 3)) var level: Int
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await ZoneManager.shared.waitUntilReady() else { throw ZoneNotReady() }
        ZoneAutomations.shared.userSetFan(level)
        return .result(dialog: "风扇已设为 \(level) 档")
    }
}

struct StartSleepWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "开始今晚的入睡监测"
    // Opening the app makes starting the silent audio keep-alive reliable.
    static var openAppWhenRun: Bool = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.startTonight()
        return .result(dialog: "已开始守候，并请求手表开始监测")
    }
}

struct ZoneAirSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Zone：空气怎么样"
    static var description = IntentDescription("用一句话说出当前空气、噪音和电量。没连上时说出最后一次读数的时间。")
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let z = ZoneManager.shared
        if ZoneSettings.shared.moduleEnabled, await z.waitUntilReady(timeout: 8) {
            if z.lastReading == nil { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            let s = ZoneAutomations.shared.currentSnapshot().spokenSummary
            return .result(value: s, dialog: "\(s)")
        }
        if let last = SharedStore.load() {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            let s = "Zone 现在没连上。\(f.string(from: last.date)) 的读数：" + last.spokenSummary
            return .result(value: s, dialog: "\(s)")
        }
        throw ZoneNotReady()
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "开始 Zone 专注（番茄钟）"
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = await ZoneManager.shared.waitUntilReady(timeout: 8)
        FocusManager.shared.start()
        guard FocusManager.shared.session.isActive else { return .result(dialog: "睡眠监测进行中，没有开始专注") }
        return .result(dialog: "开始专注 \(Int(ZoneSettings.shared.focus.focusMinutes)) 分钟")
    }
}

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "结束 Zone 专注"
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        FocusManager.shared.stop()
        return .result(dialog: "已结束专注")
    }
}

struct SleepPauseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSleepWatchIntent(), phrases: ["用 \(.applicationName) 开始今晚监测"],
                    shortTitle: "开始今晚", systemImageName: "bed.double.fill")
        AppShortcut(intent: GetZoneBatteryIntent(), phrases: ["\(.applicationName) Zone 电量"],
                    shortTitle: "Zone 电量", systemImageName: "battery.75")
        AppShortcut(intent: GetZoneReadingIntent(), phrases: ["\(.applicationName) Zone 读数"],
                    shortTitle: "Zone 读数", systemImageName: "aqi.medium")
        AppShortcut(intent: SetZoneANCIntent(), phrases: ["用 \(.applicationName) 设置 Zone 降噪"],
                    shortTitle: "Zone 降噪", systemImageName: "ear")
        AppShortcut(intent: ZoneAirSummaryIntent(), phrases: ["\(.applicationName) 空气怎么样", "问 \(.applicationName) 空气怎么样"],
                    shortTitle: "空气怎么样", systemImageName: "aqi.low")
        AppShortcut(intent: StartFocusIntent(), phrases: ["用 \(.applicationName) 开始专注"],
                    shortTitle: "开始专注", systemImageName: "timer")
        AppShortcut(intent: StopFocusIntent(), phrases: ["用 \(.applicationName) 结束专注"],
                    shortTitle: "结束专注", systemImageName: "stop.circle")
        AppShortcut(intent: SetZoneFanIntent(), phrases: ["用 \(.applicationName) 设置 Zone 风扇"],
                    shortTitle: "Zone 风扇", systemImageName: "wind")
    }
}
