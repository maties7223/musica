import SwiftUI

struct PlayerView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)
            Spacer()

            if let t = player.currentTrack {
                ArtworkView(id: t.id, data: t.artwork, size: 300)
                    .shadow(radius: 12)

                VStack(spacing: 4) {
                    Text(t.title).font(.title2.bold()).lineLimit(2)
                    Text(t.artist).font(.title3).foregroundStyle(.secondary)
                    Text(t.album).font(.subheadline).foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                VStack(spacing: 4) {
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
                    HStack {
                        Text((scrubbing ? scrubValue : player.currentTime).mmss)
                        Spacer()
                        Text(player.duration.mmss)
                    }
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)

                HStack(spacing: 48) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.largeTitle)
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.largeTitle)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Nada en reproducción").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .presentationDragIndicator(.hidden)
    }
}
