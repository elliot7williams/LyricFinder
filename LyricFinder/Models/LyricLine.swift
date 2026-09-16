import Foundation

/// A single timestamped lyric line.
struct LyricLine: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var text: String
    /// Start time in seconds.
    var startTime: Double
    /// End time in seconds.
    var endTime: Double
    var words: [WordTimestamp]?
    /// Optional confidence 0...1 (future: model comparison UI).
    var confidence: Double?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: Double,
        endTime: Double,
        words: [WordTimestamp]? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.words = words
        self.confidence = confidence
    }

    var duration: Double { max(0, endTime - startTime) }

    func contains(time: Double) -> Bool {
        time >= startTime && time < endTime
    }
}

/// Word-level timestamp for karaoke highlighting.
struct WordTimestamp: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var word: String
    var startTime: Double
    var endTime: Double

    init(id: UUID = UUID(), word: String, startTime: Double, endTime: Double) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
    }

    func isActive(at time: Double) -> Bool {
        time >= startTime && time < endTime
    }
}

/// Raw segment emitted by a transcription engine before line-breaking.
struct TranscriptionSegment: Codable, Equatable {
    var text: String
    var startTime: Double
    var endTime: Double
    var words: [WordTimestamp]?
}
