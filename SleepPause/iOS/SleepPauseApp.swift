import SwiftUI
import UIKit

final class SleepPauseAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            // Wire the optional Dyson Zone module. bootstrap() must run at launch so that
            // CoreBluetooth state restoration (relaunch in background) can hand the peripheral back.
            let zone = ZoneManager.shared
            zone.onReading = { reading in
                NoiseExposureStore.shared.ingest(reading, worn: ZoneManager.shared.worn)
                CommuteRecorder.shared.ingest(reading)
                ZoneAutomations.shared.ingest(reading)     // fan boost, widgets, Live Activity, weekly report
            }
            zone.onWornChange = { worn in
                AppModel.shared.zoneWornChanged(worn)
                FocusManager.shared.wornChanged(worn)
            }
            ZoneAutomations.shared.wire()
            if ZoneSettings.shared.moduleEnabled { zone.bootstrap() }
            if ZoneSettings.shared.commuteRecording { CommuteRecorder.shared.start() }
        }
        return true
    }
}

@main
struct SleepPauseApp: App {
    @UIApplicationDelegateAdaptor(SleepPauseAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
