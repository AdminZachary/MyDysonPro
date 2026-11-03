import Foundation

/// "Good morning" card: how fast you fell asleep, how long you slept, and overnight noise.
/// Noise may be headphone playback level, Zone ambient, or Apple Watch environmental noise.
/// See `NoiseMerge` for which one is counted. Zone ambient is unverified; HealthKit is not.
struct MorningSummary: Codable, Equatable {
    var bedStart: Date?
    var onset: Date?
    var wake: Date
    var latencyMinutes: Double?
    var sleepMinutes: Double?
    var noiseLeq: Double?
    var noiseMax: Double?
    var noisyMinutes: Int          // minutes with Leq ≥ 55 dB while asleep
    var noiseSampleMinutes: Int
    var noiseVerified: Bool
    /// “耳机播放音量” or “环境噪音”. Missing in summaries saved before this field existed.
    var noiseLabel: String
    var smartAlarmEarlyMinutes: Double?

    init(bedStart: Date?, onset: Date?, wake: Date, latencyMinutes: Double?, sleepMinutes: Double?,
         noiseLeq: Double?, noiseMax: Double?, noisyMinutes: Int, noiseSampleMinutes: Int,
         noiseVerified: Bool, noiseLabel: String = "环境噪音", smartAlarmEarlyMinutes: Double?) {
        self.bedStart = bedStart
        self.onset = onset
        self.wake = wake
        self.latencyMinutes = latencyMinutes
        self.sleepMinutes = sleepMinutes
        self.noiseLeq = noiseLeq
        self.noiseMax = noiseMax
        self.noisyMinutes = noisyMinutes
        self.noiseSampleMinutes = noiseSampleMinutes
        self.noiseVerified = noiseVerified
        self.noiseLabel = noiseLabel
        self.smartAlarmEarlyMinutes = smartAlarmEarlyMinutes
    }

    static func build(bedStart: Date?, onset: Date?, wake: Date, noise: [(start: Date, leq: Double)],
                      layoutVerified: Bool, alarmDeadline: Date?, alarmEarly: Bool,
                      noiseLabel: String = "环境噪音") -> MorningSummary {
        let latency: Double? = {
            guard let b = bedStart, let o = onset, o >= b, o.timeIntervalSince(b) < 6 * 3600 else { return nil }
            return o.timeIntervalSince(b) / 60
        }()
        let slept: Double? = {
            guard let o = onset, wake > o, wake.timeIntervalSince(o) < 16 * 3600 else { return nil }
            return wake.timeIntervalSince(o) / 60
        }()
        let night = noise.filter { m in
            guard let o = onset else { return false }
            return m.start >= o && m.start < wake && m.leq.isFinite
        }
        var leq: Double?
        if !night.isEmpty {
            let e = night.reduce(0.0) { $0 + pow(10, $1.leq / 10) } / Double(night.count)
            leq = 10 * log10(e)
        }
        let early: Double? = (alarmEarly && alarmDeadline != nil && wake < alarmDeadline!)
            ? alarmDeadline!.timeIntervalSince(wake) / 60 : nil
        return MorningSummary(bedStart: bedStart, onset: onset, wake: wake, latencyMinutes: latency, sleepMinutes: slept,
                              noiseLeq: leq, noiseMax: night.map(\.leq).max(),
                              noisyMinutes: night.filter { $0.leq >= 55 }.count, noiseSampleMinutes: night.count,
                              noiseVerified: layoutVerified, noiseLabel: noiseLabel, smartAlarmEarlyMinutes: early)
    }

    var latencyRating: String? {
        guard let l = latencyMinutes else { return nil }
        return l < 10 ? "秒睡" : l <= 30 ? "正常" : "偏慢"
    }

    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) 小时 \(String(format: "%02d", m % 60)) 分" : "\(m) 分钟"
    }

    var headline: String {
        var parts: [String] = []
        if let l = latencyMinutes { parts.append("\(Self.hm(l))入睡") }
        if let s = sleepMinutes { parts.append("睡了 \(Self.hm(s))") }
        return parts.isEmpty ? "早上好" : parts.joined(separator: "，")
    }

    var lines: [String] {
        var out: [String] = []
        if let r = latencyRating, let l = latencyMinutes { out.append("入睡用时 \(Self.hm(l))（\(r)）") }
        if let s = sleepMinutes { out.append("睡眠时长约 \(Self.hm(s))（从检测到入睡算起）") }
        if let e = smartAlarmEarlyMinutes, e >= 1 { out.append("智能闹钟在浅睡时提前 \(Int(e.rounded())) 分钟叫醒你") }
        if let l = noiseLeq, let m = noiseMax {
            out.append(String(format: "夜间%@平均 %.0f dB，最高 %.0f dB，≥55 dB 共 %d 分钟", noiseLabel, l, m, noisyMinutes)
                       + (noiseVerified ? "" : "（未验证布局）"))
        } else {
            out.append("没有夜间噪音数据")
        }
        return out
    }
}

extension MorningSummary {
    enum CodingKeys: String, CodingKey {
        case bedStart, onset, wake, latencyMinutes, sleepMinutes, noiseLeq, noiseMax
        case noisyMinutes, noiseSampleMinutes, noiseVerified, noiseLabel, smartAlarmEarlyMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bedStart = try c.decodeIfPresent(Date.self, forKey: .bedStart)
        onset = try c.decodeIfPresent(Date.self, forKey: .onset)
        wake = try c.decode(Date.self, forKey: .wake)
        latencyMinutes = try c.decodeIfPresent(Double.self, forKey: .latencyMinutes)
        sleepMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepMinutes)
        noiseLeq = try c.decodeIfPresent(Double.self, forKey: .noiseLeq)
        noiseMax = try c.decodeIfPresent(Double.self, forKey: .noiseMax)
        noisyMinutes = try c.decode(Int.self, forKey: .noisyMinutes)
        noiseSampleMinutes = try c.decode(Int.self, forKey: .noiseSampleMinutes)
        noiseVerified = try c.decode(Bool.self, forKey: .noiseVerified)
        noiseLabel = try c.decodeIfPresent(String.self, forKey: .noiseLabel) ?? "环境噪音"
        smartAlarmEarlyMinutes = try c.decodeIfPresent(Double.self, forKey: .smartAlarmEarlyMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bedStart, forKey: .bedStart)
        try c.encodeIfPresent(onset, forKey: .onset)
        try c.encode(wake, forKey: .wake)
        try c.encodeIfPresent(latencyMinutes, forKey: .latencyMinutes)
        try c.encodeIfPresent(sleepMinutes, forKey: .sleepMinutes)
        try c.encodeIfPresent(noiseLeq, forKey: .noiseLeq)
        try c.encodeIfPresent(noiseMax, forKey: .noiseMax)
        try c.encode(noisyMinutes, forKey: .noisyMinutes)
        try c.encode(noiseSampleMinutes, forKey: .noiseSampleMinutes)
        try c.encode(noiseVerified, forKey: .noiseVerified)
        try c.encode(noiseLabel, forKey: .noiseLabel)
        try c.encodeIfPresent(smartAlarmEarlyMinutes, forKey: .smartAlarmEarlyMinutes)
    }
}
