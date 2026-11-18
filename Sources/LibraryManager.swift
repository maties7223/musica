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

    /// Borra canciones: archivo, carpetas vacías, listas y base de datos.
    @MainActor
    static func delete(_ songs: [Song], in context: ModelContext) {
        let ids = Set(songs.map(\.id))
        let urls = songs.map(\.url)

        for id in ids { PlayerManager.shared.remove(id: id) }

        for url in urls {
            try? FileManager.default.removeItem(at: url)
            removeEmptyFolders(from: url.deletingLastPathComponent())
        }

        if let playlists = try? context.fetch(FetchDescriptor<Playlist>()) {
            for p in playlists { p.songIDs.removeAll { ids.contains($0) } }
        }
        for s in songs { context.delete(s) }
        try? context.save()
    }

    private static func removeEmptyFolders(from folder: URL) {
        let root = musicDirectory.path
        var dir = folder
        while dir.path.hasPrefix(root), dir.path != root {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { break }
            try? FileManager.default.removeItem(at: dir)
            dir = dir.deletingLastPathComponent()
        }
    }
}
