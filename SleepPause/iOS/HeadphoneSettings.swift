import Combine
import Foundation

/// The person's headphones. Non-Zone choices turn the Zone module off so BLE,
/// ANC and the air features stay hidden. The saved choice is what onboarding asks for.
@MainActor
final class HeadphoneSettings: ObservableObject {
    static let shared = HeadphoneSettings()
    private let defaults = UserDefaults.standard

    @Published var kind: HeadphoneKind {
        didSet {
            defaults.set(kind.rawValue, forKey: HeadphonePreference.key)
            apply()
        }
    }

    var usesZone: Bool { kind.usesZone }

    private init() {
        kind = HeadphonePreference.current()
    }

    func apply() {
        guard !ScreenshotMode.isActive else { return }
        if kind.usesZone {
            if !ZoneSettings.shared.moduleEnabled {
                ZoneSettings.shared.moduleEnabled = true
            }
            ZoneManager.shared.bootstrap()
        } else if ZoneSettings.shared.moduleEnabled {
            ZoneSettings.shared.moduleEnabled = false
            ZoneManager.shared.shutdown()
        }
    }
}
