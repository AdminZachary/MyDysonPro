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
    @Published private(set) var healthStatus: String = "未写入"

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
        if alert && ZoneSettings.shared.noiseAlerts { notifyDose() }

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
            try? await health.requestAuthorization(toShare: [audioType], read: [audioType])
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notifyDose() {
        let c = UNMutableNotificationContent()
        c.title = "今日噪音暴露已达上限"
        c.body = String(format: "按 85 dB·8 小时标准，今日剂量已达 %.0f%%（LEX,8h ≈ %.0f dB）。建议开启降噪或休息耳朵。",
                        today.dosePercent, today.lex8h ?? 0)
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
