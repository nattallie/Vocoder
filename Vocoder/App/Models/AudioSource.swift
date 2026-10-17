import Foundation

enum AudioSourceKind {
    case bundledSpeech
    case bundledMusic
    case recorded
    case imported

    var iconName: String {
        switch self {
        case .bundledSpeech: return "waveform"
        case .bundledMusic: return "music.note"
        case .recorded: return "mic.fill"
        case .imported: return "square.and.arrow.down"
        }
    }
}

/// One playable/vocodable audio source: the two bundled demo clips, or a user-added
/// recording/import. Identity is the file path for user clips (stable across relaunches
/// since the file stays put) and a fixed string for the two bundled ones.
struct AudioSource: Identifiable {
    let id: String
    let name: String
    let kind: AudioSourceKind
    let url: URL

    var iconName: String { kind.iconName }

    var isDeletable: Bool {
        switch kind {
        case .bundledSpeech, .bundledMusic: return false
        case .recorded, .imported: return true
        }
    }
}

extension AudioSource: Equatable {
    static func == (lhs: AudioSource, rhs: AudioSource) -> Bool { lhs.id == rhs.id }
}
