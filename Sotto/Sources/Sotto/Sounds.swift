import AppKit

/// Subtle system-sound cues for record start/stop.
enum Sounds {

    static func recordStart() { play("Tink", volume: 0.2) }
    static func recordStop()  { play("Pop", volume: 0.25) }
    static func error()       { play("Basso", volume: 0.3) }

    private static func play(_ name: String, volume: Float) {
        guard Settings.shared.soundsEnabled else { return }
        guard let sound = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true) else { return }
        sound.volume = volume
        sound.play()
    }
}
