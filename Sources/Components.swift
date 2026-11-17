import SwiftUI
import SwiftData

// MARK: - Carátula

enum ImageCache {
    static let cache = NSCache<NSString, UIImage>()
}

struct ArtworkView: View {
    let id: UUID
    let data: Data?
    var size: CGFloat = 48

    private var image: UIImage? {
        let key = id.uuidString as NSString
        if let cached = ImageCache.cache.object(forKey: key) { return cached }
        guard let data, let img = UIImage(data: data) else { return nil }
        let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? img
        ImageCache.cache.setObject(thumb, forKey: key)
        return thumb
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
    }
}

// MARK: - Fila de canción

struct SongRow: View {
    let song: Song
    @Environment(PlayerManager.self) private var player
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    private var isCurrent: Bool { player.currentTrack?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(id: song.id, data: song.artworkData, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(song.duration.mmss)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Añadir a lista", systemImage: "text.badge.plus") {
                if playlists.isEmpty {
                    Text("Primero crea una lista")
                }
                ForEach(playlists) { p in
                    Button(p.name) {
                        if !p.songIDs.contains(song.id) { p.songIDs.append(song.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Mini reproductor

struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerManager.self) private var player
    @State private var showFull = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        ArtworkView(id: track.id, data: track.artwork, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1).font(.subheadline.bold())
                            Text(track.artist).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.title2)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
                }
            }
            .sheet(isPresented: $showFull) { PlayerView() }
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}
