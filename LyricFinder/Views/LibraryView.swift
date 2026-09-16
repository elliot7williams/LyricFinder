import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var projects: ProjectManager
    @EnvironmentObject private var player: AudioPlayerManager
    @Binding var selection: Int
    @Binding var draftAudio: ImportedAudio?
    @Binding var draftProject: TranscriptionProject?

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var exportURL: URL?
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            Group {
                if projects.projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(projects.projects) { project in
                            NavigationLink {
                                ProjectDetailView(project: project, selection: $selection)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title).font(.headline)
                                    if !project.artist.isEmpty {
                                        Text(project.artist).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(project.duration.compactTimeString)
                                        Text("·")
                                        Text("\(project.lyrics.count) lines")
                                        Text("·")
                                        Text(project.modelUsed.displayName)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { projects.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImporter = true } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: AudioImportManager.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No projects yet",
            systemImage: "music.note.list",
            description: Text("Import an MP3, M4A, or WAV file to transcribe your first song. Everything runs offline.")
        )
        .overlay(alignment: .bottom) {
            Button { showingImporter = true } label: {
                Label("Import Audio", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let audio = try AudioImportManager.shared.importAudio(from: url)
            draftAudio = audio
            draftProject = nil
            selection = 1 // jump to Transcribe tab
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - Project detail

struct ProjectDetailView: View {
    @EnvironmentObject private var projects: ProjectManager
    @EnvironmentObject private var player: AudioPlayerManager
    var project: TranscriptionProject
    @Binding var selection: Int

    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var showingEditor = false
    @State private var liveProject: TranscriptionProject

    init(project: TranscriptionProject, selection: Binding<Int>) {
        self.project = project
        self._selection = selection
        self._liveProject = State(initialValue: project)
    }

    var body: some View {
        List {
            Section("Song") {
                LabeledContent("Title", value: liveProject.title)
                if !liveProject.artist.isEmpty { LabeledContent("Artist", value: liveProject.artist) }
                if !liveProject.album.isEmpty { LabeledContent("Album", value: liveProject.album) }
                LabeledContent("Duration", value: liveProject.duration.compactTimeString)
                LabeledContent("Model", value: liveProject.modelUsed.displayName)
            }
            Section("Playback") {
                Button {
                    player.load(url: projects.audioURL(for: liveProject), autoplay: true)
                    selection = 2
                } label: {
                    Label("Play with lyrics", systemImage: "play.fill")
                }
            }
            Section("Lyrics (\(liveProject.lyrics.count) lines)") {
                ForEach(liveProject.lyrics) { line in
                    VStack(alignment: .leading) {
                        Text(line.text)
                        Text("\(line.startTime.preciseTimeString) → \(line.endTime.preciseTimeString)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Section("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        if let url = try? ExportManager.export(project: liveProject, format: format) {
                            exportURL = url
                            showingShare = true
                        }
                    }
                }
            }
        }
        .navigationTitle(liveProject.title)
        .toolbar {
            Button("Edit") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                LyricsEditorView(project: $liveProject) {
                    projects.save(liveProject)
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            if let exportURL {
                ShareSheet(url: exportURL)
            }
        }
        .onChange(of: liveProject) { _, new in projects.save(new) }
    }
}

/// UIKit share sheet wrapper for exported files.
/// Anchors the iPad popover to the presenting view so sharing never crashes.
struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = vc.popoverPresentationController,
           let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let rootView = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.view {
            popover.sourceView = rootView
            popover.sourceRect = CGRect(x: rootView.bounds.midX, y: rootView.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
