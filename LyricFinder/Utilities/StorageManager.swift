import Foundation

/// Disk-usage helpers for imported audio, saved projects, and temp files
/// (vocal-separation outputs, exports). Whisper model weights downloaded by
/// WhisperKit live in its own cache and are reported separately when present.
enum StorageManager {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Total bytes used by the app's Documents directory.
    static func appStorageBytes() -> Int64 {
        sizeOfDirectory(documentsURL)
    }

    /// Removes temp vocal-separation outputs and old exports.
    /// Returns bytes freed (best-effort).
    @discardableResult
    static func clearTempFiles() -> Int64 {
        let tmp = FileManager.default.temporaryDirectory
        let before = sizeOfDirectory(tmp)
        if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in items {
                let name = url.lastPathComponent
                if name.hasPrefix("vocals-") || [".txt", ".lrc", ".srt", ".vtt"].contains(url.pathExtension.lowercased()) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        return max(0, before - sizeOfDirectory(tmp))
    }

    // MARK: - Internals

    private static func sizeOfDirectory(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        }
        return total
    }
}
