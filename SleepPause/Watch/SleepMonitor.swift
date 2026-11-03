import Foundation
import HealthKit
import CoreMotion
import Combine
import WatchKit
import WidgetKit

/// Runs an overnight HKWorkoutSession (.mindAndBody) so the watch keeps sampling heart rate and
/// stays alive in the background, reads heart rate via HKAnchoredObjectQuery and the wrist
/// accelerometer via CMMotionManager, and feeds both into `SleepOnsetDetector`.
@MainActor
final class SleepMonitor: NSObject, ObservableObject {
    static let shared = SleepMonitor()

    enum State: Equatable { case idle, starting, running, detected(Date), error(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var status: SleepDetectorStatus?
    @Published private(set) var lastHR: Double?
    @Published private(set) var startedAt: Date?
    /// Latest 30 s movement index (for the live stillness indicator).
    @Published private(set) var movement: Double?
    @Published private(set) var alarmDeadline: Date?
    @Published private(set) var alarmFiring = false
    private var alarm: SmartAlarmPlanner?
    private var alarmHapticTimer: Timer?
    private var alarmHapticCount = 0

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var hrQuery: HKAnchoredObjectQuery?
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "SleepPause.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var evalTimer: Timer?
    /// Detector is touched from HealthKit / CoreMotion background queues, so it lives in a
    /// lock-protected, non-actor-isolated box.
    private nonisolated let box = LockedDetector()

    private let heartRateType = HKQuantityType(.heartRate)

    var isRunning: Bool {
        if case .running = state { return true }
        if case .starting = state { return true }
        return false
    }

    // MARK: Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType, HKObjectType.workoutType()]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            state = .error("HealthKit 授权失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: Start / stop

    func start() {
        guard !isRunning else { return }
        state = .starting
        Task {
            guard await requestAuthorization() else {
                if case .starting = state { state = .error("没有 HealthKit 权限") }
                return
            }
            do {
                try startWorkout()
            } catch {
                state = .error("无法开始监测：\(error.localizedDescription)")
            }
        }
    }

    private func startWorkout() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        session.delegate = self
        self.session = session
        self.builder = builder

        let now = Date()
        startedAt = now
        let cfg = SleepSettings.shared.config
        box.withDetector { $0.reset(startDate: now, config: cfg) }
        let alarmCfg = SleepSettings.shared.alarm
        alarm = alarmCfg.enabled ? SmartAlarmPlanner(config: alarmCfg, start: now) : nil
        alarmDeadline = alarm?.deadline

        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { _, error in
            if let error { NSLog("[SleepPause] beginCollection error: \(error.localizedDescription)") }
        }

        startHeartRateQuery(from: now)
        startMotion()
        startEvaluationTimer()

        state = .running
        WatchConnector.shared.send(SleepMessage(type: .sessionStarted, date: now))
        publishComplication()
    }

    func stop() {
        stopAlarmHaptics()
        alarm = nil
        alarmDeadline = nil
        evalTimer?.invalidate()
        evalTimer = nil
        motion.stopAccelerometerUpdates()
        if let hrQuery { healthStore.stop(hrQuery) }
        hrQuery = nil

        if let session {
            session.end()
        }
        // We don't want a "Mind & Body" workout cluttering Fitness every night.
        builder?.discardWorkout()
        session = nil
        builder = nil

        if case .detected = state {
            // keep the detected state visible
        } else {
            state = .idle
        }
        WatchConnector.shared.send(SleepMessage(type: .sessionStopped, date: Date()))
        publishComplication()
    }

    /// "I'm awake" on the alarm screen.
    func dismissAlarm() {
        stopAlarmHaptics()
        stop()
        state = .idle
        publishComplication()
    }

    func resetDisplay() {
        if !isRunning { state = .idle; status = nil; lastHR = nil }
    }

    /// Sends a test "sleep onset" to the phone without needing to fall asleep.
    func sendTest() {
        WatchConnector.shared.send(SleepMessage(type: .testPause, date: Date(),
                                                baselineHR: status?.baselineHR,
                                                currentHR: status?.currentHR,
                                                stillMinutes: status?.stillMinutes))
    }

    // MARK: Heart rate

    private func startHeartRateQuery(from start: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let box = self.box
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] _, samples, _, _, error in
            if let error { NSLog("[SleepPause] HR query error: \(error.localizedDescription)"); return }
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let values = samples.map { ($0.quantity.doubleValue(for: unit), $0.endDate) }
            box.withDetector { d in
                for (bpm, date) in values { d.addHeartRate(bpm, at: date) }
            }
            let latest = values.max(by: { $0.1 < $1.1 })?.0
            Task { @MainActor [weak self] in self?.lastHR = latest }
        }
        let query = HKAnchoredObjectQuery(type: heartRateType, predicate: predicate, anchor: nil,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        healthStore.execute(query)
        hrQuery = query
    }

