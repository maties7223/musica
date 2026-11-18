import SwiftUI

struct PlayerView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        GeometryReader { geo in
            let side = max(min(geo.size.width - 64, 360), 120)

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

                    Spacer(minLength: 24)

                    VStack(spacing: 4) {
                        Text(t.title).font(.title2.bold()).lineLimit(2)
                        Text(t.artist).font(.title3).opacity(0.8).lineLimit(1)
                        Text(t.album).font(.subheadline).opacity(0.55).lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 20)

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

                    Spacer(minLength: 16)

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
                } else {
                    Text("Nada en reproducción").opacity(0.7)
                }

                Spacer(minLength: 32)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(.white)
        .background { backdrop.ignoresSafeArea() }
        .preferredColorScheme(.dark)
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
