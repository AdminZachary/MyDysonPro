import Foundation
import ActivityKit

/// Starts / updates / ends the air + noise Live Activity. Updates are throttled (ActivityKit has a budget).
@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var activity: Activity<ZoneActivityAttributes>?
    private var lastUpdate: Date?
    private var lastPushed: ZoneSnapshot?

    private init() {
        activity = Activity<ZoneActivityAttributes>.activities.first
        isRunning = activity != nil
    }

    var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(title: String, snapshot: ZoneSnapshot) {
        guard activity == nil else { update(snapshot, force: true); return }
        guard available else { lastError = "系统设置里关闭了“实时活动”"; return }
        do {
            activity = try Activity.request(attributes: ZoneActivityAttributes(title: title),
                                            content: .init(state: .init(snapshot: snapshot), staleDate: Date().addingTimeInterval(15 * 60)),
                                            pushType: nil)
            isRunning = true; lastError = nil; lastUpdate = Date(); lastPushed = snapshot
        } catch {
            lastError = error.localizedDescription
        }
    }

    func update(_ s: ZoneSnapshot, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        if !force, let l = lastUpdate, now.timeIntervalSince(l) < 30, lastPushed?.focusPhase == s.focusPhase { return }
        lastUpdate = now; lastPushed = s
        Task { await activity.update(.init(state: .init(snapshot: s), staleDate: now.addingTimeInterval(15 * 60))) }
    }

    func stop() {
        guard let a = activity else { return }
        activity = nil; isRunning = false
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
