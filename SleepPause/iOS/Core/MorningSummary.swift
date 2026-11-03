import Foundation

/// "Good morning" card: how fast you fell asleep (Sleep Cycle's "Asleep after"), how long you
/// slept, and the room noise overnight from the Zone (Pillow-style environmental audio levels).
/// ⚠️ The noise part relies on the UNVERIFIED 2DD1201D layout and only exists if the Zone stayed
/// connected and worn; otherwise those fields are nil.
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
    var smartAlarmEarlyMinutes: Double?

    static func build(bedStart: Date?, onset: Date?, wake: Date, noise: [(start: Date, leq: Double)],
                      layoutVerified: Bool, alarmDeadline: Date?, alarmEarly: Bool) -> MorningSummary {
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
                              noiseVerified: layoutVerified, smartAlarmEarlyMinutes: early)
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
            out.append(String(format: "夜间环境噪音平均 %.0f dB，最高 %.0f dB，≥55 dB 共 %d 分钟", l, m, noisyMinutes)
                       + (noiseVerified ? "" : "（未验证布局）"))
        } else {
            out.append("没有夜间噪音数据（需要整夜连接并佩戴 Zone）")
        }
        return out
    }
}