    // MARK: Motion

    private func startMotion() {
        guard motion.isAccelerometerAvailable else {
            NSLog("[SleepPause] accelerometer unavailable")
            return
        }
        motion.accelerometerUpdateInterval = 1.0 / 10.0   // 10 Hz is plenty for stillness
        let box = self.box
        motion.startAccelerometerUpdates(to: motionQueue) { @Sendable data, _ in
            guard let a = data?.acceleration else { return }
            // CMAccelerometerData.timestamp is uptime-based; wall clock is fine for 30 s epochs.
            let now = Date()
            box.withDetector { $0.addAcceleration(x: a.x, y: a.y, z: a.z, at: now) }
        }
    }

    // MARK: Evaluation

    private func startEvaluationTimer() {
        evalTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        evalTimer = t
    }

    private func evaluate() {
        let now = Date()
        let (s, epochs) = box.withDetector { d in (d.evaluate(at: now), d.recentEpochs) }
        status = s
        movement = epochs.last?.movement
        runAlarm(epochs: epochs, now: now)

        if case .asleep(let onset) = s.phase, state == .running {
            state = .detected(onset)
            // No haptics on purpose – we don't want to wake you up.
            WatchConnector.shared.send(SleepMessage(type: .sleepOnset, date: onset,
                                                    baselineHR: s.baselineHR,
                                                    currentHR: s.currentHR,
                                                    stillMinutes: s.stillMinutes))
            publishComplication()
            // With the smart alarm on we keep the session (and motion sensing) running until morning.
            if SleepSettings.shared.endSessionAfterDetection && alarm == nil {
                // Give WatchConnectivity a few seconds before the workout (and our background time) ends.
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    self?.stop()
                }
            }
        }
    }
}

// MARK: - Smart alarm & complication

extension SleepMonitor {
    private func runAlarm(epochs: [(end: Date, movement: Double)], now: Date) {
        guard var a = alarm, !alarmFiring else { return }
        for e in epochs { a.addEpoch(end: e.end, movement: e.movement) }
        let decision = a.evaluate(at: now)
        alarm = a
        switch decision {
        case .none: break
        case .gentleTap:
            WKInterfaceDevice.current().play(.directionUp)          // a light nudge out of deep sleep
        case .wake(let early):
            alarmFiring = true
            startAlarmHaptics()
            let before = max(0, a.deadline.timeIntervalSince(now) / 60)
            WatchConnector.shared.send(SleepMessage(type: .woke, date: now, baselineHR: status?.baselineHR,
                                                    currentHR: status?.currentHR, stillMinutes: early ? before : 0))
            publishComplication()
        }
    }

    private func startAlarmHaptics() {
        alarmHapticTimer?.invalidate()
        alarmHapticCount = 0
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.alarmHapticTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        alarmHapticTimer = t
    }

    private func alarmHapticTick() {
        alarmHapticCount += 1
        // gentle at first, stronger after ~30 s; give up after ~3 min
        WKInterfaceDevice.current().play(alarmHapticCount < 12 ? .directionUp : .notification)
        if alarmHapticCount > 72 { alarmHapticTimer?.invalidate(); alarmHapticTimer = nil }
    }

    private func stopAlarmHaptics() {
        alarmHapticTimer?.invalidate()
        alarmHapticTimer = nil
        alarmFiring = false
    }

    func publishComplication() {
        let phase: WatchStatusSnapshot.Phase
        var since: Date? = startedAt
        if alarmFiring { phase = .alarm }
        else {
            switch state {
            case .running, .starting: phase = .monitoring
            case .detected(let d): phase = .asleep; since = d
            default: phase = .idle; since = nil
            }
        }
        WatchStatusSnapshot(phase: phase, since: since, alarm: alarmDeadline ?? nextAlarmPreview(), updated: Date()).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func nextAlarmPreview() -> Date? {
        let c = SleepSettings.shared.alarm
        guard c.enabled else { return nil }
        return SmartAlarmPlanner.nextDeadline(after: Date(), hour: c.hour, minute: c.minute, calendar: .current)
    }
}

extension SleepMonitor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        NSLog("[SleepPause] workout state \(fromState.rawValue) -> \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .error("监测会话出错：\(error.localizedDescription)")
        }
    }
}

/// Lock-protected wrapper so the detector can be fed from background queues.
final class LockedDetector: @unchecked Sendable {
    private let lock = NSLock()
    private let detector = SleepOnsetDetector()

    func withDetector<T>(_ body: (SleepOnsetDetector) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(detector)
    }
}
