import AVFoundation
import Foundation

/// Reads the current output route and suggests a headphone choice. Never writes the setting.
enum HeadphoneRoute {
    static func suggestion() -> HeadphoneKind? {
        for output in AVAudioSession.sharedInstance().currentRoute.outputs {
            if let kind = HeadphoneKind.suggest(portType: output.portType.rawValue, portName: output.portName) {
                return kind
            }
        }
        return nil
    }
}
