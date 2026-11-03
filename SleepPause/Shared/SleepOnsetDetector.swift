import Foundation

/// Tunable thresholds for sleep-onset detection.
struct SleepDetectorConfig: Equatable, Codable {
    /// Wrist must be continuously still for this many minutes.
    var stillMinutes: Double = 12
    /// Recent heart rate must be at least this many percent below the awake baseline.
    var hrDropPercent: Double = 10
    /// Baseline heart rate is taken from the first N minutes after start (you are still awake).
    var baselineMinutes: Double = 5
    /// Window used to compute the "current" heart rate (median), in minutes.
    var currentHRWindowMinutes: Double = 5
    /// Movement index (in g) above which a 30 s epoch counts as "moving".
    var movementThresholdG: Double = 0.02
    /// Length of one motion epoch, in seconds.
    var epochSeconds: Double = 30
    /// If false, detection uses stillness only (fallback when HR is unavailable).
    var requireHeartRate: Bool = true
    /// Minimum HR samples needed for a baseline / current estimate.
    var minHRSamples: Int = 3
}

enum SleepDetectorPhase: Equatable {
    case collectingBaseline   // still inside the baseline window
    case monitoring           // waiting for stillness + HR drop
    case asleep(Date)         // onset detected at date
}

struct SleepDetectorStatus: Equatable {
    var phase: SleepDetectorPhase
    var baselineHR: Double?
    var currentHR: Double?
    var stillMinutes: Double
    var hrConditionMet: Bool
    var stillConditionMet: Bool
}

/// Pure-logic sleep-onset detector. No Apple frameworks, so it can be tested anywhere.
///
/// Motion: feed raw accelerometer samples (x, y, z in g). Each epoch's movement index is the
/// mean absolute change of the acceleration vector between consecutive samples (a simple
/// high-pass "jerk" that ignores gravity / wrist orientation). An epoch above the threshold
/// resets the stillness timer.
///
/// Heart rate: baseline = median of samples in the first `baselineMinutes`; current = median
/// of samples in the last `currentHRWindowMinutes`.
final class SleepOnsetDetector {
    private(set) var config: SleepDetectorConfig
    private(set) var startDate: Date
    private(set) var onsetDate: Date?

    private var hrSamples: [(date: Date, bpm: Double)] = []
    private var lastAccel: (x: Double, y: Double, z: Double)?
    private var epochStart: Date?
    private var epochSum: Double = 0
    private var epochCount: Int = 0
    /// Start of the current uninterrupted still period (nil until first still epoch).
    private var stillSince: Date?
    private var lastEpochEnd: Date?
    /// Recent epochs (end, movement index) for the smart alarm and the live UI. Bounded.
    private(set) var recentEpochs: [(end: Date, movement: Double)] = []
    var lastMovementIndex: Double? { recentEpochs.last?.movement }

    init(config: SleepDetectorConfig = SleepDetectorConfig(), startDate: Date = Date()) {
        self.config = config
        self.startDate = startDate
    }

    func reset(startDate: Date = Date(), config: SleepDetectorConfig? = nil) {
        if let config { self.config = config }
        self.startDate = startDate
        onsetDate = nil
        hrSamples.removeAll()
        lastAccel = nil
        epochStart = nil
        epochSum = 0
        epochCount = 0
        stillSince = nil
        lastEpochEnd = nil
        recentEpochs.removeAll()
    }

    // MARK: Input

    func addHeartRate(_ bpm: Double, at date: Date) {
        guard bpm > 20, bpm < 250 else { return }
        hrSamples.append((date, bpm))
        // Keep memory bounded: drop samples older than 2h except the baseline window.
        let keepAfter = date.addingTimeInterval(-2 * 3600)
        let baselineEnd = startDate.addingTimeInterval(config.baselineMinutes * 60)
        if hrSamples.count > 5000 {
            hrSamples.removeAll { $0.date < keepAfter && $0.date > baselineEnd }
        }
    }

