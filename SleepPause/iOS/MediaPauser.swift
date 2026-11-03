import Foundation
import AVFoundation
import MediaPlayer

/// Pauses whatever other app is playing (Apple Music, Spotify, 播客, 网易云, B站…) by taking
/// exclusive audio focus.
///
/// iOS gives third-party apps no public API to pause *another* app or to change the system
/// volume. What does work: when an app activates a non-mixable `.playback` session, iOS sends
/// an interruption to the app currently playing, and well-behaved players pause. If we then
/// deactivate WITHOUT `.notifyOthersOnDeactivation`, they are not told to resume.
///
/// Background caveat: iOS only lets an app (re)activate audio in the background if it is
/// already playing audio. So at bedtime we "arm": play an inaudible silent loop with
/// `.mixWithOthers` (your music keeps playing normally). When sleep is detected we flip the
/// same, already-active session to non-mixable, which interrupts the other app.
@MainActor
final class MediaPauser {
    private var player: AVAudioPlayer?
    private(set) var isArmed = false
    private var releaseWorkItem: DispatchWorkItem?

    /// Start the silent mixable loop that keeps the app alive in the background.
    func arm() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        try startSilentLoop()
        isArmed = true
    }

    func disarm() {
        releaseWorkItem?.cancel()
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isArmed = false
    }

    /// Interrupt other audio. Returns a human-readable result for the log.
    @discardableResult
    func pauseOthers(pauseAppleMusic: Bool = true, rearmAfter: Bool = false, releaseAfter: TimeInterval = 3) -> String {
        var notes: [String] = []
        let session = AVAudioSession.sharedInstance()
        let otherWasPlaying = session.isOtherAudioPlaying
        notes.append(otherWasPlaying ? "检测到其他 App 正在播放" : "当前没有检测到其他 App 播放")

        if pauseAppleMusic, MPMediaLibrary.authorizationStatus() == .authorized {
            let music = MPMusicPlayerController.systemMusicPlayer
            if music.playbackState == .playing {
                music.pause()
                notes.append("已暂停 Apple Music")
            }
        }

        do {
            // Non-mixable => iOS interrupts the app that currently owns playback.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            if player == nil { try startSilentLoop() }
            notes.append("已抢占音频焦点")
        } catch {
            notes.append("抢占音频失败：\(error.localizedDescription)")
        }

        // Hold focus briefly (longer while our own sleep sounds fade out), then release quietly so the
        // other app does NOT auto-resume.
        releaseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
            try? session.setActive(false)   // no .notifyOthersOnDeactivation on purpose
            self.isArmed = false
            if rearmAfter { try? self.arm() }
        }
        releaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseAfter, execute: work)

        return notes.joined(separator: "；")
    }

    private func startSilentLoop() throws {
        if let player, player.isPlaying { return }
        let p = try AVAudioPlayer(data: SilentAudio.wavData(seconds: 2))
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        player = p
    }
}
