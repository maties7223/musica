import SwiftUI

/// Cola de reproducción: lo que suena ahora y lo que viene después.
struct QueueView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentTrack {
                    Section("Sonando ahora") {
                        row(current, isCurrent: true)
                    }
                }
                Section {
                    if player.upcoming.isEmpty {
                        Text("No hay más canciones en la cola.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(player.upcoming, id: \.id) { track in
                        Button { player.jump(to: track.id) } label: {
                            row(track, isCurrent: false)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { player.removeUpcoming(at: $0) }
                    .onMove { player.moveUpcoming(from: $0, to: $1) }
                } header: {
                    Text("A continuación")
                }
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }

    private func row(_ t: Track, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkView(id: t.id, data: t.artwork, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Theme.accent : Color.primary)
                Text(t.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(t.duration.mmss)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
