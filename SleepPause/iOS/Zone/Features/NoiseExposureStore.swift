import Foundation
import HealthKit
import UserNotifications

/// Feature 3: Zone ambient SPL -> 1-minute Leq -> (optional) Apple Health environmentalAudioExposure,
/// plus a local daily dose (85 dBA / 8 h, 3 dB exchange) with a notification at 100 %.
///
/// HealthKit: third-party apps may SAVE `environmentalAudioExposure` quantity samples (dBASPL) after
/// share authorization. The *event* type `environmentalAudioExposureEvent` is read-only, so the
/// ">85 dB" alert is a local notification instead. If saving fails, data stays local.
///
/// ⚠️ The ambient SPL comes from 2DD1201D whose layout is UNVERIFIED, and we don't know whether
/// the Zone's value is A-weighted. Treat numbers as indicative until the layout is confirmed.
@MainActor
final class NoiseExposureStore: ObservableObject {
    static let shared = NoiseExposureStore()

    struct MinuteSample: Codable, Identifiable {
        var id: Date { start }
        var start: Date
        var leq: Double
        var savedToHealth: Bool
    }

    @Published private(set) var today: ExposureAccumulator
    @Published private(set) var minutes: [MinuteSample] = []
    @Published private(set) var healthMinutes: [NoiseMinute] = []
    @Published private(set) var healthStatus: String = "未写入"
    private var mergedAlertDay: Date?

    private var bucket: [(db: Double, seconds: Double)] = []
    private var bucketStart: Date?
    private var lastSampleDate: Date?
    private let health = HKHealthStore()
    private let audioType = HKQuantityType(.environmentalAudioExposure)

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var rawLogURL: URL { docs.appendingPathComponent("zone-aq-raw.jsonl") }
    private var minutesURL: URL { docs.appendingPathComponent("zone-noise-minutes.json") }
    private var accURL: URL { docs.appendingPathComponent("zone-noise-today.json") }

    private init() {
        today = ExposureAccumulator(dayStart: Calendar.current.startOfDay(for: Date()))
        if let d = try? Data(contentsOf: accURL), let a = try? JSONDecoder().decode(ExposureAccumulator.self, from: d),
           Calendar.current.isDateInToday(a.dayStart) { today = a }
        if let d = try? Data(contentsOf: minutesURL), let m = try? JSONDecoder().decode([MinuteSample].self, from: d) { minutes = m }
    }

    func ingest(_ r: ZoneAQReading, worn: Bool?) {
        appendRaw(r)
        guard r.looksPlausible, worn != false else { return }
        let alert = today.add(levelDb: r.ambientDb, at: r.date)
        _ = alert
        noteMergedDose()

        // 1-minute Leq buckets
        if bucketStart == nil { bucketStart = r.date }
        let dt = lastSampleDate.map { min(60, max(0, r.date.timeIntervalSince($0))) } ?? 10
        bucket.append((r.ambientDb, dt))
        lastSampleDate = r.date
        if let s = bucketStart, r.date.timeIntervalSince(s) >= 60 {
            if let l = Leq.of(bucket) { closeMinute(start: s, end: r.date, leq: l) }
            bucket = []
            bucketStart = r.date
        }
        persistAccumulator()
    }

    private func closeMinute(start: Date, end: Date, leq: Double) {
        var sample = MinuteSample(start: start, leq: leq, savedToHealth: false)
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        minutes.removeAll { $0.start < cutoff }
        if ZoneSettings.shared.writeNoiseToHealth {
            let q = HKQuantity(unit: .decibelAWeightedSoundPressureLevel(), doubleValue: leq)
            let hk = HKQuantitySample(type: audioType, quantity: q, start: start, end: end,
                                      metadata: ["SleepPauseSource": "Dyson Zone 2DD1201D (\(ZoneAQLayout.current.name))"])
            sample.savedToHealth = true
            health.save(hk) { ok, err in
                Task { @MainActor in
                    self.healthStatus = ok ? "已写入健康（环境声音）" : "写入失败：\(err?.localizedDescription ?? "-")（数据保存在本机）"
                }
            }
        }
        minutes.append(sample)
        if let d = try? JSONEncoder().encode(minutes) { try? d.write(to: minutesURL, options: .atomic) }
    }

