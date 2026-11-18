import SwiftUI
import SwiftData

// MARK: - Caché de carátulas

enum ImageCache {
    static let cache = NSCache<NSString, UIImage>()

    static func image(id: UUID, data: Data?) -> UIImage? {
        let key = id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data, let img = UIImage(data: data) else { return nil }
        let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? img
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}

// MARK: - Carátula (con degradado de color si no hay imagen)

struct ArtworkView: View {
    let id: UUID
    let data: Data?
    var size: CGFloat = 48
    var corner: CGFloat? = nil

    private var placeholder: some View {
        let a = Double(id.uuid.0) / 255.0
        let b = Double(id.uuid.1) / 255.0
        return ZStack {
            LinearGradient(
                colors: [
                    Color(hue: a, saturation: 0.55, brightness: 0.90),
                    Color(hue: (a + 0.10 + b * 0.1).truncatingRemainder(dividingBy: 1),
                          saturation: 0.75, brightness: 0.55)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    var body: some View {
        Group {
            if let image = ImageCache.image(id: id, data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner ?? size * 0.14, style: .continuous))
    }
}

// MARK: - Portada de lista (mosaico)

struct PlaylistCover: View {
    let songs: [Song]
    var size: CGFloat = 56

    var body: some View {
        let arts = Array(songs.filter { $0.artworkData != nil }.prefix(4))
        ZStack {
            Theme.gradient
            if arts.count >= 4 {
                let h = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) { tile(arts[0], h); tile(arts[1], h) }
                    HStack(spacing: 0) { tile(arts[2], h); tile(arts[3], h) }
                }
            } else if let first = arts.first {
                ArtworkView(id: first.id, data: first.artworkData, size: size, corner: 0)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private func tile(_ s: Song, _ h: CGFloat) -> some View {
        ArtworkView(id: s.id, data: s.artworkData, size: h, corner: 0)
    }
}

// MARK: - Botones Reproducir / Aleatorio

struct PlayShuffleButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Reproducir", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onShuffle) {
                Label("Aleatorio", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .fontWeight(.semibold)
    }
}

// MARK: - Fila de canción

struct SongRow: View {
    let song: Song
    var selecting = false
    var selected = false

    @Environment(\.modelContext) private var context
    @Environment(PlayerManager.self) private var player
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @State private var confirmDelete = false

    private var isCurrent: Bool { player.currentTrack?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
            }
            ArtworkView(id: song.id, data: song.artworkData, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Theme.accent : Color.primary)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
            Text(song.duration.mmss)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Añadir a lista", systemImage: "text.badge.plus") {
                if playlists.isEmpty { Text("Primero crea una lista") }
                ForEach(playlists) { p in
                    Button(p.name) {
                        if !p.songIDs.contains(song.id) { p.songIDs.append(song.id) }
                    }
                }
            }
            Button("Eliminar de la biblioteca", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        }
        .confirmationDialog("¿Eliminar esta canción?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                LibraryManager.delete([song], in: context)
            }
        } message: {
            Text("Se borrará de la app y de tus listas.")
        }
    }
}

// MARK: - Mini reproductor flotante

struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerManager.self) private var player
    @State private var showFull = false

    private var progress: Double {
        player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        ArtworkView(id: track.id, data: track.artwork, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1).font(.subheadline.weight(.semibold))
                            Text(track.artist).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2).frame(width: 36)
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.title2).frame(width: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        GeometryReader { g in
                            Capsule().fill(Theme.accent)
                                .frame(width: max(0, g.size.width * progress), height: 2.5)
                        }
                        .frame(height: 2.5)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
                }
            }
            .sheet(isPresented: $showFull) {
                PlayerView().environment(player)
            }
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}
