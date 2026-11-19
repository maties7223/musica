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
}

@Model
final class Playlist {
    var id: UUID
    var name: String
    /// IDs de canciones en orden
    var songIDs: [UUID]
    var createdAt: Date

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
        artist = song.artist
        album = song.album
        duration = song.duration
        url = song.url
        artwork = song.artworkData
    }
}

extension Double {
    var mmss: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let s = Int(self)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
