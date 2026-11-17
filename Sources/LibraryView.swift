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
                    List {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, song in
                            Button { player.play(filtered, startAt: i) } label: {
                                SongRow(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let items = offsets.map { filtered[$0] }
                            for s in items { LibraryManager.delete(s, in: context) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $search, prompt: "Buscar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
                if !songs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { player.play(songs.shuffled()) } label: {
                            Image(systemName: "shuffle")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    importing = true
                    let r = await LibraryManager.importFiles(urls, into: context)
                    importing = false
                    message = "Añadidas: \(r.added)" + (r.skipped > 0 ? " · Omitidas (repetidas o con error): \(r.skipped)" : "")
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
            .miniPlayerInset()
        }
    }
}
