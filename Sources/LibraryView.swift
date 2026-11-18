import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerManager.self) private var player
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var search = ""
    @State private var showImporter = false
    @State private var importing = false
    @State private var message: String?

    @State private var editing = false
    @State private var selected = Set<UUID>()
    @State private var confirmDelete = false

    private var filtered: [Song] {
        guard !search.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.artist.localizedCaseInsensitiveContains(search) ||
            $0.album.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("Sin música", systemImage: "music.note.list")
                    } description: {
                        Text("Añade tus archivos MP3 y la app los organizará por artista y álbum.")
                    } actions: {
                        Button("Añadir música") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Canciones")
            .searchable(text: $search, prompt: "Buscar")
            .toolbar {
                if !songs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editing ? "Hecho" : "Seleccionar") {
                            editing.toggle()
                            selected = []
                        }
                    }
                }
                if !editing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showImporter = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: LibraryManager.importTypes,
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    importing = true
                    let r = await LibraryManager.importFiles(urls, into: context)
                    importing = false
                    var parts = ["Añadidas: \(r.added)"]
                    if r.skipped > 0 { parts.append("Repetidas u omitidas: \(r.skipped)") }
                    if r.failed > 0 { parts.append("No se pudieron convertir: \(r.failed)") }
                    message = parts.joined(separator: " · ")
                }
            }
            .overlay {
                if importing {
                    ProgressView("Importando…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Importación", isPresented: Binding(get: { message != nil },
                                                      set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editing { deleteBar }
            }
            .confirmationDialog("¿Eliminar \(selected.count) canciones?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    let items = songs.filter { selected.contains($0.id) }
                    LibraryManager.delete(items, in: context)
                    selected = []
                    editing = false
                }
            } message: {
                Text("Se borrarán de la app y de tus listas.")
            }
            .miniPlayerInset()
        }
    }

    private var list: some View {
        List {
            if search.isEmpty && !editing {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(songs.count) canciones")
                        .font(.subheadline).foregroundStyle(.secondary)
                    PlayShuffleButtons(
                        onPlay: { player.play(filtered) },
                        onShuffle: { player.play(filtered.shuffled()) })
                }
                .listRowSeparator(.hidden)
            }
            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, song in
                Button {
                    if editing {
                        if selected.contains(song.id) { selected.remove(song.id) }
                        else { selected.insert(song.id) }
                    } else {
                        player.play(filtered, startAt: i)
                    }
                } label: {
                    SongRow(song: song, selecting: editing, selected: selected.contains(song.id))
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteOffsets)
        }
        .listStyle(.plain)
    }

    private var deleteBar: some View {
        HStack {
            Button(selected.count == filtered.count ? "Deseleccionar todo" : "Seleccionar todo") {
                if selected.count == filtered.count { selected = [] }
                else { selected = Set(filtered.map(\.id)) }
            }
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Eliminar (\(selected.count))", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        let items = offsets.map { filtered[$0] }
        LibraryManager.delete(items, in: context)
    }
}
