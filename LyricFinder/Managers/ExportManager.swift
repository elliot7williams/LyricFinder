import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case txt, lrc, srt, vtt
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

/// Exports lyrics to TXT / LRC / SRT / VTT and returns a temp file URL
/// suitable for `ShareLink` / `UIActivityViewController`.
enum ExportManager {
    static func export(project: TranscriptionProject, format: ExportFormat) throws -> URL {
        let content: String
        switch format {
        case .txt: content = txt(project: project)
        case .lrc: content = lrc(project: project)
        case .srt: content = srt(project: project)
        case .vtt: content = vtt(project: project)
        }
        let safeTitle = project.title.isEmpty ? "lyrics" : project.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle).\(format.fileExtension)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Formatters

    static func txt(project: TranscriptionProject) -> String {
        var s = ""
        if !project.title.isEmpty { s += "\(project.title)\n" }
        if !project.artist.isEmpty { s += "\(project.artist)\n" }
        if !project.title.isEmpty || !project.artist.isEmpty { s += "\n" }
        s += project.lyrics.map(\.text).joined(separator: "\n")
        return s + "\n"
    }

    /// LRC with [mm:ss.xx] timestamps, compatible with music players.
    static func lrc(project: TranscriptionProject) -> String {
        var lines: [String] = []
        if !project.title.isEmpty { lines.append("[ti:\(project.title)]") }
        if !project.artist.isEmpty { lines.append("[ar:\(project.artist)]") }
        if !project.album.isEmpty { lines.append("[al:\(project.album)]") }
        for l in project.lyrics {
            lines.append("[\(lrcTimestamp(l.startTime))]\(l.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func srt(project: TranscriptionProject) -> String {
        var blocks: [String] = []
        for (i, l) in project.lyrics.enumerated() {
            blocks.append("\(i + 1)\n\(srtTimestamp(l.startTime)) --> \(srtTimestamp(l.endTime))\n\(l.text)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func vtt(project: TranscriptionProject) -> String {
        var s = "WEBVTT\n\n"
        for l in project.lyrics {
            s += "\(vttTimestamp(l.startTime)) --> \(vttTimestamp(l.endTime))\n\(l.text)\n\n"
        }
        return s
    }

    // MARK: - Timestamp helpers

    /// mm:ss.xx (centiseconds) for LRC.
    static func lrcTimestamp(_ t: Double) -> String {
        let clamped = max(0, t)
        let m = Int(clamped / 60)
        let s = Int(clamped.truncatingRemainder(dividingBy: 60))
        let cs = Int((clamped * 100).truncatingRemainder(dividingBy: 100))
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    /// HH:MM:SS,mmm for SRT.
    static func srtTimestamp(_ t: Double) -> String {
        let ms = Int(max(0, t) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }

    /// HH:MM:SS.mmm for VTT.
    static func vttTimestamp(_ t: Double) -> String {
        let ms = Int(max(0, t) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }
}
