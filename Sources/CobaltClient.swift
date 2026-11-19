import Foundation
import SwiftData

enum CobaltError: LocalizedError {
    case invalidLink
    case noInstances
    case noAudio
    case cancelled
    case content(String)
    case retryable(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "El enlace no es válido. Debe empezar por http:// o https://."
        case .noInstances:
            return "No hay ninguna instancia de Cobalt configurada. Añade una en Ajustes."
        case .noAudio:
            return "Este enlace no ofrece un audio que se pueda descargar."
        case .cancelled:
            return "Descarga cancelada."
        case .content(let text), .retryable(let text):
            return text
        }
    }
}

enum DownloadPhase: Equatable {
    case preparing, searching, downloading, importing

    var label: String {
        switch self {
        case .preparing: return "Preparando…"
        case .searching: return "Buscando la canción…"
        case .downloading: return "Descargando audio…"
        case .importing: return "Añadiendo a la biblioteca…"
        }
    }
}

/// Cliente de la API de Cobalt con relevo entre instancias.
enum CobaltClient {
    private static var globalKey: String {
        UserDefaults.standard.string(forKey: "cobaltKey") ?? ""
    }

    // MARK: - Entrada

    @MainActor
    static func addToLibrary(
        link: String,
        context: ModelContext,
        onPhase: @escaping (DownloadPhase) -> Void = { _ in },
        onProgress: @escaping (Double) -> Void = { _ in }
    ) async throws -> LibraryManager.ImportResult {
        let text = link.trimmed
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else { throw CobaltError.invalidLink }

        onPhase(.preparing)
        let service = LinkService.detect(text)
        var info: TrackInfo?

        if service.needsSearch {
            onPhase(.searching)
            info = try? await SpotifyResolver.lookup(text)
        }

        let file = try await fetchAudio(link: text, info: info, onPhase: onPhase, onProgress: onProgress)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        onPhase(.importing)
        var overrideMeta: LibraryManager.Metadata?
        if let info {
            var meta = LibraryManager.Metadata(title: info.title)
            if let artist = info.artist, !artist.isEmpty { meta.artist = artist }
            if let artURL = info.artworkURL,
               let (data, _) = try? await URLSession.shared.data(from: artURL),
               let prepared = ImageTools.prepared(data) {
                meta.artwork = prepared
            }
            overrideMeta = meta
        }
        return await LibraryManager.importFiles([file], into: context, override: { _ in overrideMeta })
    }

    // MARK: - Relevo entre instancias

