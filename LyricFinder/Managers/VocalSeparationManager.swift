import Foundation

/// How vocal isolation should be performed.
///
/// Full Demucs/UVR models are too heavy for direct on-iPhone execution today,
/// so the architecture supports three interchangeable backends:
/// - `.off`: skip separation, transcribe the original mix.
/// - `.localStub`: placeholder for a future Core ML vocal-separation model.
/// - `.serverHelper`: offload to the bundled Python Demucs helper (Mac/server).
enum VocalSeparationMode: String, CaseIterable, Identifiable, Codable {
    case off
    case localStub
    case serverHelper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off (transcribe mix)"
        case .localStub: return "On-device (experimental)"
        case .serverHelper: return "Mac / Server helper"
        }
    }

    var description: String {
        switch self {
        case .off:
            return "Transcribe the original audio without vocal separation."
        case .localStub:
            return "Reserves the pipeline for a Core ML separator. Currently passes audio through while the model is integrated."
        case .serverHelper:
            return "Sends audio to the Demucs helper running on your Mac or server and uses the returned vocals file."
        }
    }
}

protocol VocalSeparator {
    /// Returns a URL to vocals-only (or enhanced) audio.
    func separate(
        inputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL
}

/// Pass-through separator used when mode is off or on-device model is absent.
struct PassThroughSeparator: VocalSeparator {
    func separate(inputURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        progress(1.0)
        return inputURL
    }
}

/// Uploads audio to the Python Demucs helper and downloads the vocals file.
///
/// Expected helper endpoints (see ServerHelper/demucs_server.py):
///   POST /separate  (multipart `file`) -> { "vocals_url": "/downloads/<id>_vocals.wav" }
///   GET  /downloads/<name>
struct ServerVocalSeparator: VocalSeparator {
    var serverBaseURL: URL

    func separate(inputURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        progress(0.05)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverBaseURL.appendingPathComponent("separate"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let fileData = try Data(contentsOf: inputURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(inputURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        progress(0.8)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LyricFinder", code: 2001,
                          userInfo: [NSLocalizedDescriptionKey: "Vocal-separation server returned an error."])
        }
        struct Reply: Decodable { var vocals_url: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let vocalsURL: URL
        if reply.vocals_url.hasPrefix("http") {
            vocalsURL = URL(string: reply.vocals_url)!
        } else {
            vocalsURL = serverBaseURL.appendingPathComponent(reply.vocals_url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        let (tmpURL, _) = try await URLSession.shared.download(from: vocalsURL)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocals-\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        progress(1.0)
        return dest
    }
}

/// Orchestrates vocal separation with a swappable backend.
@MainActor
final class VocalSeparationManager: ObservableObject {
    private static let modeKey = "LyricFinder.vocalSeparationMode"
    private static let serverURLKey = "LyricFinder.vocalServerURL"

    @Published var mode: VocalSeparationMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    /// e.g. http://192.168.1.10:8000 — set in Settings.
    @Published var serverBaseURLString: String {
        didSet { UserDefaults.standard.set(serverBaseURLString, forKey: Self.serverURLKey) }
    }
    @Published private(set) var isSeparating = false
    @Published private(set) var progress: Double = 0

    init() {
        let storedMode = UserDefaults.standard.string(forKey: Self.modeKey)
            .flatMap(VocalSeparationMode.init(rawValue:)) ?? .off
        self.mode = storedMode
        self.serverBaseURLString = UserDefaults.standard.string(forKey: Self.serverURLKey)
            ?? "http://localhost:8000"
    }

    func process(_ inputURL: URL) async throws -> URL {
        isSeparating = true
        progress = 0
        defer { isSeparating = false }

        let separator: VocalSeparator
        switch mode {
        case .off, .localStub:
            // .localStub is a deliberate passthrough until a Core ML
            // separator (e.g. converted Hybrid Demucs / MDX) is bundled.
            separator = PassThroughSeparator()
        case .serverHelper:
            guard let base = URL(string: serverBaseURLString) else {
                throw NSError(domain: "LyricFinder", code: 2002,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid server URL. Check Settings."])
            }
            separator = ServerVocalSeparator(serverBaseURL: base)
        }

        let out = try await separator.separate(inputURL: inputURL) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }
        progress = 1.0
        return out
    }
}
