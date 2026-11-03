import Foundation
import Combine
import UserNotifications
import WidgetKit

/// Glue for the "extras": pollution fan boost, low-battery alerts, widget / Live Activity snapshot,
/// weekly report. All of them degrade gracefully when Zone data is missing.
@MainActor
final class ZoneAutomations: ObservableObject {
    static let shared = ZoneAutomations()

    let fanBoost = FanBoostController()
    @Published private(set) var lastBoostNote: String?
    @Published private(set) var lastReport: WeeklyReport?

    private var battery = BatteryAlertPolicy()
    private var bag: Set<AnyCancellable> = []
    private var lastWidgetReload: Date?
    private var lastSnapshot: ZoneSnapshot?
    private let onsetKey = "sleep.onsets"
    private let reportKey = "report.lastWeekStart"

    private init() {}

    var zone: ZoneManager { ZoneManager.shared }

    /// Called once at launch.
    func wire() {
        zone.$batteryPercent.removeDuplicates().sink { [weak self] p in
            Task { @MainActor in self?.batteryChanged(p) }
        }.store(in: &bag)
        zone.$state.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.publishSnapshot() }
        }.store(in: &bag)
        zone.$ancMode.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.publishSnapshot() }
        }.store(in: &bag)
        checkWeeklyReport()
    }

    // MARK: reading pipeline

    func ingest(_ r: ZoneAQReading) {
        runFanBoost(r)
        publishSnapshot()
        checkWeeklyReport()
    }

    private func runFanBoost(_ r: ZoneAQReading) {
        let s = ZoneSettings.shared
        guard s.fanBoostEnabled, zone.isReady else { return }
        fanBoost.config = s.fanBoost
        let visorAttached: Bool? = zone.visor.map { $0 == 1 || $0 == 2 }
        let held = zone.adaptive.isSleepHeld(at: r.date)
        guard let action = fanBoost.update(no2: r.looksPlausible ? r.no2Ppb : nil, voc: r.looksPlausible ? r.vocPpb : nil,
                                           at: r.date, currentLevel: zone.fanSpeed, held: held, visorAttached: visorAttached)
        else { return }
        switch action {
        case .boost(let level, let reason):
            zone.setFan(level)
            lastBoostNote = "污染升高（\(reason)）→ 风扇 \(level) 档"
            notify(id: "zone.boost", title: "空气变差，已加大 Zone 风扇", body: "\(reason)。空气恢复后会自动调回。")
        case .restore(let level):
            zone.setFan(level)
            lastBoostNote = "空气恢复 → 风扇回到 \(level) 档"
        }
        AppModel.shared.add("风扇加速：\(lastBoostNote ?? "")")
    }

    /// Called when the user picks a fan level by hand (app or Shortcuts).
    func userSetFan(_ level: Int) {
        fanBoost.noteManualChange()
        zone.setFan(level)
    }

    // MARK: battery

    private func batteryChanged(_ p: Int?) {
        publishSnapshot()
        guard ZoneSettings.shared.batteryAlerts, let t = battery.update(percent: p) else { return }
        notify(id: "zone.battery", title: "Zone 电量低于 \(t)%", body: "当前 \(p ?? t)%。风扇耗电较快，可以调低风扇或充电。")
    }

    func bedtimeCheck() -> String? {
        guard ZoneSettings.shared.moduleEnabled, let w = BatteryAlertPolicy.bedtimeWarning(percent: zone.batteryPercent) else { return nil }
        notify(id: "zone.bedtime", title: "睡前提醒", body: w)
        return w
    }

    // MARK: snapshot → widgets + Live Activity

    func currentSnapshot() -> ZoneSnapshot {
        let r = zone.lastReading
        let ok = r?.looksPlausible == true && Date().timeIntervalSince(r?.date ?? .distantPast) < 300
        let f = FocusManager.shared.session
        let zoneOn = HeadphonePreference.usesZone() && ZoneSettings.shared.moduleEnabled
        let today = NoiseExposureStore.shared.mergedToday
        let latestPlayback = today.last { $0.origin == .headphone }?.leq
        return ZoneSnapshot(date: Date(), connected: zone.isReady, battery: zone.batteryPercent, ancLabel: zone.ancMode?.label,
                            worn: zone.worn, ambientDb: zoneOn ? (ok ? r?.ambientDb : nil) : latestPlayback,
                            no2Ppb: zoneOn && ok ? r?.no2Ppb : nil,
                            vocPpb: zoneOn && ok ? r?.vocPpb : nil, temperatureC: zoneOn && ok ? r?.temperatureC : nil,
                            layoutVerified: zoneOn ? ZoneAQLayout.current.isVerified : !today.contains { $0.origin == .zone },
                            dosePercent: NoiseExposureStore.shared.mergedDosePercent,
                            focusPhase: f.isActive ? (f.isPaused ? "\(f.phase.label)（暂停）" : f.phase.label) : nil,
                            focusEndsAt: f.isActive && !f.isPaused ? f.phaseEndsAt : nil,
                            showsAir: zoneOn,
                            doseLabel: NoiseMerge.primaryLabel(today))
    }

    func publishSnapshot(forceActivity: Bool = false) {
        let s = currentSnapshot()
        SharedStore.save(s)
        let now = Date()
        let changedALot = lastSnapshot.map { $0.connected != s.connected || $0.airLevel != s.airLevel ||
            $0.focusPhase != s.focusPhase || $0.battery != s.battery } ?? true
        if changedALot || (lastWidgetReload.map { now.timeIntervalSince($0) > 600 } ?? true) {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = now
        }
        lastSnapshot = s
        LiveActivityController.shared.update(s, force: forceActivity)
    }

    func startLiveActivity(title: String? = nil) {
        let name = title ?? (HeadphonePreference.usesZone() ? "Dyson Zone" : "耳机噪音")
        LiveActivityController.shared.start(title: name, snapshot: currentSnapshot())
    }

    // MARK: sleep onset history (for the weekly report)

    func recordOnset(_ d: Date) {
        var a = UserDefaults.standard.array(forKey: onsetKey) as? [Double] ?? []
        a.append(d.timeIntervalSince1970)
        a = a.filter { $0 > Date().addingTimeInterval(-60 * 86400).timeIntervalSince1970 }
        UserDefaults.standard.set(a, forKey: onsetKey)
    }

    // MARK: weekly report

    func buildLastWeek(now: Date = Date()) -> WeeklyReport {
        let cal = Calendar.current
        let week = WeeklyReport.previousWeek(now: now, calendar: cal)
        let onsets = (UserDefaults.standard.array(forKey: onsetKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        let merged = NoiseExposureStore.shared.mergedAll.filter { week.contains($0.start) }
        let noiseVerified = !merged.contains { $0.origin == .zone }
        let hasCommute = !CommuteRecorder.shared.routes.filter { week.contains($0.start) }.isEmpty
        let r = WeeklyReport.build(week: week,
                                   noiseMinutes: merged.map { ($0.start, $0.leq) },
                                   routes: CommuteRecorder.shared.routes,
                                   focus: FocusManager.shared.log.map { ($0.date, $0.minutes) },
                                   onsets: onsets, calendar: cal,
                                   layoutVerified: noiseVerified && (!hasCommute || ZoneAQLayout.current.isVerified))
        lastReport = r
        return r
    }

    func checkWeeklyReport(now: Date = Date()) {
        guard ZoneSettings.shared.weeklyReport else { return }
        let last = UserDefaults.standard.object(forKey: reportKey) as? Date
        guard WeeklyReport.shouldSend(now: now, lastSentWeekStart: last, calendar: .current) else { return }
        var cal = Calendar.current; cal.firstWeekday = 2
        UserDefaults.standard.set(cal.dateInterval(of: .weekOfYear, for: now)?.start, forKey: reportKey)
        let r = buildLastWeek(now: now)
        guard !r.isEmpty else { return }
        notify(id: "report.weekly", title: "SleepPause 上周报告", body: r.summaryLines().joined(separator: "\n"))
    }

    private func notify(id: String, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}
