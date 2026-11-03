import Foundation

/// Layout of characteristic 2DD1201D ("AQ and audio health" block, 16 bytes = 8 x UInt16 LE).
///
/// ⚠️ UNVERIFIED: the field ORDER below is inferred from the MyDyson Android app's
/// `AQAndAudioHealthData.toString()` (6.4.26420). It has NOT been checked against a real Zone.
/// After a ZoneProbe capture, fix it by editing ONLY `ZoneAQLayout.current` (word indices).
struct ZoneAQLayout: Equatable, Codable {
    var name: String
    var isVerified: Bool
    var expectedLength: Int
    // word index (0...7) of each field
    var vocPpb: Int
    var no2Ppb: Int
    var no2AQI: Int
    var temperatureDeciKelvin: Int
    var humidityPerMille: Int
    var inEarSplCentibels: Int
    var ambientSplCentibels: Int
    var audioSplCentibels: Int

    static let inferredV1 = ZoneAQLayout(
        name: "inferred-v1 (MyDyson 6.4.26420 toString order)", isVerified: false, expectedLength: 16,
        vocPpb: 0, no2Ppb: 1, no2AQI: 2, temperatureDeciKelvin: 3, humidityPerMille: 4,
        inEarSplCentibels: 5, ambientSplCentibels: 6, audioSplCentibels: 7)

    /// Change this (and set isVerified = true) once a capture confirms the order.
    static var current = inferredV1
}

struct ZoneAQReading: Equatable, Codable {
    var date: Date
    var raw: String               // hex, always kept so a wrong layout can be re-decoded later
    var layoutName: String
    var layoutVerified: Bool
    var vocPpb: Double
    var no2Ppb: Double
    var no2AQI: Double
    var temperatureC: Double
    var humidityPercent: Double
    var inEarDb: Double
    var ambientDb: Double
    var audioDb: Double

    /// Sanity check: if values fall outside physical ranges, the layout is probably wrong.
    var looksPlausible: Bool {
        (-20...60).contains(temperatureC) && (0...100).contains(humidityPercent)
            && (0...140).contains(ambientDb) && (0...140).contains(inEarDb) && (0...140).contains(audioDb)
            && no2Ppb >= 0 && no2Ppb < 5000 && vocPpb >= 0 && vocPpb < 50000
    }
}

enum ZoneAQDecoder {
    static func words(_ data: Data) -> [UInt16] {
        let b = [UInt8](data)
        return stride(from: 0, to: b.count - 1, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
    }

    static func decode(_ data: Data, date: Date = Date(), layout: ZoneAQLayout = ZoneAQLayout.current) -> ZoneAQReading? {
        guard data.count == layout.expectedLength else { return nil }
        let w = words(data).map(Double.init)
        func at(_ i: Int) -> Double { i >= 0 && i < w.count ? w[i] : .nan }
        return ZoneAQReading(
            date: date, raw: data.zoneHex, layoutName: layout.name, layoutVerified: layout.isVerified,
            vocPpb: at(layout.vocPpb),
            no2Ppb: at(layout.no2Ppb),
            no2AQI: at(layout.no2AQI),
            temperatureC: at(layout.temperatureDeciKelvin) / 10 - 273.15,
            humidityPercent: at(layout.humidityPerMille) / 10,
            inEarDb: at(layout.inEarSplCentibels) / 10,
            ambientDb: at(layout.ambientSplCentibels) / 10,
            audioDb: at(layout.audioSplCentibels) / 10)
    }
}
