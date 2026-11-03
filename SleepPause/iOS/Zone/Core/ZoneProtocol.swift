// Dyson Zone BLE protocol constants + message framing.
// Framing/MessageAssembler adapted from nikships/dyson-zone-companion (MIT, Copyright (c) 2026 Nik).
// Field meanings: [C] = dyson-zone-companion docs (verified on a live Zone by its author),
// [A] = MyDyson Android 6.4.26420 static analysis (UNVERIFIED on hardware).
import Foundation

enum ZoneUUID {
    static func full(_ short: String) -> String { "2DD1\(short)-1C37-452D-8979-D1B4A787D0A4" }
    static let authService = full("0010")
    static let authChar = full("0011")
    static let attrChar = full("0021")
    static let fanSpeed = full("2001")        // [C] write 0 off,1 rest,2 light,3 moderate
    static let fanAuto = full("2002")         // [C] bool
    static let fanActual = full("2003")       // [C] 0-3
    static let worn = full("2004")            // [A] UNVERIFIED: currently worn (byte != 0)
    static let visor = full("2005")           // [A] 0 not attached,1 in position,2 dipped,3 invalid
    static let chargerPresent = full("200B")  // [C]
    static let chargingState = full("2016")   // [C]
    static let aqBlock = full("201D")         // [C] AQ/audio health block; layout [A] UNVERIFIED
    static let batteryPercent = full("201E")  // [C]
}

enum ZoneAttr {
    static let ancMode: UInt16 = 0x400A        // [C] 0 ANC, 1 conversation, 2 transparency, 3 off
    static let eqMode: UInt16 = 0x400B         // [C]
    static let batteryState: UInt16 = 0x401A   // [C]
    static let headDetectMode: UInt16 = 0x4023 // [A] 0 auto, 1 always worn, 2 always unworn
}

enum ZoneANCMode: Int, CaseIterable, Codable {
    case anc = 0, conversation = 1, transparency = 2, off = 3
    var label: String {
        switch self {
        case .anc: return "降噪"
        case .conversation: return "对话"
        case .transparency: return "通透"
        case .off: return "关闭"
        }
    }
}

enum ZoneMsgType {
    static let requestProductInfo: UInt8 = 0x0A
    static let productInfo: UInt8 = 0x0B
    static let reauthA: UInt8 = 0x06
    static let reauthB: UInt8 = 0x07
    static let reauthC: UInt8 = 0x08
    static let connectionEstablished: UInt8 = 0x26
    static let attributeGet: UInt8 = 0x90
    static let attributeValue: UInt8 = 0x91
    static let attributeSet: UInt8 = 0x93
    static let attributeAck: UInt8 = 0x94
    static let attributeSubscribe: UInt8 = 0x96
    static let attributeReport: UInt8 = 0x97
    static let subscribeAck: UInt8 = 0x98
}

struct ZoneMessage: Equatable {
    let type: UInt8
    let payload: Data
}

enum ZoneFraming {
    static let capacity = 20

    /// First fragment header is `0x80 | (total - 1)`; later ones carry their own index.
    static func fragments(type: UInt8, payload: Data = Data()) -> [Data] {
        let logical = Data([type]) + payload
        let per = capacity - 1
        let total = max(1, (logical.count + per - 1) / per)
        return (0..<total).map { i in
            let chunk = logical.subdata(in: (i * per)..<min(logical.count, (i + 1) * per))
            let header: UInt8 = i == 0 ? UInt8(0x80 | (total - 1)) : UInt8(i & 0x7F)
            return Data([header]) + chunk
        }
    }

    static func attributeID(_ id: UInt16) -> Data { Data([UInt8(id & 0xFF), UInt8(id >> 8)]) }

    static func attributeGet(_ id: UInt16) -> [Data] {
        fragments(type: ZoneMsgType.attributeGet, payload: attributeID(id))
    }

    static func attributeSet(_ id: UInt16, value: Data) -> [Data] {
        let len = Data([UInt8(value.count & 0xFF), UInt8(value.count >> 8)])
        return fragments(type: ZoneMsgType.attributeSet, payload: attributeID(id) + len + value)
    }

    static func attributeSubscribe(_ id: UInt16) -> [Data] {
        fragments(type: ZoneMsgType.attributeSubscribe, payload: attributeID(id) + Data([0]))
    }

    /// Parses 0x91 (value, with status) and 0x97 (report) messages into (id, value).
    static func parseAttribute(_ m: ZoneMessage) -> (id: UInt16, value: Data)? {
        let p = [UInt8](m.payload)
        switch m.type {
        case ZoneMsgType.attributeValue where p.count >= 5:
            let id = UInt16(p[0]) | UInt16(p[1]) << 8
            let len = Int(p[3]) | Int(p[4]) << 8
            guard p[2] == 0, p.count >= 5 + len else { return nil }
            return (id, Data(p[5..<(5 + len)]))
        case ZoneMsgType.attributeReport where p.count >= 4:
            let id = UInt16(p[0]) | UInt16(p[1]) << 8
            let len = Int(p[2]) | Int(p[3]) << 8
            guard p.count >= 4 + len else { return nil }
            return (id, Data(p[4..<(4 + len)]))
        default:
            return nil
        }
    }
}

/// Reassembles notification fragments. A new first fragment always restarts the buffer.
struct ZoneMessageAssembler {
    private var parts: [Data] = []
    private var type: UInt8 = 0
    private var expected = 0
    private var received = 0

    mutating func push(_ fragment: Data) -> ZoneMessage? {
        guard let header = fragment.first else { return nil }
        let body = fragment.dropFirst()
        if header & 0x80 != 0 {
            guard let t = body.first else { return nil }
            type = t
            expected = Int(header & 0x7F) + 1
            received = 1
            parts = [Data(body.dropFirst())]
        } else {
            guard expected > 0 else { return nil }
            parts.append(Data(body))
            received = Int(header & 0x7F) + 1
        }
        guard received >= expected else { return nil }
        let message = ZoneMessage(type: type, payload: parts.reduce(Data(), +))
        parts = []; expected = 0; received = 0
        return message
    }
}

extension Data {
    var zoneHex: String { map { String(format: "%02x", $0) }.joined() }
}
