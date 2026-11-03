import Foundation
import AVFoundation

/// Sleep sounds: live-generated brown / pink / white noise (no loops) through the Zone with ANC
/// kept ON, faded out smoothly once the watch detects sleep (or after an optional timer).
/// Ideas: Rest Easy / Veil / Noise Machine sleep-timer fade-outs — but triggered by real sleep onset.
@MainActor
final class SleepSoundPlayer: ObservableObject {
    static let shared = SleepSoundPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var isFading = false
    @Published var color: NoiseColor { didSet { d.set(color.rawValue, forKey: "sounds.color"); synthBox.setColor(color) } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "sounds.volume"); if !isFading { gainBox.set(Float(volume)) } } }
    @Published var fadeSeconds: Double { didSet { d.set(fadeSeconds, forKey: "sounds.fade") } }
    @Published var timerMinutes: Double { didSet { d.set(timerMinutes, forKey: "sounds.timer") } }   // 0 = only on sleep

    private let d = UserDefaults.standard
    private var engine: AVAudioEngine?
    private var fadeTimer: Timer?
    private var stopTimer: Timer?
    private nonisolated let synthBox = SynthBox()
    private nonisolated let gainBox = GainBox()

    private init() {
        color = NoiseColor(rawValue: d.string(forKey: "sounds.color") ?? "") ?? .brown
        volume = d.object(forKey: "sounds.volume") as? Double ?? 0.35
        fadeSeconds = d.object(forKey: "sounds.fade") as? Double ?? 90
        timerMinutes = d.object(forKey: "sounds.timer") as? Double ?? 0
    }

    func start() {
        guard !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Mix with others so the sleep-pause keep-alive and other audio keep working.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let format = engine.outputNode.inputFormat(forBus: 0)
            let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
            synthBox.setColor(color)
            let node = Self.makeNode(format: mono, synth: synthBox, gain: gainBox)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: mono)
            gainBox.set(0)
            try engine.start()
            self.engine = engine
            isPlaying = true
            fade(to: Float(volume), over: 5, thenStop: false)          // gentle fade-in
            // Keep Zone ANC ON for sleep sounds (never turns it off).
            if ZoneSettings.shared.moduleEnabled, ZoneManager.shared.isReady, ZoneManager.shared.ancMode != .anc {
                ZoneManager.shared.setANC(.anc, manual: false)
            }
            stopTimer?.invalidate()
            if timerMinutes > 0 {
                stopTimer = Timer.scheduledTimer(withTimeInterval: timerMinutes * 60, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.fadeOutAndStop() }
                }
            }
        } catch {
            AppModel.shared.add("助眠声音启动失败：\(error.localizedDescription)")
        }
    }

    /// Built outside the main actor: the render block runs on the real-time audio thread.
    private nonisolated static func makeNode(format: AVAudioFormat, synth: SynthBox, gain: GainBox) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard let buf = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.fill(buf, count: Int(frameCount), gain: gain.get())
            return noErr
        }
    }

    /// Smooth equal-power fade, then stop the engine.
    func fadeOutAndStop(seconds: Double? = nil) {
        guard isPlaying else { return }
        fade(to: 0, over: seconds ?? fadeSeconds, thenStop: true)
    }

    func stopNow() {
        fadeTimer?.invalidate(); stopTimer?.invalidate()
        engine?.stop(); engine = nil
        isPlaying = false; isFading = false
    }

    private func fade(to target: Float, over seconds: Double, thenStop: Bool) {
        fadeTimer?.invalidate()
        let env = FadeEnvelope(from: Double(gainBox.get()), to: Double(target), start: Date(), duration: seconds)
        isFading = thenStop
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let now = Date()
                self.gainBox.set(Float(env.gain(at: now)))
                if env.isFinished(at: now) {
                    t.invalidate()
                    if thenStop { self.stopNow() } else { self.isFading = false }
                }
            }
        }
    }
}

/// Lock-protected state touched by the real-time audio thread.
final class SynthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var synth = NoiseSynth(color: .brown)
    func setColor(_ c: NoiseColor) { lock.lock(); synth = NoiseSynth(color: c); lock.unlock() }
    func fill(_ p: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
        guard lock.try() else { for i in 0..<count { p[i] = 0 }; return }   // never block the audio thread
        synth.fill(p, count: count, gain: gain); lock.unlock()
    }
}

final class GainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func set(_ v: Float) { lock.lock(); value = v; lock.unlock() }
    func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }
}
