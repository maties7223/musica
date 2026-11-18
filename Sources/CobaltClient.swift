import Foundation
import SwiftData

enum CobaltError: LocalizedError {
    case notConfigured
    case invalidLink
    case invalidInstance
    case noAudio
    case badResponse
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Primero escribe la dirección de tu instancia de Cobalt en Ajustes."
        case .invalidLink:
            return "El enlace no es válido. Debe empezar por http:// o https://."
        case .invalidInstance:
            return "La dirección de la instancia de Cobalt no es válida."
        case .noAudio:
            return "Este enlace no ofrece un audio que se pueda descargar."
        case .badResponse:
            return "La instancia respondió algo inesperado. Revisa su dirección en Ajustes."
        case .server(let text), .network(let text):
            return text
        }
    }
}

/// Cliente mínimo de la API de Cobalt (POST / → enlace de descarga del audio).
enum CobaltClient {
    static var instanceURL: String { UserDefaults.standard.string(forKey: "cobaltURL") ?? "" }
    static var apiKey: String { UserDefaults.standard.string(forKey: "cobaltKey") ?? "" }

    // MARK: - Peticiones

    private static func baseURL() throws -> URL {
        var text = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CobaltError.notConfigured }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), url.host() != nil else { throw CobaltError.invalidInstance }
        return url
    }

    private static func makeRequest(_ url: URL, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection:
            return "La instancia debe usar HTTPS (https://)."
        case .notConnectedToInternet:
            return "No hay conexión a internet."
        case .timedOut:
            return "La instancia tarda demasiado en responder."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "No se puede conectar con la instancia. Revisa su dirección."
        default:
            return error.localizedDescription
        }
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CobaltError.badResponse }
            return (data, http)
        } catch let error as CobaltError {
            throw error
        } catch let error as URLError {
            throw CobaltError.network(describe(error))
        } catch {
            throw CobaltError.network(error.localizedDescription)
        }
    }

    // MARK: - Probar conexión

    static func ping() async throws -> String {
        let (data, _) = try await send(makeRequest(try baseURL(), method: "GET"))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["cobalt"] as? [String: Any] else { throw CobaltError.badResponse }
        let version = info["version"] as? String ?? "?"
        let services = (info["services"] as? [String])?.count ?? 0
        return "Cobalt \(version) · \(services) servicios compatibles"
    }

    // MARK: - Pedir el audio

    struct Resolved {
        let url: URL
        let filename: String
    }

    static func resolve(link: String) async throws -> Resolved {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let linkURL = URL(string: trimmed),
              let scheme = linkURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              linkURL.host() != nil else { throw CobaltError.invalidLink }

        let body: [String: Any] = [
            "url": trimmed,
            "downloadMode": "audio",
            "audioFormat": "mp3",
            "audioBitrate": "320",
            "filenameStyle": "pretty"
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let (responseData, http) = try await send(makeRequest(try baseURL(), method: "POST", body: data))

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = json["status"] as? String else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CobaltError.server("La instancia no te deja usarla. Añade su clave de API en Ajustes.")
            }
            throw CobaltError.badResponse
        }

        switch status {
        case "tunnel", "redirect":
            guard let text = json["url"] as? String, let url = URL(string: text) else {
                throw CobaltError.badResponse
            }
            return Resolved(url: url, filename: json["filename"] as? String ?? "audio.mp3")
        case "picker":
            // Si hay varios elementos, solo se puede usar el audio general (si existe).
            if let text = json["audio"] as? String, let url = URL(string: text) {
                return Resolved(url: url, filename: json["audioFilename"] as? String ?? "audio.mp3")
            }
            throw CobaltError.noAudio
        case "error":
            let code = (json["error"] as? [String: Any])?["code"] as? String ?? "desconocido"
            throw CobaltError.server(message(forCode: code))
        default:
            throw CobaltError.badResponse
        }
    }

    private static func message(forCode code: String) -> String {
        if code.contains("auth") {
            return "La instancia exige autenticación. Añade tu clave de API en Ajustes."
        }
        if code.contains("rate_exceeded") {
            return "Demasiadas peticiones seguidas. Espera un momento y vuelve a intentarlo."
        }
        if code.contains("link.invalid") || code.contains("link.unsupported") {
            return "Cobalt no reconoce o no admite este enlace."
        }
        if code.contains("unavailable") { return "El contenido no está disponible." }
        if code.contains("private") { return "El contenido es privado." }
        if code.contains("live") { return "No se puede descargar una emisión en directo." }
        if code.contains("too_long") { return "El contenido es demasiado largo para esta instancia." }
        if code.contains("region") { return "El contenido no está disponible en la región de la instancia." }
        if code.contains(".age") { return "El contenido tiene restricción de edad." }
        if code.contains("youtube.login") {
            return "YouTube está pidiendo iniciar sesión, así que esta instancia no puede descargarlo ahora."
        }
        if code.contains("fetch") {
            return "Cobalt no pudo obtener el contenido (el servicio lo ha bloqueado o ha cambiado)."
        }
        return "Cobalt devolvió un error (\(code))."
    }

    // MARK: - Descargar e importar

    /// Descarga el audio a una carpeta temporal y devuelve el archivo.
    static func downloadAudio(link: String) async throws -> URL {
        let resolved = try await resolve(link: link)

        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await URLSession.shared.download(from: resolved.url)
        } catch let error as URLError {
            throw CobaltError.network(describe(error))
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CobaltError.badResponse
        }

        var name = LibraryManager.clean(resolved.filename)
        if URL(fileURLWithPath: name).pathExtension.isEmpty { name += ".mp3" }

        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Descarga el audio del enlace y lo añade a la biblioteca.
    @MainActor
    static func addToLibrary(link: String, context: ModelContext) async throws -> LibraryManager.ImportResult {
        let file = try await downloadAudio(link: link)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return await LibraryManager.importFiles([file], into: context)
    }
}
