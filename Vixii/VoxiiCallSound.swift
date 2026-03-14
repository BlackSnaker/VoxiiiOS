import Foundation

enum VoxiiCallSound {
    static var selectedRingtone: VoxiiCallRingtonePreset {
        VoxiiSoundPreferences.callRingtone
    }

    static var ringtoneFilename: String? {
        selectedRingtone.filename
    }

    static var bundledRingtoneURL: URL? {
        bundledRingtoneURL(forPreset: selectedRingtone)
    }

    static func bundledRingtoneURL(forPreset preset: VoxiiCallRingtonePreset) -> URL? {
        guard let filename = preset.filename else {
            return nil
        }
        return Bundle.main.url(
            forResource: filename.replacingOccurrences(of: ".wav", with: ""),
            withExtension: "wav"
        )
    }
}
