import Foundation

/// Persisted transcription project.
struct TranscriptionProject: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    /// Original imported file name (e.g. "song.mp3").
    var audioFileName: String
    /// File name of the audio copy inside Documents/Audio/.
    var audioStoredFileName: String
    var duration: Double
    var createdAt: Date
    var updatedAt: Date
    var lyrics: [LyricLine]
    var modelUsed: WhisperModelType
    var vocalIsolationEnabled: Bool
    var language: String

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        album: String = "",
        audioFileName: String,
        audioStoredFileName: String,
        duration: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lyrics: [LyricLine] = [],
        modelUsed: WhisperModelType = .small,
        vocalIsolationEnabled: Bool = false,
        language: String = "auto"
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.audioFileName = audioFileName
        self.audioStoredFileName = audioStoredFileName
        self.duration = duration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lyrics = lyrics
        self.modelUsed = modelUsed
        self.vocalIsolationEnabled = vocalIsolationEnabled
        self.language = language
    }
}

/// Transient settings for a transcription run (also stored per-project).
struct ProcessingSettings: Codable, Equatable {
    var model: WhisperModelType
    var vocalIsolationEnabled: Bool
    var language: String

    static let `default` = ProcessingSettings(
        model: .small,
        vocalIsolationEnabled: false,
        language: "auto"
    )
}