    func requestPermissions() async {
        if HKHealthStore.isHealthDataAvailable() {
            let headphone = HKQuantityType(.headphoneAudioExposure)
            try? await health.requestAuthorization(toShare: [audioType], read: [audioType, headphone])
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshHealth()
    }

    /// Reads headphone playback level and Apple Watch environmental noise from Health.
    /// Samples this app wrote (metadata `SleepPauseSource`) are skipped so Zone data is not counted twice.
    func refreshHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let headphone = HKQuantityType(.headphoneAudioExposure)
        let start = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date()
        let playback = await fetch(headphone, since: start, skipOurs: false)
        let ambient = await fetch(audioType, since: start, skipOurs: true)
        healthMinutes = NoiseMerge.minutes(from: playback, origin: .headphone)
            + NoiseMerge.minutes(from: ambient, origin: .watch)
        noteMergedDose()
    }

    var mergedAll: [NoiseMinute] {
        NoiseMerge.merged(
            headphone: healthMinutes.filter { $0.origin == .headphone },
            zone: minutes.map { NoiseMinute(start: $0.start, leq: $0.leq, origin: .zone) },
            watch: healthMinutes.filter { $0.origin == .watch })
    }

    var mergedToday: [NoiseMinute] {
        mergedAll.filter { Calendar.current.isDateInToday($0.start) }
    }

    var mergedDosePercent: Double { NoiseMerge.dosePercent(mergedToday) }

    var mergedLex: Double? {
        let energy = mergedToday.reduce(0.0) { $0 + pow(10, $1.leq / 10) * 60 }
        return energy > 0 ? 10 * log10(energy / ExposureAccumulator.referenceSeconds) : nil
    }

    var doseCaption: String { NoiseMerge.caption(mergedToday) }

    /// Latest Zone ambient level, shown beside the dose and not added when that minute already has playback.
    var zoneAmbientAside: String? {
        guard HeadphonePreference.usesZone(), ZoneManager.shared.isReady,
              let db = ZoneManager.shared.lastReading?.ambientDb else { return nil }
        return String(format: "Zone 环境噪音 %.0f dB。%@", db, NoiseMerge.rule)
    }

    private func noteMergedDose() {
        let day = Calendar.current.startOfDay(for: Date())
        guard mergedDosePercent >= 100, mergedAlertDay != day, ZoneSettings.shared.noiseAlerts else { return }
        mergedAlertDay = day
        notifyDose()
    }

    private func fetch(_ type: HKQuantityType, since start: Date, skipOurs: Bool) async -> [(start: Date, end: Date, db: Double)] {
        await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: []),
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                let rows = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> (Date, Date, Double)? in
                    if skipOurs, sample.metadata?["SleepPauseSource"] != nil { return nil }
                    let db = sample.quantity.doubleValue(for: .decibelAWeightedSoundPressureLevel())
                    return (sample.startDate, sample.endDate, db)
                }
                cont.resume(returning: rows)
            }
            health.execute(query)
        }
    }

    private func notifyDose() {
        let c = UNMutableNotificationContent()
        c.title = "今日噪音暴露已达上限"
        c.body = String(format: "按 85 dB·8 小时标准，今日剂量已达 %.0f%%（LEX,8h ≈ %.0f dB）。%@",
                        mergedDosePercent, mergedLex ?? 0, NoiseMerge.rule)
        let req = UNNotificationRequest(identifier: "zone.dose.\(Int(today.dayStart.timeIntervalSince1970))", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func persistAccumulator() {
        if let d = try? JSONEncoder().encode(today) { try? d.write(to: accURL, options: .atomic) }
    }

    /// Raw 201D bytes are always logged so a wrong layout can be re-decoded later.
    private func appendRaw(_ r: ZoneAQReading) {
        let line = "{\"ts\":\(r.date.timeIntervalSince1970),\"raw\":\"\(r.raw)\",\"layout\":\"\(r.layoutName)\"}\n"
        guard let data = line.data(using: .utf8) else { return }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: rawLogURL.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 5_000_000 {
            try? FileManager.default.removeItem(at: rawLogURL)
        }
        if let h = try? FileHandle(forWritingTo: rawLogURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: rawLogURL)
        }
    }
}
