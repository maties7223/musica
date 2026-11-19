import SwiftUI
import SwiftData

@main
struct MusicaApp: App {
    @State private var player = PlayerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
        }
        .modelContainer(for: [Song.self, Playlist.self])
    }
}
