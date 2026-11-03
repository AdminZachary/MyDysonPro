import Foundation

// Plain assertion-based checks that run on Linux/macOS without XCTest:
//   scripts/linux-check.sh
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("PASS  \(msg)") } else { print("FAIL  \(msg)"); failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

// 1. Message round trip
let m = SleepMessage(type: .sleepOnset, date: t0, baselineHR: 68, currentHR: 58, stillMinutes: 13)
let back = SleepMessage(dictionary: m.dictionary)
check(back == m, "SleepMessage dictionary round-trip")
check(SleepMessage(dictionary: ["type": "nope", "date": 1.0]) == nil, "unknown type rejected")

// Simulate: awake 0-5 min HR 70 with movement, then falls still; HR drifts to 60 from minute 10.
func simulate(config: SleepDetectorConfig, hrAfter: Double, moveUntilMin: Double, totalMin: Double) -> Date? {
    let d = SleepOnsetDetector(config: config, startDate: t0)
    var t = 0.0
    var onset: Date?
    var phase = 0.0
    while t <= totalMin * 60 {
        let now = t0.addingTimeInterval(t)
        // accelerometer at 10 Hz
        for i in 0..<10 {
            let ts = now.addingTimeInterval(Double(i) / 10)
            let moving = t < moveUntilMin * 60
            phase += 1
            let wobble = moving ? 0.2 * sin(phase) : 0.001 * sin(phase)
            d.addAcceleration(x: wobble, y: 0, z: -1 + wobble / 2, at: ts)
        }
        if Int(t) % 5 == 0 {
            let hr = t < 10 * 60 ? 70.0 : hrAfter
            d.addHeartRate(hr, at: now)
        }
        if Int(t) % 30 == 0 {
            let s = d.evaluate(at: now)
            if case .asleep(let o) = s.phase, onset == nil { onset = o }
        }
        t += 1
    }
    return onset
}

var cfg = SleepDetectorConfig()
// 2. Normal sleep: still from minute 6, HR 60 (>10% drop) -> onset ~ 6 + 12 = 18 min
if let o = simulate(config: cfg, hrAfter: 60, moveUntilMin: 6, totalMin: 40) {
    let mins = o.timeIntervalSince(t0) / 60
    check(mins >= 17.5 && mins <= 20, "onset detected after ~18 min (got \(mins))")
} else { check(false, "onset detected in normal sleep") }

// 3. Lying still but HR not dropping (awake, reading) -> no onset
check(simulate(config: cfg, hrAfter: 68, moveUntilMin: 6, totalMin: 40) == nil, "no onset when HR stays at baseline")

// 4. Keeps moving -> no onset
check(simulate(config: cfg, hrAfter: 55, moveUntilMin: 40, totalMin: 40) == nil, "no onset while moving")

// 5. Stillness-only mode
cfg.requireHeartRate = false
if let o = simulate(config: cfg, hrAfter: 70, moveUntilMin: 6, totalMin: 40) {
    let mins = o.timeIntervalSince(t0) / 60
    check(mins >= 17.5 && mins <= 20, "stillness-only onset ~18 min (got \(mins))")
} else { check(false, "stillness-only onset") }

// 6. Median helper
check(SleepOnsetDetector.median([3, 1, 2]) == 2 && SleepOnsetDetector.median([1, 2, 3, 4]) == 2.5, "median")

// 7. Silent WAV
let wav = SilentAudio.wavData(seconds: 1, sampleRate: 8000)
check(wav.count == 44 + 16000 && String(data: wav.prefix(4), encoding: .ascii) == "RIFF", "silent WAV header/size")

failures += runZoneChecks()
failures += runExtrasChecks()
failures += runPolishChecks()
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
