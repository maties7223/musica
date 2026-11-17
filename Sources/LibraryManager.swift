import Foundation
import AVFoundation
import SwiftData

enum LibraryManager {
    static var musicDirectory: URL {
        let dir = URL.documentsDirectory.appending(path: "Music", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct Metadata {
        var title: String
        var artist = "Artista desconocido"
        var album = "Álbum desconocido"
        var duration: Double = 0
        var artwork: Data?
    }

    /// Quita caracteres no válidos para nombres de carpeta/archivo.
    static func clean(_ text: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let result = text.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Desconocido" : result
    }

    static func readMetadata(from url: URL) async -> Metadata {
        var meta = Metadata(title: url.deletingPathExtension().lastPathComponent)
        let asset = AVURLAsset(url: url)

        if let d = try? await asset.load(.duration), d.seconds.isFinite {
            meta.duration = d.seconds
        }
        guard let items = try? await asset.load(.commonMetadata) else { return meta }

        func find(_ id: AVMetadataIdentifier) -> AVMetadataItem? {
            AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first
        }
        if let i = find(.commonIdentifierTitle),
           let s = try? await i.load(.stringValue), !s.isEmpty { meta.title = s }
        if let i = find(.commonIdentifierArtist),
           let s = try? await i.load(.stringValue), !s.isEmpty { meta.artist = s }
        if let i = find(.commonIdentifierAlbumName),
           let s = try? await i.load(.stringValue), !s.isEmpty { meta.album = s }
        if let i = find(.commonIdentifierArtwork),
           let d = try? await i.load(.dataValue) { meta.artwork = d }
        return meta
    }

    /// Copia los archivos a Documents/Music/Artista/Álbum/ y los registra en la base de datos.
    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> (added: Int, skipped: Int) {
        var added = 0, skipped = 0

        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let meta = await readMetadata(from: url)
            let relativePath = "\(clean(meta.artist))/\(clean(meta.album))/\(clean(url.lastPathComponent))"
            let destination = musicDirectory.appending(path: relativePath)

            if FileManager.default.fileExists(atPath: destination.path) {
                skipped += 1
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                skipped += 1
                continue
            }

            context.insert(Song(title: meta.title, artist: meta.artist, album: meta.album,
                                duration: meta.duration, relativePath: relativePath,
                                artworkData: meta.artwork))
            added += 1
        }
        try? context.save()
        return (added, skipped)
    }

    @MainActor
    static func delete(_ song: Song, in context: ModelContext) {
        PlayerManager.shared.remove(id: song.id)
        try? FileManager.default.removeItem(at: song.url)

        if let playlists = try? context.fetch(FetchDescriptor<Playlist>()) {
            for p in playlists { p.songIDs.removeAll { $0 == song.id } }
        }
        context.delete(song)
        try? context.save()
    }
}
