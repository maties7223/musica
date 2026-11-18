import SwiftUI
import SwiftData

/// Lista automática con las canciones marcadas como favoritas.
struct FavoritesView: View {
    @Query private var allSongs: [Song]
    @Environment(PlayerManager.self) private var player

    private var favorites: [Song] {
        allSongs
            .filter { $0.isFavorite }
            .sorted { ($0.favoritedAt ?? Date.distantPast) > ($1.favoritedAt ?? Date.distantPast) }
    }

    var body: some View {
        let favs = favorites
        Group {
            if favs.isEmpty {
                ContentUnavailableView(
                    "Sin favoritos", systemImage: "heart",
                    description: Text("Desliza una canción hacia la derecha, o mantenla pulsada y elige “Añadir a favoritos”."))
            } else {
                List {
                    PlayShuffleButtons(
                        onPlay: { player.playInOrder(favs) },
                        onShuffle: { player.playShuffled(favs) })
                        .listRowSeparator(.hidden)

                    ForEach(Array(favs.enumerated()), id: \.element.id) { i, song in
                        Button { player.play(favs, startAt: i) } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .favoriteSwipe(song)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerInset()
    }
}
