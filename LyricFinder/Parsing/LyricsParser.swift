import Foundation

/// Converts raw transcription segments into readable lyric lines.
enum LyricsParser {
    /// Max characters per displayed line before wrapping.
    static var maxCharsPerLine = 48

    /// Breaks segments into lyric lines, preserving timestamps + word timings.
    static func lines(from segments: [TranscriptionSegment]) -> [LyricLine] {
        var out: [LyricLine] = []
        for seg in segments {
            let chunks = breakIntoLines(text: seg.text, maxChars: maxCharsPerLine)
            if chunks.count <= 1 || seg.words == nil {
                out.append(LyricLine(text: seg.text.trimmed,
                                     startTime: seg.startTime,
                                     endTime: seg.endTime,
                                     words: seg.words))
            } else {
                // Split timing evenly across wrapped lines; re-slice words.
                let span = (seg.endTime - seg.startTime) / Double(chunks.count)
                for (i, chunk) in chunks.enumerated() {
                    let s = seg.startTime + Double(i) * span
                    let e = (i == chunks.count - 1) ? seg.endTime : s + span
                    let words = sliceWords(seg.words, forChunk: chunk, fullText: seg.text, start: s, end: e)
                    out.append(LyricLine(text: chunk, startTime: s, endTime: e, words: words))
                }
            }
        }
        return out.filter { !$0.text.isEmpty }
    }

    /// Greedy word-wrap that keeps words intact.
    static func breakIntoLines(text: String, maxChars: Int) -> [String] {
        let words = text.trimmed.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for w in words {
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= maxChars {
                current += " " + w
            } else {
                lines.append(current)
                current = w
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Helpers

    private static func sliceWords(
        _ words: [WordTimestamp]?,
        forChunk chunk: String,
        fullText: String,
        start: Double,
        end: Double
    ) -> [WordTimestamp]? {
        guard let words, !words.isEmpty else { return nil }
        // Best-effort: match by word order.
        let chunkWords = chunk.split(separator: " ").map(String.init)
        var result: [WordTimestamp] = []
        var cursor = 0
        for cw in chunkWords {
            if let idx = words[cursor...].firstIndex(where: { $0.word.lowercased() == cw.lowercased() }) {
                result.append(words[idx])
                cursor = min(idx + 1, words.count)
            } else if cursor < words.count {
                result.append(words[cursor])
                cursor += 1
            }
        }
        if result.isEmpty { return nil }
        // Re-stretch to the chunk time span for smooth karaoke.
        let per = (end - start) / Double(result.count)
        return result.enumerated().map { i, w in
            WordTimestamp(id: w.id, word: w.word,
                          startTime: start + Double(i) * per,
                          endTime: start + Double(i + 1) * per)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
