import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity. Sends with `sendMessage` when the phone is reachable
/// (this wakes the iOS app in the background), and falls back to `transferUserInfo`
/// (queued, guaranteed delivery, but may be delayed until the iOS app runs).
final class WatchConnector: NSObject, WCSessionDelegate {
    static let shared = WatchConnector()
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session, session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    var isReachable: Bool { session?.isReachable ?? false }

    func send(_ message: SleepMessage) {
        guard let session else { return }
        if session.activationState != .activated { activate() }
        let payload = message.dictionary
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { error in
                NSLog("[SleepPause] sendMessage failed: \(error.localizedDescription) – falling back to transferUserInfo")
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { NSLog("[SleepPause] WC activation error: \(error.localizedDescription)") }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncoming(message)
        replyHandler(["ok": true])
    }

    private func handleIncoming(_ dict: [String: Any]) {
        // The phone may ask the watch to stop monitoring.
        if let cmd = dict["command"] as? String, cmd == "stop" {
            Task { @MainActor in SleepMonitor.shared.stop() }
        }
    }
}
