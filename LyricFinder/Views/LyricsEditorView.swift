import SwiftUI

/// Manual correction UI: edit text, replay the section, keep timestamps.
struct LyricsEditorView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Binding var project: TranscriptionProject
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftTexts: [UUID: String] = [:]

    var body: some View {
        List {
            Section("Tip") {
                Text("Tap a line's text to correct it. Timestamps are preserved. Use Replay to hear just that section.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lines") {
                ForEach($project.lyrics) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Lyric text", text: Binding(
                            get: { draftTexts[line.id] ?? line.text },
                            set: { draftTexts[line.id] = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commit(lineID: line.id) }
                        HStack {
                            Text("\(line.startTime.preciseTimeString) → \(line.endTime.preciseTimeString)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                commitAll()
                                player.seek(to: line.startTime)
                                player.play()
                                // Auto-pause at end of the line.
                                DispatchQueue.main.asyncAfter(deadline: .now() + line.duration + 0.3) {
                                    Task { @MainActor in
                                        // Only pause if we haven't moved far past the line.
                                        if abs(player.currentTime - line.endTime) < 1.0 {
                                            player.pause()
                                        }
                                    }
                                }
                            } label: {
                                Label("Replay section", systemImage: "play.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Edit Lyrics")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    commitAll()
                    onSave()
                    dismiss()
                }
            }
        }
        .onAppear {
            // Ensure the edited song is loaded for replay.
            let url = AudioImportManager.shared.urlForStoredFile(named: project.audioStoredFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                if player.currentURL != url {
                    player.load(url: url)
                }
            }
        }
    }

    private func commit(lineID: UUID) {
        if let i = project.lyrics.firstIndex(where: { $0.id == lineID }),
           let text = draftTexts[lineID] {
            project.lyrics[i].text = text
        }
    }

    private func commitAll() {
        for (id, text) in draftTexts {
            if let i = project.lyrics.firstIndex(where: { $0.id == id }) {
                project.lyrics[i].text = text
            }
        }
    }
}