    private static func fetchAudio(
        link: String,
        info: TrackInfo?,
        onPhase: @escaping (DownloadPhase) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let instances = InstancePool.ordered()
        guard !instances.isEmpty else { throw CobaltError.noInstances }

        var lastError: Error?
        for instance in instances {
            if Task.isCancelled { throw CobaltError.cancelled }
            do {
                onPhase(.downloading)
                let resolved = try await resolve(instance: instance, link: link, info: info)
                InstancePool.markGood(instance)
                return try await download(resolved, onProgress: onProgress)
            } catch let error as CobaltError {
                if case .content = error { throw error }
                if case .cancelled = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CobaltError.retryable("Ninguna instancia de Cobalt respondió. Prueba otra en Ajustes.")
    }

    // MARK: - Resolver

    struct Resolved {
        let url: URL
        let filename: String
    }

    private static func resolve(instance: String, link: String, info: TrackInfo?) async throws -> Resolved {
        let service = LinkService.detect(link)

        // Spotify y enlaces sin audio directo: buscar la canción en YouTube.
        if service.needsSearch || service == .spotify {
            let query = info?.query ?? link
            return try await search(instance: instance, query: query, original: link)
        }

        var body = audioBody()
        body["url"] = link
        return try await perform(instance: instance, body: body)
    }

    private static func search(instance: String, query: String, original: String) async throws -> Resolved {
        var body = audioBody()
        body["url"] = query
        body["youtubeSearch"] = true
        body["youtubeMusic"] = true

        do {
            return try await perform(instance: instance, body: body)
        } catch let error as CobaltError {
            guard case .content = error else { throw error }
            // Si la instancia no acepta búsquedas, se busca el vídeo por otra vía.
            if let videoURL = try? await searchYouTube(query: query) {
                var retry = audioBody()
                retry["url"] = videoURL
                return try await perform(instance: instance, body: retry)
            }
            throw CobaltError.content("No se encontró la canción en YouTube. Prueba con el enlace directo.")
        }
    }

    private static func audioBody() -> [String: Any] {
        [
            "downloadMode": "audio",
            "audioFormat": "mp3",
            "audioBitrate": "320",
            "filenameStyle": "pretty",
            "youtubeVideoQuality": "1080",
            "alwaysProxy": false
        ]
    }

    /// Respaldo: primer vídeo de la búsqueda de YouTube.
    private static func searchYouTube(query: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var request = URLRequest(url: comps.url!, timeoutInterval: 25)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #""videoId":"([A-Za-z0-9_-]{11})""#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return "https://www.youtube.com/watch?v=\(html[range])"
    }

    // MARK: - Petición

    private static func credentials(for instance: String) -> (URL, String) {
        let parts = instance.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        var text = String(parts[0]).trimmed
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        let key = parts.count > 1 ? String(parts[1]).trimmed : globalKey.trimmed
        guard let url = URL(string: text), url.host() != nil else {
            return (URL(string: "https://invalid.local")!, key)
        }
        return (url, key)
    }

    private static func perform(instance: String, body: [String: Any], depth: Int = 0) async throws -> Resolved {
        let (base, key) = credentials(for: instance)
        guard base.host() != "invalid.local" else {
            throw CobaltError.retryable("Dirección de instancia no válida.")
        }

        var request = URLRequest(url: base, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let cast = response as? HTTPURLResponse else {
                throw CobaltError.retryable("Respuesta inesperada de la instancia.")
            }
            data = responseData
            http = cast
        } catch let error as URLError {
            throw CobaltError.retryable(describe(error))
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw CobaltError.retryable("La instancia pide clave de API o te ha limitado.")
        }
        if http.statusCode == 429 {
            throw CobaltError.retryable("La instancia está saturada. Probando otra…")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw CobaltError.retryable("La instancia respondió algo inesperado.")
        }

        switch status {
        case "tunnel", "redirect":
            guard let text = json["url"] as? String, let url = URL(string: text) else {
                throw CobaltError.retryable("La instancia no devolvió una descarga.")
            }
            return Resolved(url: url, filename: json["filename"] as? String ?? "audio.mp3")

        case "local-processing":
            if let text = json["tunnel"] as? String, let url = URL(string: text) {
                return Resolved(url: url, filename: json["filename"] as? String ?? "audio.mp3")
            }
            if let session = json["session"] as? String {
                return try await poll(instance: instance, session: session, depth: depth)
            }
            throw CobaltError.retryable("La instancia no terminó de procesar el audio.")

        case "picker":
            guard depth < 2, let items = json["picker"] as? [[String: Any]] else {
                if let text = json["audio"] as? String, let url = URL(string: text) {
                    return Resolved(url: url, filename: json["audioFilename"] as? String ?? "audio.mp3")
                }
                throw CobaltError.noAudio
            }
            let best = bestItem(in: items, matching: body["url"] as? String)
            guard let chosen = best?["url"] as? String else { throw CobaltError.noAudio }
            var next = body
            next["url"] = chosen
            return try await perform(instance: instance, body: next, depth: depth + 1)

        case "error":
            let code = (json["error"] as? [String: Any])?["code"] as? String ?? "desconocido"
            if code.contains("auth") || code.contains("rate") { throw CobaltError.retryable(message(for: code)) }
            throw CobaltError.content(message(for: code))

        default:
            throw CobaltError.retryable("Estado no reconocido: \(status).")
        }
    }

    /// Cobalt 11 devuelve una sesión que hay que consultar hasta que acaba.
    private static func poll(instance: String, session: String, depth: Int) async throws -> Resolved {
        let (base, key) = credentials(for: instance)
        let url = base.appending(path: "session/\(session)")

        for _ in 0..<20 {
            if Task.isCancelled { throw CobaltError.cancelled }
            try? await Task.sleep(for: .milliseconds(900))

            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !key.isEmpty { request.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization") }

            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else { continue }

            switch status {
            case "tunnel", "redirect":
                guard let text = json["url"] as? String, let resolved = URL(string: text) else {
                    throw CobaltError.retryable("La instancia no devolvió una descarga.")
                }
                return Resolved(url: resolved, filename: json["filename"] as? String ?? "audio.mp3")
            case "error":
                let code = (json["error"] as? [String: Any])?["code"] as? String ?? "desconocido"
                throw CobaltError.content(message(for: code))
            case "local-processing", "processing":
                continue
            default:
                if let text = json["url"] as? String, let resolved = URL(string: text) {
                    return Resolved(url: resolved, filename: json["filename"] as? String ?? "audio.mp3")
                }
            }
        }
        throw CobaltError.retryable("La instancia tardó demasiado en procesar el audio.")
    }

    private static func bestItem(in items: [[String: Any]], matching query: String?) -> [String: Any]? {
        let videos = items.filter { ($0["type"] as? String ?? "video") == "video" }
        guard let query, !query.isEmpty, videos.count > 1 else { return videos.first ?? items.first }
        let words = Set(query.lowercased().split(separator: " ").map(String.init))
        return videos.max { a, b in
            score(a, words) < score(b, words)
        }
    }

    private static func score(_ item: [String: Any], _ words: Set<String>) -> Int {
        let title = (item["title"] as? String ?? "").lowercased()
        return words.reduce(0) { $0 + (title.contains($1) ? 1 : 0) }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No hay conexión a internet."
        case .timedOut: return "La instancia tarda demasiado en responder."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "No se puede conectar con la instancia."
        case .appTransportSecurityRequiresSecureConnection:
            return "La instancia debe usar HTTPS."
        default: return error.localizedDescription
        }
    }

    private static func message(for code: String) -> String {
        if code.contains("auth") { return "La instancia exige una clave de API válida." }
        if code.contains("rate") { return "Demasiadas peticiones. Espera un momento." }
        if code.contains("link.invalid") || code.contains("link.unsupported") {
            return "Cobalt no reconoce o no admite este enlace."
        }
        if code.contains("unavailable") { return "El contenido no está disponible." }
        if code.contains("private") { return "El contenido es privado." }
        if code.contains("live") { return "No se puede descargar una emisión en directo." }
        if code.contains("too_long") { return "El contenido es demasiado largo." }
        if code.contains("region") { return "No disponible en la región de la instancia." }
        if code.contains(".age") { return "El contenido tiene restricción de edad." }
        if code.contains("youtube.login") {
            return "YouTube pide iniciar sesión para este vídeo."
        }
        if code.contains("fetch") { return "Cobalt no pudo obtener el contenido." }
        return "Cobalt devolvió un error (\(code))."
    }

    // MARK: - Comprobar instancias

    static func ping() async throws -> String {
        var lastError: Error = CobaltError.noInstances
        for instance in InstancePool.ordered() {
            do {
                return try await ping(instance: instance)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func ping(instance: String) async throws -> String {
        let (base, key) = credentials(for: instance)
        guard base.host() != "invalid.local" else {
            throw CobaltError.retryable("Dirección de instancia no válida.")
        }

        var request = URLRequest(url: base, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !key.isEmpty { request.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["cobalt"] as? [String: Any] else {
                throw CobaltError.retryable("La instancia no responde como Cobalt.")
            }
            InstancePool.markGood(instance)
            let version = info["version"] as? String ?? "?"
            let services = (info["services"] as? [String])?.count ?? 0
            return "Cobalt \(version) · \(services) servicios compatibles"
        } catch let error as URLError {
            throw CobaltError.retryable(describe(error))
        }
    }

    // MARK: - Descarga con progreso

    private static func download(_ resolved: Resolved, onProgress: @escaping (Double) -> Void) async throws -> URL {
        var name = LibraryManager.clean(resolved.filename)
        if URL(fileURLWithPath: name).pathExtension.isEmpty { name += ".mp3" }

        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name)

        let downloader = Downloader(destination: destination, onProgress: onProgress)
        return try await withTaskCancellationHandler {
            try await downloader.run(resolved.url)
        } onCancel: {
            downloader.cancel()
        }
    }

    private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let onProgress: (Double) -> Void
        private var continuation: CheckedContinuation<URL, Error>?
        private var task: URLSessionDownloadTask?
        private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

        init(destination: URL, onProgress: @escaping (Double) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func run(_ url: URL) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        }

        func cancel() {
            task?.cancel()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in onProgress(min(max(value, 0), 1)) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                finish(.failure(CobaltError.retryable("La descarga falló (HTTP \(http.statusCode)).")))
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                finish(.success(destination))
            } catch {
                finish(.failure(CobaltError.retryable("No se pudo guardar el archivo.")))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            if (error as? URLError)?.code == .cancelled {
                finish(.failure(CobaltError.cancelled))
            } else {
                finish(.failure(CobaltError.retryable(error.localizedDescription)))
            }
        }

        private func finish(_ result: Result<URL, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            session.finishTasksAndInvalidate()
            continuation.resume(with: result)
        }
    }
}
