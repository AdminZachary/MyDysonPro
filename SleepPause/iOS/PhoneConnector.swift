import Foundation
import WatchConnectivity

/// iPhone side of WatchConnectivity. A `sendMessage` from the watch wakes this app in the
/// background; `transferUserInfo` is delivered when the system decides (often next launch).
final class PhoneConnector: NSObject, WCSessionDelegate {
    static let shared = PhoneConnector()
    var onMessage: ((SleepMessage, String) -> Void)?
    var onStateChange: (() -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    var isPaired: Bool { session?.isPaired ?? false }
    var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
    var isReachable: Bool { session?.isReachable ?? false }

    func sendStopToWatch() {
        guard let session, session.isReachable else { return }
        session.sendMessage(["command": "stop"], replyHandler: nil, errorHandler: nil)
    }

    private func deliver(_ dict: [String: Any], via channel: String) {
        guard let msg = SleepMessage(dictionary: dict) else { return }
        DispatchQueue.main.async { self.onMessage?(msg, channel) }
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.onStateChange?() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { self.onStateChange?() } }
    func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { self.onStateChange?() } }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message, via: "sendMessage")
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        deliver(message, via: "sendMessage")
        replyHandler(["ok": true])
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo, via: "transferUserInfo")
    }
}
