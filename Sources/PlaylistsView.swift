import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @Query private var allSongs: [Song]

    @State private var showNew = false

    private func songs(in playlist: Playlist) -> [Song] {
        let map = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { map[$0] }
    }

    private var favoriteCount: Int { allSongs.filter { $0.isFavorite }.count }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    FavoritesView()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Theme.gradient
                            Image(systemName: "heart.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 58 * 0.14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favoritos").font(.headline)
                            Text("\(favoriteCount) canciones")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if playlists.isEmpty {
                    VStack(spacing: 10) {
                        Text("Aún no tienes listas de reproducción.")
                            .foregroundStyle(.secondary)
                        Button("Nueva lista") { showNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowSeparator(.hidden)
                }

                ForEach(playlists) { p in
                    NavigationLink {
                        PlaylistDetailView(playlist: p)
                    } label: {
                        let inList = songs(in: p)
                        HStack(spacing: 14) {
                            PlaylistCover(playlist: p, songs: inList, size: 58)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline).lineLimit(1)
                                Text("\(inList.count) canciones")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(playlists[i]) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Listas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                PlaylistPickerSheet(playlist: nil)
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
    @State private var showPicker = false
    @State private var showPhotos = false
    @State private var showFiles = false

    private var songs: [Song] {
        let map = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { map[$0] }
    }

    private func remove(_ song: Song) {
        playlist.songIDs.removeAll { $0 == song.id }
        Toast.shared.show("Quitada de «\(playlist.name)»", icon: "minus.circle.fill")
    }

    var body: some View {
        let current = songs
        List {
            VStack(spacing: 16) {
                PlaylistCover(playlist: playlist, songs: current, size: 160)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                if current.isEmpty {
                    Button { showPicker = true } label: {
                        Label("Añadir canciones", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .fontWeight(.semibold)
                } else {
                    PlayShuffleButtons(
                        onPlay: { player.playInOrder(current) },
                        onShuffle: { player.playShuffled(current) })
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)

            if current.isEmpty {
                Text("Esta lista está vacía.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(current.enumerated()), id: \.element.id) { i, song in
                Button { player.play(current, startAt: i) } label: {
                    SongRow(song: song, onRemoveFromPlaylist: { remove(song) })
                }
                .buttonStyle(.plain)
                .favoriteSwipe(song)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { remove(song) } label: {
                        Label("Quitar", systemImage: "minus.circle")
                    }
                }
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
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPicker = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Renombrar", systemImage: "pencil") {
                        newName = playlist.name; showRename = true
                    }
                    Menu("Imagen de la lista", systemImage: "photo") {
                        Button("Elegir de Fotos", systemImage: "photo.on.rectangle") { showPhotos = true }
                        Button("Elegir de Archivos", systemImage: "folder") { showFiles = true }
                        if playlist.coverData != nil {
                            Button("Quitar imagen", systemImage: "trash", role: .destructive) {
                                playlist.coverData = nil
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .imageChooser(photos: $showPhotos, files: $showFiles) { data in
            playlist.coverData = data
        }
        .sheet(isPresented: $showPicker) {
            PlaylistPickerSheet(playlist: playlist)
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
