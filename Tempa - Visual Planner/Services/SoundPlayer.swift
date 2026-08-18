import Foundation
import AVFoundation

/// Tiny shared player for short UI sound effects (bundled mp3s).
///
/// Category is `.ambient`, deliberately. The chime used to run on `.playback`,
/// which is the category for music: it ignores the ring/silent switch and rides
/// the MEDIA volume — usually left near max — so a small confirmation sound came
/// out louder than every other noise the phone makes, and the side buttons
/// wouldn't touch it unless pressed during the one second it played. `.ambient`
/// makes it behave like a UI sound: the silent switch mutes it, and it still
/// mixes with whatever else is playing instead of interrupting it.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// The level every UI sound plays at, and the ceiling none may exceed.
    /// `AVAudioPlayer.volume` is linear gain, not perceived loudness: 0.5 is
    /// only −6 dB (barely quieter), 0.25 is −12 dB, this is about −18 dB. The
    /// source file peaks at −7.7 dBFS, so the chime lands around −26 dBFS —
    /// clearly a nudge, not an alarm. Turn it DOWN here if it's still too much;
    /// `play` clamps to it, so no call site can bring the blast back.
    static let volume: Float = 0.12

    private var player: AVAudioPlayer?
    private init() {}

    func play(_ name: String, ext: String = "mp3", volume: Float = SoundPlayer.volume) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[Tempa] sound not found in bundle: \(name).\(ext)")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            // Clamped, not trusted: a caller asking for more gets the ceiling.
            let applied = min(max(volume, 0), Self.volume)
            player?.volume = applied
            player?.currentTime = 0
            player?.play()
            // Printed so it's obvious from the console which build is running —
            // if this line is missing while a chime plays, the device has a
            // stale build and no source change will be audible.
            print("[Tempa] chime \(name) · volume \(applied) · category ambient")
        } catch {
            print("[Tempa] sound play error:", error)
        }
    }

    /// The one chime in the app — task completed, and focus session finished.
    /// Both go through here so the level can never drift apart again.
    func playSuccess() {
        play("universfield-new-notification-013-363676")
    }
}
