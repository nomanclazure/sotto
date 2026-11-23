import Foundation
import CoreGraphics

enum HotkeyOption: String, CaseIterable {
    case rightOption, rightCommand, rightControl, fnGlobe, f13

    var label: String {
        switch self {
        case .rightOption:  return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .fnGlobe:      return "Fn / Globe key"
        case .f13:          return "F13"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption:  return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fnGlobe:      return 63
        case .f13:          return 105
        }
    }

    // Modifier hotkeys arrive as flagsChanged events; F13 as keyDown/keyUp.
    var isModifier: Bool { self != .f13 }

    var flagMask: CGEventFlags {
        switch self {
        case .rightOption:  return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fnGlobe:      return .maskSecondaryFn
        case .f13:          return []
        }
    }
}

enum ModelOption: String, CaseIterable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case smallEn = "small.en"

    var fileName: String { "ggml-\(rawValue).bin" }

    var displayName: String {
        switch self {
        case .tinyEn:  return "Tiny (fastest, least accurate) — 75 MB"
        case .baseEn:  return "Base (recommended) — 142 MB"
        case .smallEn: return "Small (most accurate, slower) — 466 MB"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    // Sanity floor for a completed download, in bytes
    var minValidSize: Int64 {
        switch self {
        case .tinyEn:  return 60_000_000
        case .baseEn:  return 120_000_000
        case .smallEn: return 400_000_000
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let hotkey = "hotkey"
        static let model = "model"
        static let micUID = "micDeviceUID"
        static let sounds = "soundsEnabled"
        static let onboarded = "onboarded"
    }

    var enabled: Bool {
        get { d.object(forKey: Key.enabled) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.enabled) }
    }

    var hotkey: HotkeyOption {
        get { HotkeyOption(rawValue: d.string(forKey: Key.hotkey) ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: Key.hotkey) }
    }

    var model: ModelOption {
        get { ModelOption(rawValue: d.string(forKey: Key.model) ?? "") ?? .baseEn }
        set { d.set(newValue.rawValue, forKey: Key.model) }
    }

    /// nil means "System Default" input device
    var micDeviceUID: String? {
        get { d.string(forKey: Key.micUID) }
        set { d.set(newValue, forKey: Key.micUID) }
    }

    var soundsEnabled: Bool {
        get { d.object(forKey: Key.sounds) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.sounds) }
    }

    var onboarded: Bool {
        get { d.bool(forKey: Key.onboarded) }
        set { d.set(newValue, forKey: Key.onboarded) }
    }
}
