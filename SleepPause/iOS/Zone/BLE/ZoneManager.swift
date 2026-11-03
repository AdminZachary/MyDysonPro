import CoreBluetooth
import CryptoKit
import Foundation
import Combine

/// Optional Dyson Zone control over BLE (unofficial). Handshake / crypto / framing follow
/// nikships/dyson-zone-companion (MIT). The Zone accepts ONE controller: quit MyDyson first.
///
/// Background: `bluetooth-central` background mode + state restoration
/// (CBCentralManagerOptionRestoreIdentifierKey) + a pending `connect` to the remembered peripheral,
/// which iOS keeps alive indefinitely and completes when the Zone becomes connectable.
@MainActor
final class ZoneManager: NSObject, ObservableObject {
    static let shared = ZoneManager()

    enum LinkState: Equatable {
        case disabled, needsLogin, bluetoothOff(String), searching, busyElsewhere, connecting, authenticating, ready, failed(String)
        var label: String {
            switch self {
            case .disabled: return "未启用"
            case .needsLogin: return "需要登录 Dyson 账号"
            case .bluetoothOff(let s): return s
            case .searching: return "正在寻找 Zone…"
            case .busyElsewhere: return "Zone 正被其他设备控制（请彻底退出 MyDyson）"
            case .connecting: return "连接中…"
            case .authenticating: return "认证中…"
            case .ready: return "已连接"
            case .failed(let s): return "失败：\(s)"
            }
        }
    }

    @Published private(set) var state: LinkState = .disabled
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var charging: Int?
    @Published private(set) var fanSpeed: Int?
    @Published private(set) var fanAuto: Bool?
    @Published private(set) var fanActual: Int?
    @Published private(set) var ancMode: ZoneANCMode?
    @Published private(set) var worn: Bool?          // UNVERIFIED source (2DD12004)
    @Published private(set) var visor: Int?
    @Published private(set) var lastReading: ZoneAQReading?
    @Published private(set) var lastRawAQ: String?
    @Published private(set) var log: [String] = []

    /// Hooks wired up by the app.
    var onReading: (@MainActor (ZoneAQReading) -> Void)?
    var onWornChange: (@MainActor (Bool) -> Void)?

    static let restoreID = "SleepPause.ZoneCentral"
    private static let peripheralKey = "zone.peripheralID"
    private let authChar = CBUUID(string: ZoneUUID.authChar)
    private let attrChar = CBUUID(string: ZoneUUID.attrChar)
    private let authService = CBUUID(string: ZoneUUID.authService)

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var pendingServices = 0
    private var authAsm = ZoneMessageAssembler()
    private var attrAsm = ZoneMessageAssembler()
    private var writeQueue: [(data: Data, char: CBCharacteristic, gapMs: Int)] = []
    private var writing = false
    private var handshakeStage = 0
    private var credentials: ZoneCredentials?
    private var key: SymmetricKey?
    private var pollTimer: Timer?
    private var lastCommandedANC: (mode: ZoneANCMode, at: Date)?
    let adaptive = AdaptiveANCController()

    var isReady: Bool { state == .ready }

    /// Connected sample for screenshots. Does not open Bluetooth.
    func applyScreenshotFixture() {
        state = .ready
        batteryPercent = 72
        charging = 0
        fanSpeed = 1
        fanActual = 1
        fanAuto = false
        ancMode = .anc
        worn = true
        lastReading = ZoneAQReading(
            date: Date(), raw: "", layoutName: ZoneAQLayout.current.name, layoutVerified: false,
            vocPpb: 120, no2Ppb: 18, no2AQI: 20, temperatureC: 23, humidityPercent: 45,
            inEarDb: 55, ambientDb: 62, audioDb: 40)
    }

    // MARK: Lifecycle

