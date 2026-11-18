import SwiftUI
import SwiftData

struct ArtistGroup: Identifiable {
    let key: String
    let name: String
    let songs: [Song]
    var id: String { key }
}

struct ArtistsView: View {
    @Query(sort: \Song.title) private var songs: [Song]

    /// Agrupa por el primer artista (de la etiqueta o, si no hay, del título).
    private var grouped: [ArtistGroup] {
        Dictionary(grouping: songs, by: \.artistKey)
            .map { ArtistGroup(key: $0.key, name: $0.value[0].mainArtist, songs: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("Sin artistas", systemImage: "music.mic",
                                           description: Text("Añade música desde la pestaña Canciones."))
                } else {
                    List(grouped) { group in
                        NavigationLink {
                            ArtistDetailView(key: group.key, name: group.name)
                        } label: {
                            HStack(spacing: 14) {
                                ArtworkView(id: group.songs[0].id,
                                            data: group.songs.first(where: { $0.displayArtwork != nil })?.displayArtwork,
                                            size: 58, corner: 29)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(.headline).lineLimit(1)
                                    Text("\(group.songs.count) canciones")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Artistas")
            .miniPlayerInset()
        }
    }
}

struct ArtistDetailView: View {
    let key: String
    let name: String
    @Query(sort: \Song.title) private var allSongs: [Song]
    @Environment(\.modelContext) private var context
    @Environment(PlayerManager.self) private var player

    private func makeAlbums(_ songs: [Song]) -> [(name: String, songs: [Song])] {
        Dictionary(grouping: songs, by: \.album)
            .map { ($0.key, $0.value.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        let mine = allSongs.filter { $0.artistKey == key }
        let albums = makeAlbums(mine)
        let ordered = albums.flatMap(\.songs)

        List {
            if let first = mine.first(where: { $0.displayArtwork != nil }) ?? mine.first {
                VStack(spacing: 16) {
                    ArtworkView(id: first.id, data: first.displayArtwork, size: 140, corner: 70)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    PlayShuffleButtons(
                        onPlay: { player.playInOrder(ordered) },
                        onShuffle: { player.playShuffled(ordered) })
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            }
            ForEach(albums, id: \.name) { album in
                Section(album.name) {
                    ForEach(Array(album.songs.enumerated()), id: \.element.id) { i, song in
                        Button { player.play(album.songs, startAt: i) } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .favoriteSwipe(song)
                    }
                    .onDelete { offsets in
                        LibraryManager.delete(offsets.map { album.songs[$0] }, in: context)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerInset()
    }
}
