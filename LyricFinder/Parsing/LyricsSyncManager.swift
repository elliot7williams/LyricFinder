import Foundation

/// Computes which lyric line / word is active at a playback position.
enum LyricsSyncManager {
    /// Index of the line containing `time`, or the last line before it.
    static func currentLineIndex(at time: Double, in lines: [LyricLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        if let i = lines.firstIndex(where: { $0.contains(time: time) }) { return i }
        // Before first line → nil; between lines → previous line stays lit.
        let past = lines.lastIndex(where: { $0.startTime <= time })
        return past
    }

    /// Index of the active word within a line, if word timings exist.
    static func currentWordIndex(at time: Double, in line: LyricLine) -> Int? {
        guard let words = line.words, !words.isEmpty else { return nil }
        return words.firstIndex(where: { $0.isActive(at: time) })
    }

    /// Next line change after `time` (useful for timers / auto-scroll).
    static func nextBoundary(after time: Double, in lines: [LyricLine]) -> Double? {
        lines.map(\.startTime).sorted().first(where: { $0 > time })
    }
}
