import SwiftUI
import SwiftData
import UIKit

/// Hoja para pegar un enlace y descargar su audio con Cobalt.
struct AddFromLinkSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cobaltURL") private var instance = ""

    @State private var link = ""
    @State private var working = false
    @State private var errorText: String?

    private var hasInstance: Bool {
        !instance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canStart: Bool {
        !working && hasInstance && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        if let text = UIPasteboard.general.string { link = text }
                    } label: {
                        Label("Pegar del portapapeles", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Enlace")
                } footer: {
                    Text("Se descarga el audio en MP3 y se añade a tu biblioteca. Úsalo solo con contenido que tengas derecho a descargar.")
                }

                if !hasInstance {
                    Section {
                        Label("Aún no has configurado tu instancia de Cobalt. Hazlo en Ajustes.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            Text(working ? "Descargando…" : "Descargar audio")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(!canStart)
                }
            }
            .navigationTitle("Añadir desde enlace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    @MainActor
    private func start() async {
        errorText = nil
        working = true
        defer { working = false }
        do {
            let result = try await CobaltClient.addToLibrary(link: link, context: context)
            if result.added > 0 {
                Toast.shared.show("Canción añadida a la biblioteca")
                dismiss()
            } else if result.skipped > 0 {
                errorText = "Esa canción ya estaba en tu biblioteca."
            } else {
                errorText = "No se pudo importar el archivo descargado."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
