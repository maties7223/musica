import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @AppStorage("cobaltURL") private var legacyURL = ""
    @AppStorage("cobaltKey") private var cobaltKey = ""
    @AppStorage("autoPasteLink") private var autoPaste = true
    @AppStorage("autoPlayAfterDownload") private var autoPlay = false

    @State private var instances = InstancePool.userList
    @State private var recalculating = false
    @State private var refreshing = false
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
                    if instances.isEmpty {
                        Text("Sin instancias propias.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(instances.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("https://tu-instancia.com", text: Binding(
                                get: { instances.indices.contains(index) ? instances[index] : "" },
                                set: { newValue in
                                    guard instances.indices.contains(index) else { return }
                                    instances[index] = newValue
                                    InstancePool.userList = instances
                                }))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            Button {
                                testOne(instances[index])
                            } label: {
                                Image(systemName: "bolt.horizontal")
                            }
                            .buttonStyle(.borderless)
                            .disabled(testing)
                        }
                    }
                    .onDelete { offsets in
                        instances.remove(atOffsets: offsets)
                        InstancePool.userList = instances
                    }
                    Button {
                        instances.append("")
                        InstancePool.userList = instances
                    } label: {
                        Label("Añadir instancia", systemImage: "plus")
                    }
                    Button {
                        Task {
                            refreshing = true
                            let count = await InstancePool.refreshPublic()
                            refreshing = false
                            Toast.shared.show(count > 0 ? "Instancias públicas: \(count)"
                                                        : "No se pudo actualizar la lista",
                                              icon: count > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        }
                    } label: {
                        HStack {
                            Text("Actualizar instancias públicas")
                            Spacer()
                            if refreshing { ProgressView() }
                        }
                    }
                    .disabled(refreshing)
                } header: {
                    Text("Instancias de Cobalt")
                } footer: {
                    Text("Se prueban en orden: la última que funcionó, las tuyas y las públicas. Puedes escribir la clave tras una barra vertical: https://host|CLAVE. Usa solo contenido que tengas derecho a descargar.")
                }

                Section {
                    Toggle("Usar instancias públicas de reserva", isOn: Binding(
                        get: { InstancePool.usePublic },
                        set: { InstancePool.usePublic = $0 }))
                    Toggle("Rellenar con el portapapeles al abrir", isOn: $autoPaste)
                    Toggle("Reproducir al terminar la descarga", isOn: $autoPlay)
                } header: {
                    Text("Descargas")
                }

                Section {
                    SecureField("Clave de API por defecto (opcional)", text: $cobaltKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await testCobalt() }
                    } label: {
                        HStack {
                            Text("Probar instancias")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)
                } header: {
                    Text("Acceso")
                } footer: {
                    Text("La clave se envía a las instancias que la pidan. La pública api.cobalt.tools necesita la suya.")
                }

                Section {
                    Button {
                        Task { await recalculate() }
                    } label: {
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
            .onAppear(perform: migrate)
            .miniPlayerInset()
        }
    }

    /// Pasa la antigua dirección única a la lista de instancias.
    private func migrate() {
        let old = legacyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty else { return }
        if !instances.contains(where: { $0.lowercased() == old.lowercased() }) {
            instances.insert(old, at: 0)
            InstancePool.userList = instances
        }
        legacyURL = ""
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

    private func testOne(_ instance: String) {
        let text = instance.trimmed
        guard !text.isEmpty else { return }
        testing = true
        Task {
            defer { testing = false }
            InstancePool.userList = instances
            do {
                let info = try await CobaltClient.ping(instance: text)
                testMessage = "Conectado.\n\(info)"
            } catch {
                testMessage = error.localizedDescription
            }
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
