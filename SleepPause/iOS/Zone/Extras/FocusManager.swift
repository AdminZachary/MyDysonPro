import Foundation
import UserNotifications

/// Pomodoro focus with the Zone: ANC during focus, transparency on breaks, optional fan level,
/// auto-pause when the headphones come off (⚠️ needs the unverified 2DD12004 worn flag; without it
/// the timer simply keeps running). Never runs while the sleep watch holds the ANC mode.
@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    struct LogItem: Codable { var date: Date; var minutes: Double }

    @Published private(set) var session = FocusSession()
    @Published private(set) var log: [LogItem] = []
    private var timer: Timer?
    private let logKey = "focus.log"

    private init() {
        if let d = UserDefaults.standard.data(forKey: logKey), let l = try? JSONDecoder().decode([LogItem].self, from: d) { log = l }
    }

    var zone: ZoneManager { ZoneManager.shared }

    /// Past sessions for the weekly report. Does not start a live timer.
    func applyScreenshotHistory() {
        let cal = Calendar.current
        let week = WeeklyReport.previousWeek(now: Date(), calendar: cal)
        log = (0..<4).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: week.start).map { LogItem(date: $0.addingTimeInterval(9 * 3600), minutes: 25) }
        }
        log.append(LogItem(date: Date().addingTimeInterval(-3600), minutes: 25))
        log.append(LogItem(date: Date().addingTimeInterval(-1800), minutes: 25))
    }

    func applyScreenshotFixture() {
        applyScreenshotHistory()
        var next = FocusSession()
        next.loadPreview(remaining: 24 * 60 + 18, cycles: 2, at: Date())
        session = next
    }

    func start() {
        guard !zone.adaptive.isSleepHeld(at: Date()) else {
            AppModel.shared.add("睡眠监测进行中，不能开始专注（保持当前降噪）")
            return
        }
        session.config = ZoneSettings.shared.focus
        session.start(at: Date())
        zone.adaptive.focusActive = true
        apply(.focus)
        scheduleNotification()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        _ = UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        ZoneAutomations.shared.publishSnapshot(forceActivity: true)
        if ZoneSettings.shared.liveActivityAuto { ZoneAutomations.shared.startLiveActivity(title: "专注") }
    }

    func stop() {
        guard session.isActive else { return }
        session.stop(at: Date())
        record()
        timer?.invalidate(); timer = nil
        zone.adaptive.focusActive = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.phase"])
        ZoneAutomations.shared.publishSnapshot(forceActivity: true)
    }

    func togglePause() {
        if session.isPaused { session.resume(at: Date()); scheduleNotification() }
        else { session.pause(at: Date()); UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.phase"]) }
        ZoneAutomations.shared.publishSnapshot(forceActivity: true)
    }

    func wornChanged(_ worn: Bool) {
        guard session.wornChanged(worn, at: Date()) else { return }
        AppModel.shared.add(worn ? "专注：戴回耳机，计时继续" : "专注：摘下耳机，计时暂停（2004 未验证）")
        if session.isPaused { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.phase"]) }
        else { scheduleNotification() }
        ZoneAutomations.shared.publishSnapshot(forceActivity: true)
    }

    var todayMinutes: Double {
        log.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.minutes } +
            (session.isActive ? session.focusedSeconds / 60 : 0)
    }

    private func tick() {
        if let next = session.tick(at: Date()) {
            Haptics.success()
            apply(next)
            scheduleNotification()
            ZoneAutomations.shared.publishSnapshot(forceActivity: true)
        }
    }

    private func apply(_ phase: FocusPhase) {
        guard zone.isReady else { return }
        let c = session.config
        switch phase {
        case .focus:
            zone.setANC(c.focusANC, manual: false)
            if let f = c.focusFanLevel { zone.setFan(f) }
        case .shortBreak, .longBreak:
            zone.setANC(c.breakANC, manual: false)
        case .idle: break
        }
    }

    private func scheduleNotification() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["focus.phase"])
        let rem = session.remaining(at: Date())
        guard session.isActive, !session.isPaused, rem > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = session.phase == .focus ? "专注结束，休息一下" : "休息结束，继续专注"
        content.body = "已完成 \(session.completedFocusCycles + (session.phase == .focus ? 1 : 0)) 个番茄"
        content.sound = .default
        c.add(UNNotificationRequest(identifier: "focus.phase", content: content,
                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: rem, repeats: false)))
    }

    private func record() {
        let m = session.focusedSeconds / 60
        guard m >= 1 else { return }
        log.append(LogItem(date: Date(), minutes: m))
        let cutoff = Date().addingTimeInterval(-60 * 86400)
        log.removeAll { $0.date < cutoff }
        if let d = try? JSONEncoder().encode(log) { UserDefaults.standard.set(d, forKey: logKey) }
        AppModel.shared.add(String(format: "专注结束：%.0f 分钟，%d 个番茄", m, session.completedFocusCycles))
        SleepExtrasStore.shared.refreshAchievements()
    }
}
