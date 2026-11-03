#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island showing air + noise (inspired by Paku and SoundGuard).
struct ZoneActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var snapshot: ZoneSnapshot
    }
    var title: String
}
#endif
