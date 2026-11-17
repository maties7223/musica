import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "music.note.list") }
            ArtistsView()
                .tabItem { Label("Artistas", systemImage: "music.mic") }
            PlaylistsView()
                .tabItem { Label("Listas", systemImage: "square.stack") }
        }
    }
}
