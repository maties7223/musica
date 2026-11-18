import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var youtubeURL: String = ""
    @State private var isDownloading: Bool = false
    @State private var statusMessage: String = ""

    var body: some View {
        Form {
            Section(header: Text("Descargar desde YouTube")) {
                TextField("Pega el enlace de YouTube aquí", text: $youtubeURL)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif
                
                Button(action: {
                    guard !youtubeURL.isEmpty else { return }
                    Task {
                        isDownloading = true
                        statusMessage = "Descargando..."
                        
                        let success = await LibraryManager.downloadFromYouTube(url: youtubeURL, into: modelContext)
                        
                        isDownloading = false
                        if success {
                            statusMessage = "¡Descargado e importado con éxito!"
                            youtubeURL = ""
                        } else {
                            statusMessage = "Error al descargar. Comprueba el enlace."
                        }
                    }
                }) {
                    if isDownloading {
                        HStack {
                            ProgressView()
                            Text(" Descargando audio...")
                        }
                    } else {
                        Text("Descargar y añadir a la biblioteca")
                    }
                }
                .disabled(youtubeURL.isEmpty || isDownloading)
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(statusMessage.contains("éxito") ? .green : .red)
                }
            }
        }
        .navigationTitle("Configuración")
    }
}
