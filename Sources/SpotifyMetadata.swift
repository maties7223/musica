import Foundation

struct TrackInfo {
    var title: String
    var artist: String?
    var artworkURL: URL?

    /// Consulta para buscar la canción en YouTube.
    var query: String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(artist) \(title)"
    }
}

enum SpotifyResolver {
    /// Obtiene título y artista de un enlace de Spotify sin necesidad de cuenta.
    /// Primero el endpoint oEmbed público y, si falla, la página de inserción.
    static func lookup(_ link: String) async throws -> TrackInfo {
        if let info = try? await oEmbed(link), !info.title.isEmpty { return info }

        if let id = trackID(link), let info = try? await embedPage(id: id), !info.title.isEmpty {
            return info
        }
        throw CobaltError.content("No se pudo leer la canción de Spotify. Prueba con el enlace de YouTube.")
    }

    private static func oEmbed(_ link: String) async throws -> TrackInfo {
        var comps = URLComponents(string: "https://open.spotify.com/oembed")!
        comps.queryItems = [URLQueryItem(name: "url", value: link)]
        var request = URLRequest(url: comps.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CobaltError.content("Spotify no devolvió datos para ese enlace.")
        }

        let title = (json["title"] as? String)?.trimmed ?? ""
        var artist = (json["author_name"] as? String)?.trimmed
        var clean = title
        // oEmbed a veces devuelve "Canción - Artista" en el título.
        if artist == nil, let range = title.range(of: " - ") {
            clean = String(title[..<range.lowerBound]).trimmed
            artist = String(title[range.upperBound...]).trimmed
        }
        let art = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
        return TrackInfo(title: clean, artist: artist, artworkURL: art)
    }

    private static func trackID(_ link: String) -> String? {
        guard let url = URL(string: link), url.host()?.lowercased().hasSuffix("spotify.com") == true else {
            return nil
        }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "track" else { return nil }
        return String(parts[1])
    }

    private static func embedPage(id: String) async throws -> TrackInfo {
        var request = URLRequest(url: URL(string: "https://open.spotify.com/embed/track/\(id)")!,
                                 timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw CobaltError.content("Respuesta inesperada de Spotify.")
        }

        let name = firstMatch(in: html, pattern: #""name"\s*:\s*"([^"]+)""#)
        let artist = firstMatch(in: html, pattern: #""artists"\s*:\s*\[\s*\{\s*"name"\s*:\s*"([^"]+)""#)
        let art = firstMatch(in: html, pattern: #""url"\s*:\s*"(https://i\.scdn\.co/[^"]+)""#)
        guard let name, !name.isEmpty else { throw CobaltError.content("Canción no encontrada.") }
        return TrackInfo(title: name, artist: artist, artworkURL: art.flatMap(URL.init(string:)))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
