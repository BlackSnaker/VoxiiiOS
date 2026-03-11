import Foundation

enum VoxiiCallRingtonePreset: String, CaseIterable, Identifiable {
    case voxii
    case crystal
    case pulse
    case silent

    var id: String { rawValue }

    var filename: String? {
        switch self {
        case .voxii:
            return "voxii_call_ringtone.wav"
        case .crystal:
            return "voxii_call_crystal.wav"
        case .pulse:
            return "voxii_call_pulse.wav"
        case .silent:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .voxii:
            return "waveform.path.ecg"
        case .crystal:
            return "sparkles"
        case .pulse:
            return "dot.radiowaves.left.and.right"
        case .silent:
            return "bell.slash.fill"
        }
    }
}

enum VoxiiMessageSoundPreset: String, CaseIterable, Identifiable {
    case classic
    case glass
    case minimal
    case off

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .classic:
            return "message.fill"
        case .glass:
            return "water.waves"
        case .minimal:
            return "circle.grid.2x1.fill"
        case .off:
            return "speaker.slash.fill"
        }
    }
}

enum VoxiiSoundPreferences {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let callRingtone = "voxii_call_ringtone_preset"
        static let messageSoundPreset = "voxii_message_sound_preset"
    }

    static var callRingtone: VoxiiCallRingtonePreset {
        get {
            VoxiiCallRingtonePreset(rawValue: defaults.string(forKey: Keys.callRingtone) ?? "") ?? .voxii
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.callRingtone)
        }
    }

    static var messageSoundPreset: VoxiiMessageSoundPreset {
        get {
            VoxiiMessageSoundPreset(rawValue: defaults.string(forKey: Keys.messageSoundPreset) ?? "") ?? .classic
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.messageSoundPreset)
        }
    }
}
