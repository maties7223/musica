import SwiftUI
import SwiftData

struct ArtistsView: View {
    @Query(sort: \Song.title) private var songs: [Song]

    private var grouped: [(artist: String, songs: [Song])] {
        Dictionary(grouping: songs, by: \.artist)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("Sin artistas", systemImage: "music.mic",
                                           description: Text("Añade música desde la pestaña Biblioteca."))
                } else {
                    List(grouped, id: \.artist) { group in
                        NavigationLink {
                            ArtistDetailView(name: group.artist, songs: group.songs)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(id: group.songs[0].id, data: group.songs[0].artworkData, size: 48)
                                VStack(alignment: .leading) {
                                    Text(group.artist)
                                    Text("\(group.songs.count) canciones")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Artistas")
            .miniPlayerInset()
        }
    }
}

struct ArtistDetailView: View {
    let name: String
    let songs: [Song]
    @Environment(PlayerManager.self) private var player

    private var albums: [(name: String, songs: [Song])] {
        Dictionary(grouping: songs, by: \.album)
            .map { ($0.key, $0.value.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(albums, id: \.name) { album in
                Section(album.name) {
                    ForEach(Array(album.songs.enumerated()), id: \.element.id) { i, song in
                        Button { player.play(album.songs, startAt: i) } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(name)
        .miniPlayerInset()
    }
}
