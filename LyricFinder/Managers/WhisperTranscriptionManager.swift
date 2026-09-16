import Foundation

/// Orchestrates local/offline lyric transcription.
///
/// MVP strategy (compiles with zero third-party deps):
/// - Uses `MockTranscriptionEngine` so Import → Play → Transcribe → Edit →
///   Export works immediately for testing the full pipeline.
/// - `WhisperKitEngine` (below, conditionally compiled with
///   `canImport(WhisperKit)`) is the production path. Add WhisperKit via SPM
///   and it is used automatically — no other code changes required.
///
/// No OpenAI API key is required in either path.
@MainActor
final class WhisperTranscriptionManager: ObservableObject {
    private static let modelKey = "LyricFinder.selectedModel"
    private static let languageKey = "LyricFinder.transcriptionLanguage"

    /// Common transcription languages (Whisper supports ~99; this covers the
    /// lyric use-case while keeping the picker usable).
    static let supportedLanguages: [(code: String, label: String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"), ("hi", "Hindi"),
    ]

    @Published private(set) var isTranscribing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage: String = "Idle"
    @Published var selectedModel: WhisperModelType {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelKey) }
    }
    @Published var transcriptionLanguage: String {
        didSet { UserDefaults.standard.set(transcriptionLanguage, forKey: Self.languageKey) }
    }

    init() {
        let storedModel = UserDefaults.standard.string(forKey: Self.modelKey)
            .flatMap(WhisperModelType.init(rawValue:)) ?? .small
        self.selectedModel = storedModel
        self.transcriptionLanguage = UserDefaults.standard.string(forKey: Self.languageKey) ?? "auto"
    }

    private var currentTask: Task<[LyricLine], Error>?

    var canCancel: Bool { isTranscribing }

    func cancel() {
        currentTask?.cancel()
    }

    /// Runs vocal separation (optional) then transcription, returning lyric lines.
    /// - Parameters:
    ///   - audioURL: original (or imported) audio file.
    ///   - settings: model + vocal-isolation choices.
    ///   - separator: vocal separation manager (respects its `mode`).
    ///   - progressHandler: 0...1 combined progress for UI.
    func transcribe(
        audioURL: URL,
        settings: ProcessingSettings,
        separator: VocalSeparationManager,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> [LyricLine] {
        // Cancel any in-flight run; never hold two large models at once.
        currentTask?.cancel()

        let task = Task<[LyricLine], Error> {
            await MainActor.run {
                self.isTranscribing = true
                self.progress = 0
                self.statusMessage = "Preparing…"
            }
            defer {
                Task { @MainActor in
                    self.isTranscribing = false
                }
            }

            func report(_ p: Double, _ msg: String) async {
                await MainActor.run {
                    self.progress = p
                    self.statusMessage = msg
                }
                progressHandler(p, msg)
            }

            // 1. Optional vocal separation (0% → 25%).
            var workingURL = audioURL
            if settings.vocalIsolationEnabled, separator.mode != .off {
                await report(0.02, "Isolating vocals…")
                workingURL = try await separator.process(audioURL)
                try Task.checkCancellation()
                await report(0.25, "Vocals ready. Loading model…")
            } else {
                await report(0.05, "Loading transcription model…")
            }

            // 2. Transcribe (25% → 95%). Engine is chosen at compile time:
            //    WhisperKit when available, otherwise the mock engine.
            let engine = Self.makeEngine(model: settings.model)
            let segments = try await engine.transcribe(
                audioURL: workingURL,
                language: settings.language
            ) { p, msg in
                Task { @MainActor in
                    // Map engine progress into the 25–95% band.
                    let mapped = 0.25 + p * 0.70
                    self.progress = mapped
                    self.statusMessage = msg
                    progressHandler(mapped, msg)
                }
            }
            try Task.checkCancellation()

            // 3. Parse into lyric lines (95% → 100%).
            await report(0.95, "Formatting lyrics…")
            let lines = LyricsParser.lines(from: segments)
            await report(1.0, "Done")
            return lines
        }

        currentTask = task
        do {
            return try await task.value
        } catch is CancellationError {
            await MainActor.run {
                self.isTranscribing = false
                self.statusMessage = "Cancelled"
            }
            throw CancellationError()
        } catch {
            await MainActor.run {
                self.isTranscribing = false
                self.statusMessage = "Failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Engine selection

    private static func makeEngine(model: WhisperModelType) -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperKitEngine(model: model)
        #else
        return MockTranscriptionEngine(model: model)
        #endif
    }
}

// MARK: - Engine protocol

/// Progress callback runs off the main thread; hop to MainActor for UI.
protocol TranscriptionEngine: Sendable {
    func transcribe(
        audioURL: URL,
        language: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [TranscriptionSegment]
}

// MARK: - Mock engine (MVP)

/// Deterministic placeholder so the full app pipeline works with no model
/// downloads. It synthesises evenly-spaced lyric lines across the audio
/// duration. Replaced automatically by `WhisperKitEngine` once WhisperKit
/// is added via SPM.
struct MockTranscriptionEngine: TranscriptionEngine {
    var model: WhisperModelType

    func transcribe(
        audioURL: URL,
        language: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [TranscriptionSegment] {
        let duration = await Self.audioDuration(url: audioURL)
        let total = max(duration, 30)
        // Simulate chunked work with cancellation support.
        let steps = 20
        for i in 1...steps {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 120_000_000) // 0.12s
            let p = Double(i) / Double(steps)
            progress(p, "Transcribing (preview engine)… \(Int(p * 100))%")
        }
        // Evenly spaced demo lines with word timings for karaoke UI.
        let demoTexts = [
            "This is a preview transcription",
            "Add WhisperKit for real lyrics",
            "Import a song to get started",
            "Every line keeps its timestamp",
            "Tap a line to seek the audio",
            "Edit any line to fix mistakes",
            "Export to TXT, LRC, SRT or VTT",
            "Your projects are saved offline"
        ]
        let lineCount = max(8, Int(total / 15))
        var segments: [TranscriptionSegment] = []
        let slice = total / Double(lineCount)
        for i in 0..<lineCount {
            let text = demoTexts[i % demoTexts.count]
            let start = Double(i) * slice
            let end = min(start + slice * 0.95, total)
            let words = Self.words(for: text, start: start, end: end)
            segments.append(TranscriptionSegment(text: text, startTime: start, endTime: end, words: words))
        }
        return segments
    }

    private static func words(for text: String, start: Double, end: Double) -> [WordTimestamp] {
        let parts = text.split(separator: " ")
        guard !parts.isEmpty else { return [] }
        let per = (end - start) / Double(parts.count)
        return parts.enumerated().map { idx, w in
            WordTimestamp(word: String(w),
                          startTime: start + Double(idx) * per,
                          endTime: start + Double(idx + 1) * per)
        }
    }

    private static func audioDuration(url: URL) async -> Double {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 {
                    cont.resume(returning: Double(file.length) / file.processingFormat.sampleRate)
                } else {
                    cont.resume(returning: 0)
                }
            }
        }
    }
}

#if canImport(WhisperKit)
import AVFoundation
import WhisperKit

/// Production engine backed by WhisperKit (Core ML, on-device, offline).
/// Add via SPM: https://github.com/argmaxinc/WhisperKit
struct WhisperKitEngine: TranscriptionEngine {
    var model: WhisperModelType

    func transcribe(
        audioURL: URL,
        language: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [TranscriptionSegment] {
        // First launch downloads the model (~75 MB–2.9 GB depending on size);
        // afterwards everything is offline from the on-device cache.
        progress(0.05, "Loading \(model.displayName) model… (first run downloads it)")
        let pipe = try await WhisperKit(model: model.whisperKitModelSlug, verbose: false)
        try Task.checkCancellation()

        // Word timestamps ON so the Now Playing view can do karaoke
        // highlighting; language nil = auto-detect.
        let options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language,
            wordTimestamps: true
        )
        progress(0.2, "Transcribing with \(model.displayName)…")

        // Throttles status updates: the callback fires per decode step, but
        // we only hop to the main actor when newly decoded text appears.
        let tracker = SnippetTracker()
        let results: [TranscriptionResult] = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        ) { prog in
            let snippet = String(prog.text.suffix(80))
            if tracker.shouldReport(snippet) {
                let message = snippet.isEmpty
                    ? "Transcribing with \(model.displayName)…"
                    : "Heard: “…\(snippet)”"
                Task { @MainActor in progress(0.5, message) }
            }
            // Returning false aborts decoding promptly on Cancel.
            return Task.isCancelled ? false : nil
        }
        try Task.checkCancellation()

        var segments: [TranscriptionSegment] = []
        for r in results {
            for s in r.segments {
                let words = s.words?.map {
                    WordTimestamp(word: $0.word, startTime: Double($0.start), endTime: Double($0.end))
                }
                segments.append(TranscriptionSegment(
                    text: s.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: Double(s.start),
                    endTime: Double(s.end),
                    words: words
                ))
            }
        }
        progress(1.0, "Transcription complete")
        return segments
    }
}

/// Thread-safe "only report when the text changed" gate for the decode
/// callback, which may fire thousands of times from background threads.
/// `lock` serializes all access to `last`, hence unchecked Sendable.
private final class SnippetTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ""
    func shouldReport(_ snippet: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard snippet != last else { return false }
        last = snippet
        return true
    }
}
#else
import AVFoundation
#endif
