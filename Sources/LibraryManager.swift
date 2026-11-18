import Foundation
import AVFoundation
import SwiftData
import UniformTypeIdentifiers
import SwiftOGG

enum LibraryManager {
    static var musicDirectory: URL {
        let dir = URL.documentsDirectory.appending(path: "Music", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extensiones que iOS no reproduce y que la app convierte a M4A al importar.
    static let opusExtensions: Set<String> = ["opus", "ogg", "oga"]

    /// Tipos de archivo que se pueden elegir en el selector.
    static var importTypes: [UTType] {
        var types: [UTType] = [.audio]
        for ext in opusExtensions {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    /// Asset que mide la duración real (importante en MP3 sin cabecera de duración).
    static func preciseAsset(_ url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    }

    struct Metadata {
        var title: String
        var artist = "Artista desconocido"
        var album = "Álbum desconocido"
        var duration: Double = 0
        var artwork: Data?
    }

    struct ImportResult {
        var added = 0
        var skipped = 0
        var failed = 0
    }

    static func clean(_ text: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let result = text.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Desconocido" : result
    }

    // MARK: - Metadatos

    static func readMetadata(from url: URL, fallbackName: String) async -> Metadata {
        var meta = Metadata(title: URL(fileURLWithPath: fallbackName)
            .deletingPathExtension().lastPathComponent)
        let asset = preciseAsset(url)

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

    /// Lee título, artista y álbum de las etiquetas "OpusTags" de un archivo Ogg Opus.
    struct OpusTags { var title: String?; var artist: String?; var album: String? }

    static func readOpusTags(from url: URL) -> OpusTags {
        var tags = OpusTags()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return tags }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024),
              let marker = data.range(of: Data("OpusTags".utf8)) else { return tags }

        var pos = marker.upperBound
        func u32() -> Int? {
            guard pos + 4 <= data.count else { return nil }
            var v = 0
            for i in 0..<4 { v |= Int(data[pos + i]) << (8 * i) }
            pos += 4
            return v
        }
        guard let vendorLen = u32(), pos + vendorLen <= data.count else { return tags }
        pos += vendorLen
        guard let count = u32() else { return tags }

        for _ in 0..<min(count, 200) {
            guard let len = u32(), len < 100_000, pos + len <= data.count else { break }
            let text = String(decoding: data[pos..<(pos + len)], as: UTF8.self)
            pos += len
            guard let eq = text.firstIndex(of: "=") else { continue }
            let key = text[..<eq].uppercased()
            let value = String(text[text.index(after: eq)...])
            switch key {
            case "TITLE": tags.title = value
            case "ARTIST": tags.artist = value
            case "ALBUM": tags.album = value
            default: break
            }
        }
        return tags
    }

    // MARK: - Importar

    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> ImportResult {
        var result = ImportResult()

        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            var source = url
            var finalName = url.lastPathComponent
            var tempFile: URL?
            var tags: OpusTags?
            defer { if let t = tempFile { try? FileManager.default.removeItem(at: t) } }

            // Opus/Ogg → M4A (AAC), que iOS sí reproduce
            if opusExtensions.contains(url.pathExtension.lowercased()) {
                tags = readOpusTags(from: url)
                let tmp = FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString + ".m4a")
                let ok = await Task.detached { () -> Bool in
                    do {
                        try OGGConverter.convertOpusOGGToM4aFile(src: url, dest: tmp)
                        return true
                    } catch {
                        return false
                    }
                }.value
                guard ok else { result.failed += 1; continue }
                source = tmp
                tempFile = tmp
                finalName = url.deletingPathExtension().lastPathComponent + ".m4a"
            }

            var meta = await readMetadata(from: source, fallbackName: finalName)
            if let t = tags {
                if let v = t.title, !v.isEmpty { meta.title = v }
                if let v = t.artist, !v.isEmpty { meta.artist = v }
                if let v = t.album, !v.isEmpty { meta.album = v }
            }

            let relativePath = "\(clean(meta.artist))/\(clean(meta.album))/\(clean(finalName))"
            let destination = musicDirectory.appending(path: relativePath)

            if FileManager.default.fileExists(atPath: destination.path) {
                result.skipped += 1
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                result.skipped += 1
                continue
            }

            context.insert(Song(title: meta.title, artist: meta.artist, album: meta.album,
                                duration: meta.duration, relativePath: relativePath,
                                artworkData: meta.artwork))
            result.added += 1
        }
        try? context.save()
        return result
    }

    // MARK: - Descarga desde YouTube (Cobalt API)

    @MainActor
    static func downloadFromYouTube(url youtubeURL: String, into context: ModelContext) async -> Bool {
        guard let apiURL = URL(string: "https://api.cobalt.tools/api/json") else { return false }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://cobalt.tools", forHTTPHeaderField: "Origin")
        
        let body: [String: Any] = [
            "url": youtubeURL,
            "audioFormat": "m4a"
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            
            let status = json["status"] as? String ?? ""
            guard status == "stream" || status == "redirect" || status == "picker",
                  let downloadString = json["url"] as? String,
                  let downloadURL = URL(string: downloadString) else {
                return false
            }
            
            let (tempLocalURL, _) = try await URLSession.shared.download(from: downloadURL)
            let result = await importFiles([tempLocalURL], into: context)
            
            try? FileManager.default.removeItem(at: tempLocalURL)
            
            return result.added > 0
        } catch {
            print("Error descargando de YouTube con Cobalt: \(error)")
            return false
        }
    }

    // MARK: - Borrar

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
