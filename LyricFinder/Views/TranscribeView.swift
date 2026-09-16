import SwiftUI

struct TranscribeView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var projects: ProjectManager
    @EnvironmentObject private var transcriber: WhisperTranscriptionManager
    @EnvironmentObject private var separator: VocalSeparationManager

    @Binding var selection: Int
    @Binding var draftAudio: ImportedAudio?
    @Binding var draftProject: TranscriptionProject?

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var peaks: [Float] = []
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var vocalToggle = false
    @State private var lines: [LyricLine] = []
    @State private var transcribeError: String?
    @State private var showingEditor = false
    @State private var editableProject: TranscriptionProject?
    @State private var exportURL: URL?
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    importCard
                    if let audio = draftAudio {
                        playbackCard(audio: audio)
                        settingsCard
                        actionCard(audio: audio)
                    }
                    if !lines.isEmpty {
                        resultCard
                    }
                }
                .padding()
            }
            .navigationTitle("Transcribe")
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: AudioImportManager.supportedContentTypes,
                allowsMultipleSelection: false
            ) { handleImport($0) }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: { Text(importError ?? "") }
            .alert("Transcription failed", isPresented: Binding(
                get: { transcribeError != nil },
                set: { if !$0 { transcribeError = nil } }
            )) {
                Button("OK") { transcribeError = nil }
            } message: { Text(transcribeError ?? "") }
            .sheet(isPresented: $showingEditor) {
                NavigationStack {
                    LyricsEditorView(project: Binding(
                        get: { editableProject ?? TranscriptionProject(title: title, audioFileName: "", audioStoredFileName: "", duration: 0, lyrics: lines) },
                        set: { editableProject = $0 }
                    )) {
                        if let p = editableProject {
                            lines = p.lyrics
                            projects.save(p)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let exportURL { ShareSheet(url: exportURL) }
            }
        }
        .onChange(of: draftAudio) { _, new in
            if let new {
                title = (new.fileName as NSString).deletingPathExtension
                player.load(url: new.fileURL)
                Task { peaks = await WaveformGenerator.peaks(for: new.fileURL) }
            }
        }
    }

    // MARK: - Cards

    private var importCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "waveform.and.mic")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(draftAudio == nil ? "Import a song to begin" : "Imported file")
                    .font(.headline)
                if let audio = draftAudio {
                    Text(audio.fileName).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(audio.duration.compactTimeString) · \(audio.fileSizeBytes.fileSizeString)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Button(draftAudio == nil ? "Import Audio (MP3, M4A, WAV…)" : "Choose Different File") {
                    showingImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func playbackCard(audio: ImportedAudio) -> some View {
        GroupBox("Playback") {
            VStack(spacing: 10) {
                if peaks.isEmpty {
                    ProgressView().frame(height: 60)
                } else {
                    WaveformView(
                        peaks: peaks,
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0
                    ) { p in
                        player.seek(to: p * player.duration)
                    }
                    .frame(height: 64)
                }
                HStack {
                    Text(player.currentTime.compactTimeString).monospacedDigit()
                    Spacer()
                    Text(audio.duration.compactTimeString).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10").font(.title2) }
                    Button { player.restart() } label: { Image(systemName: "backward.end.fill").font(.title2) }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }
                    Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10").font(.title2) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }

    private var settingsCard: some View {
        GroupBox("Transcription") {
            VStack(spacing: 12) {
                TextField("Song title", text: $title).textFieldStyle(.roundedBorder)
                TextField("Artist (optional)", text: $artist).textFieldStyle(.roundedBorder)
                TextField("Album (optional)", text: $album).textFieldStyle(.roundedBorder)
                Picker("Model", selection: $transcriber.selectedModel) {
                    ForEach(WhisperModelType.allCases) { m in
                        Text("\(m.displayName) (\(m.approxSize))").tag(m)
                    }
                }
                .pickerStyle(.menu)
                Text(transcriber.selectedModel.speedNote)
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Language", selection: $transcriber.transcriptionLanguage) {
                    ForEach(WhisperTranscriptionManager.supportedLanguages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Vocal isolation (reduces instruments)", isOn: $vocalToggle)
                if vocalToggle {
                    Picker("Isolation backend", selection: $separator.mode) {
                        ForEach(VocalSeparationMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(separator.mode.description).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func actionCard(audio: ImportedAudio) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                if transcriber.isTranscribing {
                    ProgressView(value: transcriber.progress) {
                        Text(transcriber.statusMessage)
                    }
                    .progressViewStyle(.linear)
                    Button("Cancel", role: .destructive) { transcriber.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await runTranscription(audio: audio) }
                    } label: {
                        Label("Transcribe Lyrics (Offline)", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    #if !canImport(WhisperKit)
                    Text("Preview engine active — add WhisperKit via SPM for real on-device transcription. See README.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    #endif
                }
            }
        }
    }

    private var resultCard: some View {
        GroupBox("Lyrics (\(lines.count) lines)") {
            VStack(spacing: 8) {
                ForEach(lines.prefix(6)) { line in
                    HStack {
                        Text(line.startTime.compactTimeString)
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .leading)
                        Text(line.text).font(.subheadline)
                        Spacer()
                    }
                }
                if lines.count > 6 {
                    Text("+\(lines.count - 6) more lines…").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Edit") { prepareEditor() }
                        .buttonStyle(.bordered)
                    Button("Save to Library") { saveProject() }
                        .buttonStyle(.borderedProminent)
                    Menu("Export") {
                        ForEach(ExportFormat.allCases) { f in
                            Button(f.displayName) { exportDraft(format: f) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            draftAudio = try AudioImportManager.shared.importAudio(from: url)
            lines = []
        } catch {
            importError = error.localizedDescription
        }
    }

    private func runTranscription(audio: ImportedAudio) async {
        transcribeError = nil
        lines = []
        let settings = ProcessingSettings(
            model: transcriber.selectedModel,
            vocalIsolationEnabled: vocalToggle,
            language: transcriber.transcriptionLanguage
        )
        // Ensure the separator manager reflects the toggle.
        if vocalToggle, separator.mode == .off {
            separator.mode = .localStub
        } else if !vocalToggle {
            separator.mode = .off
        }
        do {
            let result = try await transcriber.transcribe(
                audioURL: audio.fileURL,
                settings: settings,
                separator: separator
            )
            lines = result
            saveProject()
            selection = 2 // jump to Now Playing
        } catch is CancellationError {
            // User cancelled — stay on screen.
        } catch {
            transcribeError = error.localizedDescription
        }
    }

    private func saveProject() {
        guard let audio = draftAudio else { return }
        let project = TranscriptionProject(
            title: title.isEmpty ? audio.fileName : title,
            artist: artist,
            album: album,
            audioFileName: audio.fileName,
            audioStoredFileName: audio.fileURL.lastPathComponent,
            duration: audio.duration,
            lyrics: lines,
            modelUsed: transcriber.selectedModel,
            vocalIsolationEnabled: vocalToggle
        )
        projects.save(project)
        draftProject = project
        // Load into the player so Now Playing highlights immediately.
        player.load(url: audio.fileURL)
    }

    private func prepareEditor() {
        guard let audio = draftAudio else { return }
        editableProject = TranscriptionProject(
            title: title, artist: artist, album: album,
            audioFileName: audio.fileName,
            audioStoredFileName: audio.fileURL.lastPathComponent,
            duration: audio.duration,
            lyrics: lines,
            modelUsed: transcriber.selectedModel,
            vocalIsolationEnabled: vocalToggle
        )
        showingEditor = true
    }

    private func exportDraft(format: ExportFormat) {
        guard let audio = draftAudio else { return }
        let project = TranscriptionProject(
            title: title, artist: artist, album: album,
            audioFileName: audio.fileName,
            audioStoredFileName: audio.fileURL.lastPathComponent,
            duration: audio.duration,
            lyrics: lines,
            modelUsed: transcriber.selectedModel,
            vocalIsolationEnabled: vocalToggle
        )
        if let url = try? ExportManager.export(project: project, format: format) {
            exportURL = url
            showingShare = true
        }
    }
}