    /// Call at launch (also when iOS relaunches us for BLE state restoration).
    func bootstrap() {
        guard ZoneSettings.shared.moduleEnabled else { state = .disabled; return }
        credentials = ZoneKeychain.load()
        guard let c = credentials, let ltk = Data(hexString: c.ltk) else { state = .needsLogin; return }
        key = ZoneCrypto.deriveAuthKey(ltk: ltk)
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                                                 CBCentralManagerOptionShowPowerAlertKey: true])
        } else {
            connectOrScan()
        }
    }

    func shutdown() {
        pollTimer?.invalidate()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        resetLink()
        state = .disabled
    }

    func forgetAccount() {
        shutdown()
        ZoneKeychain.delete()
        UserDefaults.standard.removeObject(forKey: Self.peripheralKey)
        state = .needsLogin
    }

    /// Waits (up to `timeout`) for an authenticated link — used by App Intents.
    func waitUntilReady(timeout: TimeInterval = 12) async -> Bool {
        if isReady { return true }
        bootstrap()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isReady { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return isReady
    }

    // MARK: Commands

    func setANC(_ mode: ZoneANCMode, manual: Bool) {
        guard isReady else { note("降噪模式未设置：Zone 未连接"); return }
        lastCommandedANC = (mode, Date())
        if manual { adaptive.noteManualChange(at: Date()) }
        ancMode = mode
        enqueue(ZoneFraming.attributeSet(ZoneAttr.ancMode, value: Data([UInt8(mode.rawValue)])), to: attrChar, gapMs: 150)
    }

    /// 0 off, 1 rest, 2 light, 3 moderate. Turns auto mode off first (as the app does).
    func setFan(_ level: Int) {
        guard isReady, (0...3).contains(level) else { note("风扇未设置：Zone 未连接"); return }
        let autoC = CBUUID(string: ZoneUUID.fanAuto), speedC = CBUUID(string: ZoneUUID.fanSpeed)
        fanAuto = false
        fanSpeed = level
        enqueue([Data([0])], to: autoC, gapMs: 150)
        enqueue([Data([UInt8(level)])], to: speedC, gapMs: 150)
    }

    /// Feature 1: called when the watch reports sleep onset. Returns a log line.
    func handleSleepOnset() -> String {
        let s = ZoneSettings.shared
        guard s.moduleEnabled else { return "Zone 模块未启用" }
        // Keep the current ANC mode through the night: pause adaptive switching.
        adaptive.beginSleepHold(at: Date())
        guard isReady else {
            bootstrap()
            return "Zone 未连接，跳过关风扇/关降噪"
        }
        var done: [String] = []
        if s.sleepFanOff { setFan(0); done.append("风扇已关") }
        if s.sleepANCOff { setANC(.off, manual: true); done.append("降噪已关") }
        return done.isEmpty ? "Zone：未勾选任何睡眠动作" : "Zone：" + done.joined(separator: "，")
    }

    // MARK: Internals

    private func note(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date())) \(s)", at: 0)
        if log.count > 100 { log.removeLast() }
    }

    private func resetLink() {
        pollTimer?.invalidate(); pollTimer = nil
        peripheral = nil
        chars = [:]
        authAsm = ZoneMessageAssembler()
        attrAsm = ZoneMessageAssembler()
        writeQueue = []
        writing = false
        handshakeStage = 0
    }

    private func connectOrScan() {
        guard let central, central.state == .poweredOn, peripheral == nil else { return }
        if let s = UserDefaults.standard.string(forKey: Self.peripheralKey), let id = UUID(uuidString: s),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            // A pending connect never times out: iOS completes it (even in background) once the
            // Zone is connectable again.
            attach(p)
            state = .connecting
            central.connect(p)
            // also scan briefly in foreground in case the identifier changed
        }
        state = state == .connecting ? .connecting : .searching
        central.scanForPeripherals(withServices: [authService], options: nil)
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
    }

    private func startHandshake() {
        handshakeStage = 1
        state = .authenticating
        sendAuth(ZoneMsgType.requestProductInfo)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.handshakeStage == 1 else { return }
            self.sendReauthA()
        }
    }

    private func sendReauthA() {
        guard let c = credentials, let key,
              let a = ZoneCrypto.reauthPayloadA(accountId: c.accountId, key: key, nonce: ZoneCrypto.randomBytes(16)) else {
            state = .failed("账号数据无效，请重新登录"); return
        }
        handshakeStage = 2
        sendAuth(ZoneMsgType.reauthA, a)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.handshakeStage == 2 else { return }
            self.state = .failed("握手超时（密钥错误或 Zone 被占用）")
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
        }
    }

    private func handleAuth(_ m: ZoneMessage) {
        switch m.type {
        case ZoneMsgType.productInfo:
            if handshakeStage == 1 { sendReauthA() }
        case ZoneMsgType.reauthB:
            guard let key, let ch = ZoneCrypto.challenge(fromPayloadB: m.payload, key: key) else {
                state = .failed("密钥被拒绝，请重新登录"); return
            }
            handshakeStage = 3
            sendAuth(ZoneMsgType.reauthC, ZoneCrypto.reauthPayloadC(key: key, challenge: ch))
        case ZoneMsgType.connectionEstablished:
            handshakeStage = 4
            state = .ready
            note("已认证")
            sync()
        default:
            break
        }
    }

    private func sync() {
        guard let p = peripheral else { return }
        for id in [ZoneAttr.ancMode, ZoneAttr.batteryState, ZoneAttr.headDetectMode] {
            enqueue(ZoneFraming.attributeSubscribe(id), to: attrChar, gapMs: 150)
            enqueue(ZoneFraming.attributeGet(id), to: attrChar, gapMs: 150)
        }
        let wanted = [ZoneUUID.fanSpeed, ZoneUUID.fanAuto, ZoneUUID.fanActual, ZoneUUID.worn, ZoneUUID.visor,
                      ZoneUUID.chargingState, ZoneUUID.aqBlock, ZoneUUID.batteryPercent].map { CBUUID(string: $0) }
        for u in wanted {
            guard let c = chars[u] else { continue }
            if c.properties.contains(.notify) { p.setNotifyValue(true, for: c) }
            if c.properties.contains(.read) { p.readValue(for: c) }
        }
        pollTimer?.invalidate()
        // Some characteristics may not notify; poll the AQ block + worn every 10 s.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.peripheral, self.isReady else { return }
                for u in [ZoneUUID.aqBlock, ZoneUUID.worn, ZoneUUID.batteryPercent] {
                    if let c = self.chars[CBUUID(string: u)], c.properties.contains(.read) { p.readValue(for: c) }
                }
            }
        }
    }

    private func handleChar(_ uuid: CBUUID, _ v: Data) {
        guard let b = v.first else { return }
        switch uuid.uuidString.uppercased() {
        case ZoneUUID.batteryPercent: batteryPercent = min(100, Int(b))
        case ZoneUUID.chargingState: charging = Int(b)
        case ZoneUUID.fanSpeed: fanSpeed = Int(b)
        case ZoneUUID.fanAuto: fanAuto = b != 0
        case ZoneUUID.fanActual: fanActual = Int(b)
        case ZoneUUID.visor: visor = Int(b)
        case ZoneUUID.worn:
            let w = b != 0
            if worn != w { worn = w; note(w ? "佩戴：已戴上（2004，未验证）" : "佩戴：已摘下（2004，未验证）"); onWornChange?(w) }
        case ZoneUUID.aqBlock:
            lastRawAQ = v.zoneHex
            if let r = ZoneAQDecoder.decode(v) {
                lastReading = r
                onReading?(r)
                runAdaptive(r)
            } else {
                note("201D 长度 \(v.count) 与布局不符，原始：\(v.zoneHex)")
            }
        default: break
        }
    }

    private func handleAttr(_ m: ZoneMessage) {
        guard let parsed = ZoneFraming.parseAttribute(m), let b = parsed.value.first else { return }
        switch parsed.id {
        case ZoneAttr.ancMode:
            let mode = ZoneANCMode(rawValue: Int(b))
            // A change we did not command in the last 5 s = user pressed the button -> manual override.
            if let mode, mode != ancMode, !(lastCommandedANC.map { $0.mode == mode && Date().timeIntervalSince($0.at) < 5 } ?? false),
               ancMode != nil {
                adaptive.noteManualChange(at: Date())
                note("检测到手动切换降噪 → 自适应暂停 \(Int(ZoneSettings.shared.adaptive.manualOverrideMinutes)) 分钟")
            }
            ancMode = mode
        default: break
        }
    }

    private func runAdaptive(_ r: ZoneAQReading) {
        let s = ZoneSettings.shared
        guard s.adaptiveEnabled, r.looksPlausible else { return }
        guard !adaptive.isSleepHeld(at: r.date) else { return }   // sleep watch / after onset: keep mode
        adaptive.config = s.adaptive
        if let target = adaptive.update(ambientDb: r.ambientDb, at: r.date, current: ancMode) {
            note(String(format: "自适应：环境 %.0f dB → %@", r.ambientDb, target.label))
            setANC(target, manual: false)
        }
    }

    private func sendAuth(_ type: UInt8, _ payload: Data = Data()) {
        enqueue(ZoneFraming.fragments(type: type, payload: payload), to: authChar, gapMs: 40)
    }

    private func enqueue(_ fragments: [Data], to uuid: CBUUID, gapMs: Int) {
        guard let c = chars[uuid] else { return }
        for (i, f) in fragments.enumerated() { writeQueue.append((f, c, i == fragments.count - 1 ? gapMs : 40)) }
        pump()
    }

    private func pump() {
        guard !writing, !writeQueue.isEmpty, let p = peripheral else { return }
        writing = true
        let item = writeQueue.removeFirst()
        let type: CBCharacteristicWriteType = item.char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(item.data, for: item.char, type: type)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(40, item.gapMs))) { [weak self] in
            self?.writing = false
            self?.pump()
        }
    }
}

