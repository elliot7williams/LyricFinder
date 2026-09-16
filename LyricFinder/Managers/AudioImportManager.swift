import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Info about an imported audio file copied into the app sandbox.
struct ImportedAudio: Equatable {
    var fileURL: URL
    var fileName: String
    var duration: Double
    var fileSizeBytes: Int64
}

/// Handles importing audio via UIDocumentPicker and copying into Documents/Audio.
///
/// Security-scoped URLs from the picker are resolved and copied so the app
/// retains access across launches.
final class AudioImportManager {
    static let shared = AudioImportManager()

    /// Common audio types accepted by the importer.
    static var supportedContentTypes: [UTType] {
        [.mp3, .mpeg4Audio, .wav, .aiff,
         .init(filenameExtension: "flac"),
         .init(filenameExtension: "ogg"),
         .init(filenameExtension: "opus"),
         .audio]
            .compactMap { $0 }
    }

    private init() {}

    private var audioDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Audio", isDirectory: true)
    }

    /// Copies a picked file into the sandbox and reads duration + size.
    func importAudio(from sourceURL: URL) throws -> ImportedAudio {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let base = (fileName as NSString).deletingPathExtension
        let safeBase = base.isEmpty ? "audio" : base
        // Avoid collisions with a timestamp suffix.
        let storedName = "\(safeBase)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let dest = audioDirectory.appendingPathComponent(storedName)

        // Source may be security-scoped; coordinate the read.
        var readError: NSError?
        var fileData: Data?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &readError) { url in
            fileData = try? Data(contentsOf: url)
        }
        if let readError { throw readError }
        guard let data = fileData else {
            throw NSError(domain: "LyricFinder", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read the selected audio file."])
        }
        try data.write(to: dest, options: .atomic)

        let duration = Self.audioDuration(url: dest)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? Int64(data.count)

        return ImportedAudio(
            fileURL: dest,
            fileName: fileName,
            duration: duration.isFinite ? duration : 0,
            fileSizeBytes: size
        )
    }

    /// Resolves the stored audio URL for a project.
    func urlForStoredFile(named storedFileName: String) -> URL {
        audioDirectory.appendingPathComponent(storedFileName)
    }

    /// Duration without the deprecated AVURLAsset.duration accessor.
    private static func audioDuration(url: URL) -> Double {
        if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 {
            return Double(file.length) / file.processingFormat.sampleRate
        }
        return 0
    }
}
