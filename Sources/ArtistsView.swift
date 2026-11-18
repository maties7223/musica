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
                                           description: Text("Añade música desde la pestaña Canciones."))
                } else {
                    List(grouped, id: \.artist) { group in
                        NavigationLink {
                            ArtistDetailView(name: group.artist)
                        } label: {
                            HStack(spacing: 14) {
                                ArtworkView(id: group.songs[0].id,
                                            data: group.songs.first(where: { $0.artworkData != nil })?.artworkData,
                                            size: 58, corner: 29)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.artist).font(.headline).lineLimit(1)
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
    let name: String
    @Query private var songs: [Song]
    @Environment(\.modelContext) private var context
    @Environment(PlayerManager.self) private var player

    init(name: String) {
        self.name = name
        _songs = Query(filter: #Predicate<Song> { $0.artist == name },
                       sort: \Song.title)
    }

    private var albums: [(name: String, songs: [Song])] {
        Dictionary(grouping: songs, by: \.album)
            .map { ($0.key, $0.value.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private var ordered: [Song] { albums.flatMap(\.songs) }

    var body: some View {
        List {
            if let first = songs.first(where: { $0.artworkData != nil }) ?? songs.first {
                VStack(spacing: 16) {
                    ArtworkView(id: first.id, data: first.artworkData, size: 140, corner: 70)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    PlayShuffleButtons(
                        onPlay: { player.play(ordered) },
                        onShuffle: { player.play(ordered.shuffled()) })
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
