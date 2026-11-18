import SwiftUI
import SwiftData

/// Hoja para crear una lista (playlist == nil) o añadir canciones a una existente.
struct PlaylistPickerSheet: View {
    let playlist: Playlist?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var name = ""
    @State private var picked: [UUID] = []
    @State private var search = ""

    private var existing: Set<UUID> { Set(playlist?.songIDs ?? []) }

    private var filtered: [Song] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.displayArtist.localizedCaseInsensitiveContains(q) ||
            $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    private var canConfirm: Bool {
        if playlist == nil {
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !picked.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if playlist == nil {
                    Section("Nombre") {
                        TextField("Nombre de la lista", text: $name)
                    }
                }
                Section {
                    if songs.isEmpty {
                        Text("Aún no hay canciones en la biblioteca.")
                            .foregroundStyle(.secondary)
                    } else if filtered.isEmpty {
                        Text("Sin resultados.").foregroundStyle(.secondary)
                    }
                    ForEach(filtered, id: \.id) { song in
                        row(song)
                    }
                } header: {
                    Text(picked.isEmpty ? "Canciones" : "Canciones · \(picked.count) seleccionadas")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Buscar canciones")
            .navigationTitle(playlist == nil ? "Nueva lista" : "Añadir canciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(playlist == nil ? "Crear" : "Añadir") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(!canConfirm)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ song: Song) -> some View {
        let already = existing.contains(song.id)
        let on = picked.contains(song.id)
        Button {
            guard !already else { return }
            if let i = picked.firstIndex(of: song.id) {
                picked.remove(at: i)
            } else {
                picked.append(song.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: (on || already) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
                ArtworkView(id: song.id, data: song.displayArtwork, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).lineLimit(1)
                    Text(already ? "Ya está en la lista" : song.displayArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(already ? 0.5 : 1)
    }

    private func confirm() {
        if let playlist {
            let new = picked.filter { !existing.contains($0) }
            playlist.songIDs.append(contentsOf: new)
            let text = new.count == 1
                ? "1 canción añadida a «\(playlist.name)»"
                : "\(new.count) canciones añadidas a «\(playlist.name)»"
            Toast.shared.show(text)
        } else {
            let p = Playlist(name: name.trimmingCharacters(in: .whitespaces))
            p.songIDs = picked
            context.insert(p)
            try? context.save()
            Toast.shared.show("Lista «\(p.name)» creada")
        }
        dismiss()
    }
}
