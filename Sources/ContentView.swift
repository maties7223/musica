import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerManager.self) private var player

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Canciones", systemImage: "music.note") }
            ArtistsView()
                .tabItem { Label("Artistas", systemImage: "music.mic") }
            PlaylistsView()
                .tabItem { Label("Listas", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .modifier(ToastOverlay())
        .task {
            // Recupera lo último que sonaba (en pausa, en el mismo minuto).
            let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
            player.restore(from: songs)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.saveTime() }
        }
    }
}
