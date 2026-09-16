import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var transcriber: WhisperTranscriptionManager
    @EnvironmentObject private var separator: VocalSeparationManager

    @State private var storageBytes: Int64 = 0
    @State private var freedMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Transcription model") {
                    Picker("Default model", selection: $transcriber.selectedModel) {
                        ForEach(WhisperModelType.allCases) { m in
                            VStack(alignment: .leading) {
                                Text("\(m.displayName) · \(m.approxSize)")
                                Text(m.speedNote).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(m)
                        }
                    }
                    #if canImport(WhisperKit)
                    Text("WhisperKit detected — real on-device transcription is active.")
                        .font(.caption).foregroundStyle(.green)
                    #else
                    Text("Preview engine active. Add WhisperKit (SPM) for real offline transcription — see README.")
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                }

                Section("Language") {
                    Picker("Transcription language", selection: $transcriber.transcriptionLanguage) {
                        ForEach(WhisperTranscriptionManager.supportedLanguages, id: \.code) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    Text("Auto-detect lets Whisper choose; pick a language if lyrics are consistently misheard.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Vocal isolation") {
                    Picker("Backend", selection: $separator.mode) {
                        ForEach(VocalSeparationMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    Text(separator.mode.description)
                        .font(.caption).foregroundStyle(.secondary)
                    if separator.mode == .serverHelper {
                        TextField("Server URL", text: $separator.serverBaseURLString)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("Run ServerHelper/demucs_server.py on your Mac, then enter its address (e.g. http://192.168.1.10:8000).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("On-device Demucs is impractical on iPhone today (memory/compute). The pipeline reserves a slot for a future Core ML separator — see VocalSeparationManager.swift.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("App data", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                    Button("Clear temporary files (vocals, exports)") {
                        let freed = StorageManager.clearTempFiles()
                        storageBytes = StorageManager.appStorageBytes()
                        freedMessage = "Freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))."
                    }
                    if let freedMessage {
                        Text(freedMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Imported audio and saved projects are kept. Delete projects from the Library to free more space.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy & offline") {
                    Label("100% offline by default — no API key needed", systemImage: "lock.shield")
                    Label("Audio never leaves your device unless you enable the server helper", systemImage: "internaldrive")
                    Label("No lyric redistribution — your transcriptions stay local", systemImage: "doc")
                }

                Section("About") {
                    LabeledContent("App", value: "LyricFinder 1.0 (MVP)")
                    LabeledContent("Transcription", value: "Whisper (local)")
                    LabeledContent("Licenses", value: "See README")
                }
            }
            .navigationTitle("Settings")
            .task { storageBytes = StorageManager.appStorageBytes() }
        }
    }
}
