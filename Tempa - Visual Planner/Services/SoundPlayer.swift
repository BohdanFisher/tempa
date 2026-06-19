import Foundation
import AVFoundation

/// Tiny shared player for short UI sound effects (bundled mp3s).
/// Uses `.playback` + `.mixWithOthers` so the chime always plays (even on silent)
/// without interrupting the user's other audio.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?
    private init() {}

    func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[Tempa] sound not found in bundle: \(name).\(ext)")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            player?.volume = volume
            player?.currentTime = 0
            player?.play()
        } catch {
            print("[Tempa] sound play error:", error)
        }
    }

    /// The chime used on task completion and when a focus session ends — at 50% volume.
    func playSuccess() {
        play("universfield-new-notification-013-363676", volume: 0.5)
    }
}
