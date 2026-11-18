import SwiftUI

struct ContentView: View {
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
    }
}
