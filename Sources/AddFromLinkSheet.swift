import SwiftUI
import SwiftData
import UIKit

/// Pega uno o varios enlaces de YouTube, Spotify o SoundCloud y añade el audio.
struct AddFromLinkSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoPasteLink") private var autoPaste = true
    @AppStorage("autoPlayAfterDownload") private var autoPlay = false

    private let prefill: String?

    @State private var input = ""
    @State private var working = false
    @State private var phase: DownloadPhase = .preparing
    @State private var progress: Double = 0
    @State private var current = 0
    @State private var total = 0
    @State private var errorText: String?
    @State private var added: [Song] = []
    @State private var skipped = 0
    @State private var failed = 0
    @State private var job: Task<Void, Never>?

    init(prefill: String? = nil) {
        self.prefill = prefill
    }

    private var links: [String] { LinkService.links(in: input) }
    private var hasInstance: Bool { !InstancePool.ordered().isEmpty }
    private var canStart: Bool { !working && hasInstance && !links.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pega uno o varios enlaces…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(working)
                    Button {
                        if let text = UIPasteboard.general.string { input = text }
                    } label: {
                        Label("Pegar del portapapeles", systemImage: "doc.on.clipboard")
                    }
                    .disabled(working)
                } header: {
                    Text("Enlaces")
                } footer: {
                    Text("Vale YouTube, YouTube Music, Spotify y SoundCloud. Puedes pegar varias canciones a la vez, una por línea. En Spotify se busca la canción en YouTube para obtener el audio.")
                }

                if !links.isEmpty {
                    Section("Detectado") {
                        ForEach(Array(links.prefix(5).enumerated()), id: \.offset) { _, link in
                            let service = LinkService.detect(link)
                            Label {
                                Text(link).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: service.icon).foregroundStyle(service.tint)
                            }
                        }
                        if links.count > 5 {
                            Text("y \(links.count - 5) más").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !hasInstance {
                    Section {
                        Label("No hay instancias de Cobalt. Configúralas en Ajustes.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if working {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(total > 1 ? "\(current) de \(total) · \(phase.label)" : phase.label)
                                Spacer()
                                Text("\(Int(progress * 100)) %")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: progress)
                        }
                        Button("Cancelar", role: .cancel) { job?.cancel() }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }

                if !working && !added.isEmpty {
                    Section {
                        Button { play(added) } label: {
                            Label("Reproducir ahora", systemImage: "play.fill")
                        }
                        Button { enqueue(added) } label: {
                            Label("Añadir a la cola", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                    } header: {
                        Text("Añadidas \(added.count)")
                    }
                }

                if !working {
                    Section {
                        Button {
                            start()
                        } label: {
                            Label("Descargar y añadir", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(!canStart)
                    }
                }
            }
            .navigationTitle("Añadir desde enlace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added.isEmpty ? "Cerrar" : "Hecho") { dismiss() }
                        .disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        if let prefill, input.trimmed.isEmpty {
            input = prefill
            return
        }
        guard autoPaste, input.trimmed.isEmpty else { return }
        if let text = UIPasteboard.general.string,
           !LinkService.links(in: text).isEmpty {
            input = text
        }
    }

    @MainActor
    private func start() {
        let list = links
        guard !list.isEmpty else { return }
        errorText = nil
        added = []
        skipped = 0
        failed = 0
        working = true
        progress = 0
        total = list.count
        current = 1

        job = Task {
            var firstError: String?
            for (index, link) in list.enumerated() {
                if Task.isCancelled { break }
                current = index + 1
                progress = 0
                do {
                    let result = try await CobaltClient.addToLibrary(
                        link: link,
                        context: context,
                        onPhase: { phase = $0 },
                        onProgress: { progress = $0 })
                    added.append(contentsOf: result.songs)
                    skipped += result.skipped
                    failed += result.failed
                } catch is CancellationError {
                    break
                } catch let error as CobaltError {
                    if case .cancelled = error { break }
                    failed += 1
                    firstError = firstError ?? error.localizedDescription
                } catch {
                    failed += 1
                    firstError = firstError ?? error.localizedDescription
                }
            }

            working = false
            progress = 0
            var parts: [String] = []
            if !added.isEmpty { parts.append("Añadidas: \(added.count)") }
            if skipped > 0 { parts.append("Ya estaban: \(skipped)") }
            if failed > 0 { parts.append("Con error: \(failed)") }
            errorText = parts.isEmpty ? "No se pudo descargar nada." : nil
            if !parts.isEmpty {
                Toast.shared.show(parts.joined(separator: " · "),
                                  icon: added.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            }
            if added.isEmpty, let firstError { errorText = firstError }
            if !added.isEmpty && autoPlay { play(added) }
        }
    }

    private func play(_ songs: [Song]) {
        PlayerManager.shared.play(songs)
        dismiss()
    }

    private func enqueue(_ songs: [Song]) {
        for song in songs { PlayerManager.shared.addToQueue(song) }
        dismiss()
    }
}
