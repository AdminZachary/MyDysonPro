import Foundation

struct CommutePoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    var date: Date
    var no2Ppb: Double?
    var vocPpb: Double?
    var ambientDb: Double?
}

struct CommuteRoute: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date?
    var points: [CommutePoint] = []
    var layoutVerified: Bool = false
}

enum CommuteMetric: String, CaseIterable, Codable {
    case no2, voc, noise
    var label: String {
        switch self { case .no2: return "NO₂"; case .voc: return "VOC"; case .noise: return "噪音" }
    }
    func value(_ p: CommutePoint) -> Double? {
        switch self { case .no2: return p.no2Ppb; case .voc: return p.vocPpb; case .noise: return p.ambientDb }
    }
    /// 0 good … 3 bad. Thresholds are rough, self-chosen bands — not an official AQI.
    func level(_ v: Double) -> Int {
        let t: [Double]
        switch self {
        case .no2: t = [21, 53, 100]      // ppb
        case .voc: t = [250, 500, 1000]   // ppb
        case .noise: t = [55, 70, 85]     // dB
        }
        return t.firstIndex { v < $0 } ?? 3
    }
}

struct CommuteStats: Equatable {
    var durationMinutes: Double
    var distanceKm: Double
    var mean: Double?
    var maximum: Double?
    var fractionBad: Double?   // share of points at level >= 2

    static func of(_ r: CommuteRoute, metric: CommuteMetric) -> CommuteStats {
        let pts = r.points
        let dur = ((r.end ?? pts.last?.date ?? r.start).timeIntervalSince(r.start)) / 60
        var dist = 0.0
        for i in 1..<Swift.max(1, pts.count) where pts.count > 1 {
            dist += haversineKm(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon)
        }
        let vals = pts.compactMap { metric.value($0) }.filter { $0.isFinite }
        let mean = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        let bad = vals.isEmpty ? nil : Double(vals.filter { metric.level($0) >= 2 }.count) / Double(vals.count)
        return CommuteStats(durationMinutes: Swift.max(0, dur), distanceKm: dist, mean: mean, maximum: vals.max(), fractionBad: bad)
    }

    static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0, d = Double.pi / 180
        let dLat = (lat2 - lat1) * d, dLon = (lon2 - lon1) * d
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * d) * cos(lat2 * d) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
