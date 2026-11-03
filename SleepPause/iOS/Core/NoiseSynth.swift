import Foundation

/// Live-generated sleep noise (no loops, nothing to download) — like Veil / Noise Machine / Rest Easy.
enum NoiseColor: String, CaseIterable, Codable {
    case brown, pink, white
    var label: String { switch self { case .brown: return "棕噪音"; case .pink: return "粉噪音"; case .white: return "白噪音" } }
    var symbol: String { switch self { case .brown: return "water.waves"; case .pink: return "cloud.rain"; case .white: return "wind" } }
}

/// Deterministic, allocation-free generator (xorshift RNG) so it is safe on the audio thread.
struct NoiseSynth {
    var color: NoiseColor
    private var rng: UInt64
    private var brown: Double = 0
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0

    init(color: NoiseColor, seed: UInt64 = 0x9E3779B97F4A7C15) {
        self.color = color
        self.rng = seed == 0 ? 1 : seed
    }

    private mutating func white() -> Double {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Double(rng % 2_000_001) / 1_000_000.0 - 1.0     // [-1, 1]
    }

    mutating func next() -> Float {
        let w = white()
        let v: Double
        switch color {
        case .white:
            v = w * 0.5
        case .pink:   // Paul Kellet's refined pink filter
            b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520; b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
            v = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
            b6 = w * 0.115926
        case .brown:  // leaky integrator
            brown = (brown + 0.02 * w) / 1.02
            v = brown * 3.5
        }
        return Float(max(-1, min(1, v)))
    }

    mutating func fill(_ buffer: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
        for i in 0..<count { buffer[i] = next() * gain }
    }
}

/// Smooth fades: equal-power (cosine) curve, so the end never "drops".
struct FadeEnvelope: Equatable {
    var from: Double
    var to: Double
    var start: Date
    var duration: TimeInterval

    func gain(at now: Date) -> Double {
        guard duration > 0 else { return to }
        let x = min(1, max(0, now.timeIntervalSince(start) / duration))
        let s = (1 - cos(Double.pi * x)) / 2          // 0 → 1 smoothly
        return from + (to - from) * s
    }
    func isFinished(at now: Date) -> Bool { now.timeIntervalSince(start) >= duration }
}
