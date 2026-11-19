import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerManager.self) private var player

    @State private var pendingLink: String?
    @State private var showLink = false

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
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "musica" else { return }
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let link = comps?.queryItems?.first(where: { $0.name == "url" })?.value {
                pendingLink = link
            } else if let path = comps?.path.trimmed, !path.isEmpty {
                pendingLink = String(path.drop { $0 == "/" }).removingPercentEncoding
            }
            showLink = pendingLink != nil
        }
        .sheet(isPresented: $showLink, onDismiss: { pendingLink = nil }) {
            AddFromLinkSheet(prefill: pendingLink)
        }
    }
}
