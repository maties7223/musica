import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Ruta relativa dentro de Documents/Music (Artista/Álbum/archivo.mp3)
    var relativePath: String
    @Attribute(.externalStorage) var artworkData: Data?
    /// Imagen elegida por el usuario (tiene prioridad sobre la carátula del archivo).
    @Attribute(.externalStorage) var customArtworkData: Data? = nil
    var dateAdded: Date

    init(title: String, artist: String, album: String, duration: Double,
         relativePath: String, artworkData: Data?) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.relativePath = relativePath
        self.artworkData = artworkData
        self.dateAdded = Date()
    }

    var url: URL {
        LibraryManager.musicDirectory.appending(path: relativePath)
    }

    /// Imagen que se muestra: la del usuario si existe, si no la del archivo.
    var displayArtwork: Data? { customArtworkData ?? artworkData }

    /// Artista a mostrar: la etiqueta del archivo o, si no hay, el que aparece en el título.
    var displayArtist: String {
        let tag = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && tag != ArtistParser.unknown { return tag }
        return ArtistParser.fromTitle(title) ?? ArtistParser.unknown
    }

    /// Solo el primer artista (para agrupar en la pestaña Artistas).
    var mainArtist: String {
        let name = ArtistParser.first(of: displayArtist)
        return name.isEmpty ? ArtistParser.unknown : name
    }

    /// Clave de agrupación: ignora mayúsculas y acentos.
    var artistKey: String {
        mainArtist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

@Model
final class Playlist {
    var id: UUID
    var name: String
    /// IDs de canciones en orden
    var songIDs: [UUID]
    var createdAt: Date
    /// Imagen elegida por el usuario para la lista.
    @Attribute(.externalStorage) var coverData: Data? = nil

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.songIDs = []
        self.createdAt = Date()
    }
}

/// Copia ligera de una canción para la cola de reproducción.
struct Track: Identifiable, Equatable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let url: URL
    let artwork: Data?

    init(song: Song) {
        id = song.id
        title = song.title
        artist = song.displayArtist
        album = song.album
        duration = song.duration
        url = song.url
        artwork = song.displayArtwork
    }
}

// MARK: - Detección de artistas

enum ArtistParser {
    static let unknown = "Artista desconocido"

    /// Separadores que indican que hay más de un artista.
    private static let separators = [",", ";", " & ", " feat.", " feat ", " ft.", " ft ",
                                     " featuring ", " x ", "(", "["]
    private static let titleDashes = [" - ", " – ", " — "]

    /// Se queda solo con el primer artista de un texto como "A, B & C".
    static func first(of text: String) -> String {
        var end = text.endIndex
        for sep in separators {
            if let r = text.range(of: sep, options: .caseInsensitive), r.lowerBound < end {
                end = r.lowerBound
            }
        }
        return text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detecta el artista en títulos con formato "Artista - Canción".
    static func fromTitle(_ title: String) -> String? {
        // Quita un número de pista inicial: "01 - ", "1. ", "03) "
        let text = title.replacingOccurrences(of: "^\\d{1,3}\\s*[-–.)]\\s*", with: "",
                                              options: .regularExpression)
        let ranges = titleDashes.compactMap { text.range(of: $0) }
        guard let r = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let name = first(of: String(text[..<r.lowerBound]))
        guard !name.isEmpty, name.contains(where: { !$0.isNumber }) else { return nil }
        return name
    }
}

extension Double {
    var mmss: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let s = Int(self)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