    func addAcceleration(x: Double, y: Double, z: Double, at date: Date) {
        if epochStart == nil { epochStart = date }
        if let last = lastAccel {
            let dx = x - last.x, dy = y - last.y, dz = z - last.z
            epochSum += (dx * dx + dy * dy + dz * dz).squareRoot()
            epochCount += 1
        }
        lastAccel = (x, y, z)
        if let es = epochStart, date.timeIntervalSince(es) >= config.epochSeconds {
            closeEpoch(at: date)
        }
    }

    /// Feed a pre-computed movement index for one epoch (useful for tests / other sources).
    func addEpoch(movementIndex: Double, endingAt date: Date) {
        registerEpoch(movementIndex: movementIndex, end: date)
    }

    private func closeEpoch(at date: Date) {
        let index = epochCount > 0 ? epochSum / Double(epochCount) : 0
        registerEpoch(movementIndex: index, end: date)
        epochStart = date
        epochSum = 0
        epochCount = 0
    }

    private func registerEpoch(movementIndex: Double, end: Date) {
        let start = lastEpochEnd ?? end.addingTimeInterval(-config.epochSeconds)
        if movementIndex > config.movementThresholdG {
            stillSince = nil
        } else if stillSince == nil {
            stillSince = start
        }
        lastEpochEnd = end
        recentEpochs.append((end, movementIndex))
        if recentEpochs.count > 40 { recentEpochs.removeFirst(recentEpochs.count - 40) }
    }

    // MARK: Evaluation

    var baselineHR: Double? {
        let end = startDate.addingTimeInterval(config.baselineMinutes * 60)
        let values = hrSamples.filter { $0.date >= startDate && $0.date <= end }.map { $0.bpm }
        guard values.count >= config.minHRSamples else { return nil }
        return Self.median(values)
    }

    func currentHR(at now: Date) -> Double? {
        let from = now.addingTimeInterval(-config.currentHRWindowMinutes * 60)
        let values = hrSamples.filter { $0.date >= from && $0.date <= now }.map { $0.bpm }
        guard values.count >= config.minHRSamples else { return nil }
        return Self.median(values)
    }

    func stillMinutes(at now: Date) -> Double {
        guard let s = stillSince else { return 0 }
        return max(0, now.timeIntervalSince(s) / 60)
    }

    /// Evaluate at `now`. Once onset is detected it latches until `reset`.
    @discardableResult
    func evaluate(at now: Date = Date()) -> SleepDetectorStatus {
        let baseline = baselineHR
        let current = currentHR(at: now)
        let still = stillMinutes(at: now)
        let stillOK = still >= config.stillMinutes

        var hrOK = false
        if let b = baseline, let c = current {
            hrOK = c <= b * (1 - config.hrDropPercent / 100)
        }
        if !config.requireHeartRate { hrOK = true }

        if let onset = onsetDate {
            return SleepDetectorStatus(phase: .asleep(onset), baselineHR: baseline, currentHR: current,
                                       stillMinutes: still, hrConditionMet: hrOK, stillConditionMet: stillOK)
        }

        let inBaselineWindow = now.timeIntervalSince(startDate) < config.baselineMinutes * 60
        if inBaselineWindow {
            return SleepDetectorStatus(phase: .collectingBaseline, baselineHR: baseline, currentHR: current,
                                       stillMinutes: still, hrConditionMet: hrOK, stillConditionMet: stillOK)
        }

        if stillOK && hrOK {
            onsetDate = now
            return SleepDetectorStatus(phase: .asleep(now), baselineHR: baseline, currentHR: current,
                                       stillMinutes: still, hrConditionMet: hrOK, stillConditionMet: stillOK)
        }
        return SleepDetectorStatus(phase: .monitoring, baselineHR: baseline, currentHR: current,
                                   stillMinutes: still, hrConditionMet: hrOK, stillConditionMet: stillOK)
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        if n == 0 { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
