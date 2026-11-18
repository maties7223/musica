import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @State private var recalculating = false
    
    // Estados para la descarga de música
    @State private var enlaceYouTube: String = ""
    @State private var estadoTexto: String = ""
    @State private var descargando: Bool = false

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

                // NUEVA SECCIÓN DE DESCARGA
                Section {
                    TextField("Pega enlace de YouTube...", text: $enlaceYouTube)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button {
                        descargarAudio(desde: enlaceYouTube)
                    } label: {
                        HStack {
                            Text("Descargar .m4a")
                            Spacer()
                            if descargando { ProgressView() }
                        }
                    }
                    .disabled(enlaceYouTube.isEmpty || descargando)
                    
                    if !estadoTexto.isEmpty {
                        Text(estadoTexto)
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                } header: {
                    Text("Descargar música")
                } footer: {
                    Text("Pega el enlace de YouTube para bajar la canción a través de tu servidor.")
                }
            }
            .navigationTitle("Ajustes")
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

    // FUNCIÓN DE PETICIÓN AL SERVIDOR DE RENDER (CON TU URL YA CONFIGURADA)
    private func descargarAudio(desde urlTexto: String) {
        let servidorUrlString = "https://servidor-musica-thom.onrender.com/download?url=\(urlTexto)"
        
        guard let urlCodificada = servidorUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlCodificada) else {
            estadoTexto = "Enlace no válido"
            return
        }
        
        descargando = true
        estadoTexto = "Descargando del servidor..."
        
        URLSession.shared.dataTask(with: url) { datos, respuesta, error in
            DispatchQueue.main.async {
                descargando = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    estadoTexto = "Error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let httpRespuesta = respuesta as? HTTPURLResponse, httpRespuesta.statusCode == 200,
                  let datosAudio = datos else {
                DispatchQueue.main.async {
                    estadoTexto = "Error en el servidor (¿está dormido?)"
                }
                return
            }
            
            do {
                let directorioTemporal = FileManager.default.temporaryDirectory
                let nombreArchivo = UUID().uuidString + ".m4a"
                let rutaDestino = directorioTemporal.appendingPathComponent(nombreArchivo)
                
                try datosAudio.write(to: rutaDestino)
                
                DispatchQueue.main.async {
                    estadoTexto = "¡Descargado con éxito!"
                    enlaceYouTube = ""
                    Toast.shared.show("Canción bajada al temporal")
                    print("Guardado en: \(rutaDestino.path)")
                }
            } catch {
                DispatchQueue.main.async {
                    estadoTexto = "Error al guardar localmente"
                }
            }
        }.resume()
    }
}