// MARK: - CoreBluetooth (delegate queue = main)

extension ZoneManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
                attach(p)
                note("iOS 恢复了 BLE 会话")
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                if let p = peripheral {
                    if p.state == .connected { p.discoverServices(nil) } else { central.connect(p) }
                } else {
                    connectOrScan()
                }
            case .unauthorized: state = .bluetoothOff("没有蓝牙权限")
            case .poweredOff: state = .bluetoothOff("蓝牙已关闭")
            default: state = .bluetoothOff("蓝牙不可用")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData ad: [String: Any], rssi: NSNumber) {
        MainActor.assumeIsolated {
            if (ad[CBAdvertisementDataIsConnectable] as? Bool) == false {
                state = .busyElsewhere
                return
            }
            guard peripheral == nil || peripheral?.identifier == p.identifier, peripheral?.state != .connected else { return }
            central.stopScan()
            attach(p)
            state = .connecting
            central.connect(p)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.peripheralKey)
            central.stopScan()
            p.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            note("连接失败：\(error?.localizedDescription ?? "-")")
            resetLink()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connectOrScan() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            note("已断开：\(error?.localizedDescription ?? "-")")
            let keepFailed: Bool = { if case .failed = state { return true } else { return false } }()
            resetLink()
            if !keepFailed { state = .searching }
            guard ZoneSettings.shared.moduleEnabled else { return }
            // Re-issue a pending connect: completes in the background when the Zone is back.
            attach(p)
            central.connect(p)
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let services = p.services ?? []
            pendingServices = services.count
            for s in services { p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in s.characteristics ?? [] { chars[c.uuid] = c }
            pendingServices -= 1
            guard pendingServices == 0 else { return }
            guard let a = chars[authChar], let at = chars[attrChar] else {
                note("不是 Dyson 控制设备")
                central?.cancelPeripheralConnection(p)
                return
            }
            p.setNotifyValue(true, for: a)
            p.setNotifyValue(true, for: at)
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if c.uuid == attrChar && handshakeStage == 0 && error == nil { startHandshake() }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let v = c.value else { return }
            if c.uuid == authChar { if let m = authAsm.push(v) { handleAuth(m) } }
            else if c.uuid == attrChar { if let m = attrAsm.push(v) { handleAttr(m) } }
            else { handleChar(c.uuid, v) }
        }
    }
}
