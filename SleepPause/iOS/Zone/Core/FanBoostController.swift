import Foundation

/// "Pollution boost": raise the Zone fan when NO₂ or VOC spikes, restore the previous level when
/// the air has been clean again for a while. Inspired by Home Assistant's
/// `voc_crossed_threshold` + `fan.increase_speed` automations.
///
/// ⚠️ NO₂ / VOC come from 2DD1201D whose layout is UNVERIFIED. Missing values => no action.
struct FanBoostConfig: Codable, Equatable {
    var no2HighPpb: Double = 53       // ≈ US AQI "moderate→unhealthy for sensitive" band edge
    var no2ClearPpb: Double = 35
    var vocHighPpb: Double = 500
    var vocClearPpb: Double = 300
    var boostLevel: Int = 3           // 0 off … 3 moderate
    var sustainSeconds: Double = 20   // spike must last this long before boosting / clearing
    var minBoostSeconds: Double = 120 // keep the boost at least this long
    var cooldownSeconds: Double = 300 // wait after a restore before boosting again
}

enum FanBoostAction: Equatable {
    case boost(to: Int, reason: String)
    case restore(to: Int)
}

final class FanBoostController {
    var config: FanBoostConfig
    private(set) var isBoosting = false
    private(set) var savedLevel: Int?
    private var highSince: Date?
    private var clearSince: Date?
    private var boostedAt: Date?
    private var restoredAt: Date?

    init(config: FanBoostConfig = FanBoostConfig()) { self.config = config }

    /// The user picked a fan level by hand: forget the boost, don't restore over their choice.
    func noteManualChange() {
        isBoosting = false; savedLevel = nil; highSince = nil; clearSince = nil
    }

    /// - held: true while the sleep watch is active / after sleep onset (never boost at night).
    /// - visorAttached: from 2DD12005 when known; `false` => fan boost is pointless, do nothing.
    func update(no2: Double?, voc: Double?, at now: Date, currentLevel: Int?,
                held: Bool, visorAttached: Bool?) -> FanBoostAction? {
        if held || visorAttached == false {
            isBoosting = false; savedLevel = nil; highSince = nil; clearSince = nil
            return nil
        }
        let n = no2.flatMap { $0.isFinite ? $0 : nil }, v = voc.flatMap { $0.isFinite ? $0 : nil }
        guard n != nil || v != nil else { return nil }          // no data: degrade gracefully
        let high = (n.map { $0 >= config.no2HighPpb } ?? false) || (v.map { $0 >= config.vocHighPpb } ?? false)
        let clear = (n.map { $0 <= config.no2ClearPpb } ?? true) && (v.map { $0 <= config.vocClearPpb } ?? true)

        if !isBoosting {
            guard high else { highSince = nil; return nil }
            if highSince == nil { highSince = now }
            guard now.timeIntervalSince(highSince!) >= config.sustainSeconds else { return nil }
            if let r = restoredAt, now.timeIntervalSince(r) < config.cooldownSeconds { return nil }
            let cur = currentLevel ?? 0
            guard cur < config.boostLevel else { return nil }
            isBoosting = true; savedLevel = cur; boostedAt = now; clearSince = nil
            var why: [String] = []
            if let n, n >= config.no2HighPpb { why.append(String(format: "NO₂ %.0f ppb", n)) }
            if let v, v >= config.vocHighPpb { why.append(String(format: "VOC %.0f ppb", v)) }
            return .boost(to: config.boostLevel, reason: why.joined(separator: "、"))
        } else {
            guard clear else { clearSince = nil; return nil }
            if clearSince == nil { clearSince = now }
            guard now.timeIntervalSince(clearSince!) >= config.sustainSeconds,
                  now.timeIntervalSince(boostedAt ?? now) >= config.minBoostSeconds else { return nil }
            let back = savedLevel ?? 1
            isBoosting = false; savedLevel = nil; restoredAt = now; highSince = nil
            return .restore(to: back)
        }
    }
}
