import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @State private var recalculating = false
    @AppStorage("cobaltURL") private var cobaltURL = ""
    @AppStorage("cobaltKey") private var cobaltKey = ""
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        ForEach(ThemeChoice.allCases) { choice in
                            Button { ThemeStore.shared.select(choice) } label: {
                                swatch(choice)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Color de la interfaz")
                } footer: {
                    Text("Cambia el color de botones, pestañas y portadas sin imagen.")
                }

                Section {
                    TextField("https://tu-instancia.com", text: $cobaltURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Clave de API (opcional)", text: $cobaltKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button { Task { await testCobalt() } } label: {
                        HStack {
                            Text("Probar conexión")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || cobaltURL.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Descargas con Cobalt")
                } footer: {
                    Text("Cobalt necesita una instancia propia o de alguien que te dé acceso (con su clave de API); la pública api.cobalt.tools no está pensada para usarse desde otras apps. La dirección debe empezar por https://. Después, en Canciones → + → Desde un enlace.")
                }

                Section {
                    Button { Task { await recalculate() } } label: {
                        HStack {
                            Text("Recalcular duraciones")
                            Spacer()
                            if recalculating { ProgressView() }
                        }
                    }
                    .disabled(recalculating || songs.isEmpty)
                } header: {
                    Text("Biblioteca")
                } footer: {
                    Text("Vuelve a medir la duración real de cada canción por si alguna aparece con un tiempo distinto.")
                }
            }
            .navigationTitle("Ajustes")
            .alert("Cobalt", isPresented: Binding(get: { testMessage != nil },
                                                  set: { if !$0 { testMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(testMessage ?? "") }
            .miniPlayerInset()
        }
    }

    private func swatch(_ choice: ThemeChoice) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(choice.gradient).frame(width: 46, height: 46)
                if ThemeStore.shared.choice == choice {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            Text(choice.name)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    @MainActor
    private func testCobalt() async {
        testing = true
        defer { testing = false }
        do {
            let info = try await CobaltClient.ping()
            testMessage = "Conectado correctamente.\n\(info)"
        } catch {
            testMessage = error.localizedDescription
        }
    }

    @MainActor
    private func recalculate() async {
        recalculating = true
        var changed = 0
        for song in songs {
            let asset = LibraryManager.preciseAsset(song.url)
            guard let d = try? await asset.load(.duration),
                  d.seconds.isFinite, d.seconds > 0 else { continue }
            if abs(d.seconds - song.duration) > 0.5 {
                song.duration = d.seconds
                changed += 1
            }
        }
        try? context.save()
        recalculating = false
        if changed == 0 {
            Toast.shared.show("Las duraciones ya eran correctas", icon: "info.circle.fill")
        } else {
            Toast.shared.show("Duraciones corregidas: \(changed)")
        }
    }
}
