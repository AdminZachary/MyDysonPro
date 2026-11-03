import Foundation

/// Daily noise dose using the 85 dBA / 8 h criterion with a 3 dB exchange rate (NIOSH-style).
/// dose% = 100 * Σ(10^(L/10)·dt) / (8h · 10^(8.5)).  LEX,8h = 10·log10(Σ(10^(L/10)·dt) / 8h).
struct ExposureAccumulator: Codable, Equatable {
    var dayStart: Date
    var energySum: Double = 0          // Σ 10^(L/10) * seconds
    var secondsCounted: Double = 0
    var alerted = false
    var lastSample: Date?

    static let criterionDb = 85.0
    static let referenceSeconds = 8.0 * 3600

    init(dayStart: Date) { self.dayStart = dayStart }

    /// Adds a level held since the previous sample (capped at `maxGap` to ignore disconnects).
    /// Returns true exactly once per day when the dose first reaches 100 %.
    mutating func add(levelDb: Double, at date: Date, maxGap: TimeInterval = 60,
                      calendar: Calendar = .current) -> Bool {
        if !calendar.isDate(date, inSameDayAs: dayStart) {
            self = ExposureAccumulator(dayStart: calendar.startOfDay(for: date))
        }
        defer { lastSample = date }
        guard levelDb.isFinite, levelDb > 0, levelDb < 150, let prev = lastSample else { return false }
        let dt = min(max(0, date.timeIntervalSince(prev)), maxGap)
        guard dt > 0 else { return false }
        energySum += pow(10, levelDb / 10) * dt
        secondsCounted += dt
        if !alerted && dosePercent >= 100 {
            alerted = true
            return true
        }
        return false
    }

    var dosePercent: Double {
        100 * energySum / (Self.referenceSeconds * pow(10, Self.criterionDb / 10))
    }

    var lex8h: Double? { energySum > 0 ? 10 * log10(energySum / Self.referenceSeconds) : nil }

    var leq: Double? { secondsCounted > 0 ? 10 * log10(energySum / secondsCounted) : nil }
}

/// Equivalent continuous level of a set of (level, seconds) pairs — used for 1-minute Leq samples.
enum Leq {
    static func of(_ parts: [(db: Double, seconds: Double)]) -> Double? {
        let total = parts.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        let e = parts.reduce(0) { $0 + pow(10, $1.db / 10) * $1.seconds }
        return 10 * log10(e / total)
    }
}
