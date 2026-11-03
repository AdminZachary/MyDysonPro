import Foundation

func runNoiseMergeChecks() -> Int {
    var fails = 0
    func ck(_ c: Bool, _ m: String) { print(c ? "PASS  \(m)" : "FAIL  \(m)"); if !c { fails += 1 } }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func minute(_ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h, minute: m))!
    }

    let same = minute(9, 0)
    let headphone = [NoiseMinute(start: same, leq: 80, origin: .headphone)]
    let zone = [NoiseMinute(start: same, leq: 100, origin: .zone)]
    let watch = [NoiseMinute(start: same, leq: 90, origin: .watch)]
    let merged = NoiseMerge.merged(headphone: headphone, zone: zone, watch: watch, calendar: cal)
    ck(merged.count == 1 && merged[0].origin == .headphone && merged[0].leq == 80,
       "merge: headphone wins the overlapping minute")
    let onlyAmbient = NoiseMerge.merged(headphone: [], zone: zone, watch: watch, calendar: cal)
    ck(onlyAmbient.count == 1 && onlyAmbient[0].origin == .zone && onlyAmbient[0].leq == 100,
       "merge: Zone ambient beats the Watch when no headphone sample")
    let watchOnly = NoiseMerge.merged(headphone: [], zone: [], watch: [NoiseMinute(start: minute(10, 0), leq: 70, origin: .watch)], calendar: cal)
    ck(watchOnly.count == 1 && watchOnly[0].origin == .watch, "merge: Watch fills a minute nothing else covers")

    // 4 h at 88 dB is about 100 % dose. An overlapping louder Zone minute must not raise it.
    var loud: [NoiseMinute] = []
    for i in 0..<240 { loud.append(NoiseMinute(start: minute(8, 0).addingTimeInterval(Double(i) * 60), leq: 88, origin: .headphone)) }
    let dose = NoiseMerge.dosePercent(loud)
    ck(abs(dose - 100) < 1, "dose: 4 h @ 88 dB ≈ 100 % (got \(dose))")
    var withZone = loud
    withZone[0] = NoiseMinute(start: loud[0].start, leq: 110, origin: .zone)
    let kept = NoiseMerge.merged(headphone: loud, zone: [withZone[0]], watch: [], calendar: cal)
    ck(abs(NoiseMerge.dosePercent(kept) - dose) < 0.01, "dose: overlapping Zone sample is not added")
    ck(NoiseMerge.primaryLabel(kept) == "耳机播放音量", "label: headphone when it supplies the minutes")
    ck(NoiseMerge.primaryLabel(onlyAmbient) == "环境噪音", "label: ambient when that is the only source")
    ck(NoiseMerge.caption(merged).contains("耳机播放音量"), "caption names the source")

    let span = NoiseMerge.minutes(from: [(start: minute(12, 0), end: minute(12, 3), db: 60)], origin: .headphone, calendar: cal)
    ck(span.count == 3 && span.allSatisfy { $0.leq == 60 && $0.origin == .headphone }, "samples expand to one minute each")
    ck(NoiseMerge.minutes(from: [(start: minute(1, 0), end: minute(1, 0).addingTimeInterval(10 * 3600), db: 50)],
                          origin: .watch, calendar: cal, maxSpan: 3600).count == 60,
       "sample span is capped")

    ck(HeadphoneKind.suggest(portType: "BluetoothA2DPOutput", portName: "AirPods Pro") == .airpods, "route: AirPods")
    ck(HeadphoneKind.suggest(portType: "BluetoothA2DPOutput", portName: "Beats Fit Pro") == .airpods, "route: Beats")
    ck(HeadphoneKind.suggest(portType: "BluetoothA2DPOutput", portName: "Dyson Zone") == .zone, "route: Zone")
    ck(HeadphoneKind.suggest(portType: "BluetoothA2DPOutput", portName: "WH-1000XM5") == .other, "route: other bluetooth")
    ck(HeadphoneKind.suggest(portType: "Headphones", portName: "Headphones") == .other, "route: wired")
    ck(HeadphoneKind.suggest(portType: "Speaker", portName: "iPhone") == nil, "route: speaker is not headphones")
    ck(!HeadphoneKind.airpods.usesZone && HeadphoneKind.zone.usesZone, "only Zone enables the Zone module")
    return fails
}
