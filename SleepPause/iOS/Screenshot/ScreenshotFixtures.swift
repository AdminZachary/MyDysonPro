import UIKit

/// Sample state for `-screenshotMode`. No Bluetooth, Health, or notification prompts.
@MainActor
enum ScreenshotFixtures {
    static func install() {
        let defaults = UserDefaults.standard
        let screen = ScreenshotMode.screen
        defaults.set(screen != "onboarding", forKey: "onboarding.done")
        defaults.set(HeadphoneKind.zone.rawValue, forKey: HeadphonePreference.key)
        defaults.set(true, forKey: "zone.enabled")
        defaults.set(false, forKey: "zone.noiseToHealth")
        defaults.set(false, forKey: "zone.commute")

        let wake = Date().addingTimeInterval(-3 * 3600)
        let onset = wake.addingTimeInterval(-8 * 3600)
        let bed = onset.addingTimeInterval(-20 * 60)
        defaults.set(onset.timeIntervalSince1970, forKey: "lastOnset")
        let morning = MorningSummary(
            bedStart: bed, onset: onset, wake: wake,
            latencyMinutes: 20, sleepMinutes: 8 * 60,
            noiseLeq: 48, noiseMax: 61, noisyMinutes: 12, noiseSampleMinutes: 480,
            noiseVerified: true, noiseLabel: "环境噪音", smartAlarmEarlyMinutes: 14)
        if let data = try? JSONEncoder().encode(morning) {
            defaults.set(data, forKey: "morning.last")
        }
        defaults.set(onsets(latest: onset).map(\.timeIntervalSince1970), forKey: "sleep.onsets")

        UIView.setAnimationsEnabled(false)
        ZoneManager.shared.applyScreenshotFixture()
        NoiseExposureStore.shared.applyScreenshotFixture(dosePercent: 35)
        FocusManager.shared.applyScreenshotFixture()
        _ = ZoneAutomations.shared.buildLastWeek()
        AppModel.shared.applyScreenshotFixture(armed: screen == "sleep")
    }

    /// Evenings at 23:18 for the sleep chart and the weekly report.
    private static func onsets(latest: Date) -> [Date] {
        let cal = Calendar.current
        return (0..<10).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: latest) else { return nil }
            return cal.date(bySettingHour: 23, minute: 18, second: 0, of: day)
        }
    }
}
