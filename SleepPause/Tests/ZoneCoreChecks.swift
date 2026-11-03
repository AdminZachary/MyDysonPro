import Foundation

var zfails = 0
func zcheck(_ c: Bool, _ m: String) { print(c ? "PASS  \(m)" : "FAIL  \(m)"); if !c { zfails += 1 } }

func runZoneChecks() -> Int {
    // Framing
    let payload = Data((0..<45).map { UInt8($0) })
    var asm = ZoneMessageAssembler()
    var got: ZoneMessage?
    for f in ZoneFraming.fragments(type: 0x97, payload: payload) { got = asm.push(f) ?? got }
    zcheck(got == ZoneMessage(type: 0x97, payload: payload), "framing round trip (3 fragments)")
    zcheck(ZoneFraming.attributeSet(ZoneAttr.ancMode, value: Data([3]))[0] == Data([0x80, 0x93, 0x0A, 0x40, 0x01, 0x00, 0x03]),
           "ANC off set message bytes")
    let rep = ZoneFraming.parseAttribute(ZoneMessage(type: 0x97, payload: Data([0x0A, 0x40, 0x01, 0x00, 0x02])))
    zcheck(rep?.id == 0x400A && rep?.value == Data([2]), "parse 0x97 report")
    let val = ZoneFraming.parseAttribute(ZoneMessage(type: 0x91, payload: Data([0x1A, 0x40, 0x00, 0x01, 0x00, 0x01])))
    zcheck(val?.id == 0x401A && val?.value == Data([1]), "parse 0x91 value")

    // Decoder (synthetic block in the inferred order)
    func le(_ v: [UInt16]) -> Data { Data(v.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) }
    let block = le([120, 18, 2, 2961, 455, 652, 715, 701])  // 22.95 C, 45.5 %, 65.2/71.5/70.1 dB
    let r = ZoneAQDecoder.decode(block, date: Date(timeIntervalSince1970: 0))
    zcheck(r != nil && abs(r!.temperatureC - 22.95) < 0.01 && abs(r!.ambientDb - 71.5) < 0.01 && r!.no2Ppb == 18,
           "decoder inferred layout values")
    zcheck(r?.layoutVerified == false && r?.raw == block.zoneHex, "decoder keeps raw + unverified flag")
    zcheck(r?.looksPlausible == true, "plausibility ok")
    zcheck(ZoneAQDecoder.decode(Data([1, 2, 3])) == nil, "decoder rejects wrong length")
    let garbage = ZoneAQDecoder.decode(le([65000, 65000, 65000, 65000, 65000, 65000, 65000, 65000]))
    zcheck(garbage?.looksPlausible == false, "plausibility flags garbage")

    // Adaptive ANC with hysteresis
    let c = AdaptiveANCController()
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var mode: ZoneANCMode = .transparency
    var switches: [(Double, ZoneANCMode)] = []
    func feed(_ db: Double, _ from: Double, _ to: Double) {
        var t = from
        while t < to {
            if let m = c.update(ambientDb: db, at: t0.addingTimeInterval(t), current: mode) { mode = m; switches.append((t, m)) }
            t += 2
        }
    }
    feed(75, 0, 60)            // loud -> ANC after ~10 s
    zcheck(mode == .anc && switches.count == 1 && switches[0].0 >= 10 && switches[0].0 <= 20, "loud -> ANC after smoothing")
    feed(63, 60, 200)          // inside hysteresis band -> stay
    zcheck(mode == .anc && switches.count == 1, "hysteresis band keeps ANC")
    feed(50, 200, 230)         // quiet but dwell satisfied -> transparency
    zcheck(mode == .transparency && switches.count == 2, "quiet -> transparency")
    feed(80, 230, 260)         // loud again but within min dwell (60 s) -> no switch yet
    zcheck(mode == .transparency, "min dwell prevents flapping")
    c.noteManualChange(at: t0.addingTimeInterval(260))
    feed(80, 260, 600)         // overridden for 30 min
    zcheck(mode == .transparency, "manual override respected")
    feed(80, 2100, 2200)
    zcheck(mode == .anc, "after override expires -> ANC")

    // Sleep hold: armed sleep watch / after onset -> never switch away from current mode
    c.sleepWatchActive = true
    feed(40, 2300, 2700)
    zcheck(mode == .anc, "sleep watch active: quiet does not leave ANC")
    c.sleepWatchActive = false
    c.beginSleepHold(at: t0.addingTimeInterval(2700))
    feed(40, 2700, 3500)
    zcheck(mode == .anc, "after sleep onset: ANC kept")
    c.clearSleepHold()
    feed(40, 3500, 3700)
    zcheck(mode == .transparency, "hold cleared -> adaptive resumes")

    // Exposure: 85 dB for 8 h = 100 % dose; 88 dB reaches 100 % at ~4 h
    var acc = ExposureAccumulator(dayStart: Date(timeIntervalSince1970: 0))
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    acc.dayStart = cal.startOfDay(for: t0)
    var alertAt: Double?
    var t = 0.0
    while t <= 5 * 3600 {
        if acc.add(levelDb: 88, at: t0.addingTimeInterval(t), calendar: cal) { alertAt = t }
        t += 10
    }
    zcheck(alertAt != nil && abs(alertAt! - 4 * 3600) < 120, "88 dB -> 100 % dose at ~4 h (got \(alertAt ?? -1))")
    zcheck(abs((acc.leq ?? 0) - 88) < 0.01, "Leq of constant 88 dB = 88")
    zcheck(abs((Leq.of([(80, 30), (90, 30)]) ?? 0) - 87.4) < 0.1, "Leq mix 80/90 dB ≈ 87.4")
    var acc2 = ExposureAccumulator(dayStart: cal.startOfDay(for: t0))
    _ = acc2.add(levelDb: 90, at: t0, calendar: cal)
    _ = acc2.add(levelDb: 90, at: t0.addingTimeInterval(3600), calendar: cal)  // 1 h gap -> capped at 60 s
    zcheck(acc2.secondsCounted == 60, "gaps capped (disconnects don't count)")

    // Commute stats
    var route = CommuteRoute(name: "test", start: t0, end: t0.addingTimeInterval(600))
    route.points = [CommutePoint(lat: 31.2304, lon: 121.4737, date: t0, no2Ppb: 10, vocPpb: nil, ambientDb: 60),
                    CommutePoint(lat: 31.2394, lon: 121.4737, date: t0.addingTimeInterval(300), no2Ppb: 60, vocPpb: nil, ambientDb: 72)]
    let st = CommuteStats.of(route, metric: .no2)
    zcheck(abs(st.distanceKm - 1.0) < 0.02 && st.mean == 35 && st.maximum == 60 && st.fractionBad == 0.5 && st.durationMinutes == 10,
           "commute stats")
    return zfails
}
