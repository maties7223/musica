import SwiftUI
import SwiftData

struct PlayerView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Query private var songs: [Song]

    @State private var scrubbing = false
    @State private var scrubValue = 0.0
    @State private var showQueue = false

    private var currentSong: Song? {
        guard let id = player.currentTrack?.id else { return nil }
        return songs.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(min(geo.size.width - 64, geo.size.height * 0.40, 360), 120)

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 8)

                if let t = player.currentTrack {
                    ArtworkView(id: t.id, data: t.artwork, size: side, corner: 24)
                        .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
                        .scaleEffect(player.isPlaying ? 1 : 0.88)
                        .animation(.spring(duration: 0.45), value: player.isPlaying)

                    Spacer(minLength: 20)

                    VStack(spacing: 4) {
                        Text(t.title).font(.title2.bold()).lineLimit(2)
                        Text(t.artist).font(.title3).opacity(0.8).lineLimit(1)
                        Text(t.album).font(.subheadline).opacity(0.55).lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 16)

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { scrubbing ? scrubValue : player.currentTime },
                                set: { scrubValue = $0 }),
                            in: 0...max(player.duration, 1)
                        ) { editing in
                            if editing { scrubValue = player.currentTime }
                            scrubbing = editing
                            if !editing { player.seek(to: scrubValue) }
                        }
                        .tint(.white)
                        HStack {
                            Text((scrubbing ? scrubValue : player.currentTime).mmss)
                            Spacer()
                            Text(player.duration.mmss)
                        }
                        .font(.caption).monospacedDigit().opacity(0.7)
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 12)

                    HStack(spacing: 44) {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 34))
                        }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 84))
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 34))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 12)

                    optionsRow
                } else {
                    Text("Nada en reproducción").opacity(0.7)
                }

                Spacer(minLength: 20)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(.white)
        .background { backdrop.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView().environment(player)
        }
    }

    /// Aleatorio · Favorito · Cola · Repetir
    private var optionsRow: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.isShuffled ? Theme.accent : Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            if let song = currentSong {
                Button { FavoriteActions.toggle(song) } label: {
                    Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(song.isFavorite ? Theme.accent : Color.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
            } else {
                Image(systemName: "heart")
                    .foregroundStyle(Color.white.opacity(0.3))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode.icon)
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.6) : Theme.accent)
                    .frame(width: 44, height: 44)
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal, 36)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let t = player.currentTrack, let img = ImageCache.image(id: t.id, data: t.artwork) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 70)
                .overlay(Color.black.opacity(0.45))
                .clipped()
        } else {
            Theme.gradient.overlay(Color.black.opacity(0.35))
        }
    }
}
