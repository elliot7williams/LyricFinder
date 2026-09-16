import SwiftUI

/// Large karaoke lyrics view with smooth auto-scroll.
struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var projects: ProjectManager

    @State private var activeProject: TranscriptionProject?
    @State private var autoScroll = true

    private var lines: [LyricLine] { activeProject?.lyrics ?? [] }

    private var activeIndex: Int? {
        let t = player.currentTime
        let ls = lines
        return LyricsSyncManager.currentLineIndex(at: t, in: ls)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { activeProject?.id },
            set: { newID in
                guard let newID else { return }
                if let p = projects.project(id: newID) {
                    activeProject = p
                    player.load(url: projects.audioURL(for: p))
                }
            }
        )
    }

    private var scrubBinding: Binding<Double> {
        Binding<Double>(
            get: { player.currentTime },
            set: { player.seek(to: $0) }
        )
    }

    private var sliderRange: ClosedRange<Double> {
        0...max(player.duration, 0.01)
    }

    var body: some View {
        NavigationStack {
            VStack {
                if lines.isEmpty {
                    emptyView
                } else {
                    projectPicker
                    lyricsScroll
                    miniControls
                }
            }
            .navigationTitle("Now Playing")
            .toolbar {
                if !lines.isEmpty {
                    Toggle(isOn: $autoScroll) {
                        Label("Follow", systemImage: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }
                }
            }
            .onAppear { pickLatest() }
            .onChange(of: projects.projects) { _, _ in pickLatest(keepSelection: true) }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "Nothing playing",
            systemImage: "play.circle",
            description: Text("Transcribe a song, or open a project from the Library.")
        )
    }

    private var projectPicker: some View {
        Picker("Song", selection: selectionBinding) {
            ForEach(projects.projects) { p in
                Text(p.title).tag(UUID?(p.id))
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
    }

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(lines.indices, id: \.self) { i in
                        LyricRowView(
                            line: lines[i],
                            isActive: i == activeIndex,
                            currentTime: player.currentTime,
                            onTap: { player.seek(to: lines[i].startTime + 0.01) },
                            large: true
                        )
                        .id(i)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: activeIndex) { _, new in
                guard autoScroll, let new else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private var miniControls: some View {
        VStack(spacing: 8) {
            Slider(value: scrubBinding, in: sliderRange)
                .padding(.horizontal)
            HStack {
                Text(player.currentTime.compactTimeString)
                    .monospacedDigit()
                Spacer()
                Text(activeProject?.title ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(player.duration.compactTimeString)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal)
            HStack(spacing: 32) {
                Button { player.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.title2)
                }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                Button { player.skip(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.title2)
                }
            }
            .foregroundStyle(.tint)
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func pickLatest(keepSelection: Bool = false) {
        if keepSelection, let current = activeProject,
           projects.project(id: current.id) != nil { return }
        guard let latest = projects.projects.first else { return }
        // Don't stomp an actively playing session on first appear if the
        // player already has audio loaded from the Transcribe tab.
        if activeProject == nil && player.currentURL != nil { return }
        activeProject = latest
    }
}
