import SwiftUI
import WatchKit
import HealthKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        if ScreenshotMode.isActive {
            MainActor.assumeIsolated {
                SleepMonitor.shared.applyScreenshot(bedtime: ScreenshotMode.screen == "bedtime")
            }
            return
        }
        WatchConnector.shared.activate()
        Task { @MainActor in SleepMonitor.shared.publishComplication() }
    }

    /// Called when the iPhone app calls `HKHealthStore.startWatchApp(with:)`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            SleepMonitor.shared.start()
        }
    }
}

@main
struct SleepPauseWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate
    @StateObject private var monitor = SleepMonitor.shared
    @StateObject private var settings = SleepSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(settings)
        }
    }
}
