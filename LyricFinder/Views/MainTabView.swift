import SwiftUI

struct MainTabView: View {
    @State private var selection = 0
    /// Shared draft: imported audio waiting to be transcribed.
    @State var draftAudio: ImportedAudio?
    @State var draftProject: TranscriptionProject?

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(selection: $selection, draftAudio: $draftAudio, draftProject: $draftProject)
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(0)
            TranscribeView(selection: $selection, draftAudio: $draftAudio, draftProject: $draftProject)
                .tabItem { Label("Transcribe", systemImage: "waveform.and.mic") }
                .tag(1)
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
    }
}
