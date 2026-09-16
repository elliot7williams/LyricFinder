import SwiftUI

@main
struct LyricFinderApp: App {
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var projects = ProjectManager()
    @StateObject private var transcriber = WhisperTranscriptionManager()
    @StateObject private var vocalSeparator = VocalSeparationManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(player)
                .environmentObject(projects)
                .environmentObject(transcriber)
                .environmentObject(vocalSeparator)
        }
    }
}
