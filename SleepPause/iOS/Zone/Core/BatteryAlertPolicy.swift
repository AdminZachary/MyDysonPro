import Foundation

/// Low-battery notifications (like MagicPods / CAPod) and a bedtime charge check.
/// Uses 2DD1201E battery percent, which dyson-zone-companion reads on real hardware.
struct BatteryAlertPolicy: Codable, Equatable {
    var thresholds: [Int] = [20, 10]
    private(set) var fired: Set<Int> = []

    /// Returns the threshold that was just crossed downward (fires once until the battery recovers).
    mutating func update(percent: Int?) -> Int? {
        guard let p = percent, (0...100).contains(p) else { return nil }
        for t in thresholds where p > t + 5 { fired.remove(t) }   // re-arm after charging
        guard let t = thresholds.sorted().first(where: { p <= $0 && !fired.contains($0) }) else { return nil }
        for u in thresholds where u >= t { fired.insert(u) }      // don't fire 20 % right after 10 %
        return t
    }

    static func bedtimeWarning(percent: Int?, minimum: Int = 30) -> String? {
        guard let p = percent, p < minimum else { return nil }
        return "Zone 电量只有 \(p)%，可能撑不过今晚。入睡判定和暂停不受影响，但耳机可能半夜关机。"
    }
}
