import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView {
                        Label("Sin listas", systemImage: "square.stack")
                    } description: {
                        Text("Crea tu primera lista de reproducción.")
                    } actions: {
                        Button("Nueva lista") { showNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(playlists) { p in
                            NavigationLink {
                                PlaylistDetailView(playlist: p)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    Text("\(p.songIDs.count) canciones")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(playlists[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Listas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("Nueva lista", isPresented: $showNew) {
                TextField("Nombre", text: $newName)
                Button("Crear") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { context.insert(Playlist(name: name)) }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .miniPlayerInset()
        }
    }
}

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Query private var allSongs: [Song]
    @Environment(PlayerManager.self) private var player

    @State private var showRename = false
    @State private var newName = ""

    private var songs: [Song] {
        let map = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { map[$0] }
    }

    var body: some View {
        let current = songs
        List {
            if current.isEmpty {
                Text("Vacía. Mantén pulsada una canción en la Biblioteca y elige “Añadir a lista”.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(current.enumerated()), id: \.element.id) { i, song in
                Button { player.play(current, startAt: i) } label: { SongRow(song: song) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = offsets.map { current[$0].id }
                playlist.songIDs.removeAll { ids.contains($0) }
            }
            .onMove { from, to in
                var s = current
                s.move(fromOffsets: from, toOffset: to)
                playlist.songIDs = s.map(\.id)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Reproducir", systemImage: "play.fill") { player.play(current) }
                    Button("Aleatorio", systemImage: "shuffle") { player.play(current.shuffled()) }
                    Button("Renombrar", systemImage: "pencil") {
                        newName = playlist.name; showRename = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Renombrar lista", isPresented: $showRename) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { playlist.name = n }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .miniPlayerInset()
    }
}
