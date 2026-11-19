import Foundation
import SwiftUI

/// Servicio detectado a partir de un enlace pegado.
enum LinkService: String {
    case youtube, youtubeMusic, spotify, soundcloud, other

    var name: String {
        switch self {
        case .youtube, .youtubeMusic: return "YouTube"
        case .spotify: return "Spotify"
        case .soundcloud: return "SoundCloud"
        case .other: return "Enlace"
        }
    }

    var icon: String {
        switch self {
        case .youtube, .youtubeMusic: return "play.rectangle.fill"
        case .spotify: return "waveform.circle.fill"
        case .soundcloud: return "cloud.fill"
        case .other: return "link"
        }
    }

    var tint: Color {
        switch self {
        case .youtube, .youtubeMusic: return .red
        case .spotify: return .green
        case .soundcloud: return .orange
        case .other: return .secondary
        }
    }

    /// Spotify no entrega audio: hay que buscarlo en YouTube.
    var needsSearch: Bool { self == .spotify }

    static func detect(_ text: String) -> LinkService {
        guard let url = URL(string: text.trimmed), let host = url.host()?.lowercased() else {
            return .other
        }
        if host.hasSuffix("spotify.com") || host == "spotify.link" { return .spotify }
        if host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            return host.hasPrefix("music.") ? .youtubeMusic : .youtube
        }
        if host.hasSuffix("soundcloud.com") { return .soundcloud }
        return .other
    }

    /// Enlaces válidos de la entrada: ignora líneas vacías y texto suelto.
    static func links(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { $0.trimmed }
            .filter { $0.lowercased().hasPrefix("http") }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
