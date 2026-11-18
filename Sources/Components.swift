import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import Observation

// MARK: - Caché de carátulas

enum ImageCache {
    static let cache = NSCache<NSString, UIImage>()

    static func image(id: UUID, data: Data?) -> UIImage? {
        guard let data else { return nil }
        // El tamaño forma parte de la clave para que se actualice al cambiar la imagen.
        let key = "\(id.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let img = UIImage(data: data) else { return nil }
        let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? img
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}

// MARK: - Preparar imágenes elegidas por el usuario

enum ImageTools {
    /// Reduce la imagen a un máximo de 1000 px y la guarda como JPEG.
    static func prepared(_ data: Data, maxSide: CGFloat = 1000) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

/// Permite elegir una imagen de Fotos o de Archivos.
struct ImageChooser: ViewModifier {
    @Binding var photos: Bool
    @Binding var files: Bool
    let onPick: (Data) -> Void

    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $photos, selection: $item, matching: .images)
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let prepared = ImageTools.prepared(data) {
                        await MainActor.run { onPick(prepared) }
                    }
                    await MainActor.run { item = nil }
                }
            }
            .background(
                Color.clear.fileImporter(isPresented: $files,
                                         allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url),
                       let prepared = ImageTools.prepared(data) {
                        onPick(prepared)
                    }
                }
            )
    }
}

extension View {
    func imageChooser(photos: Binding<Bool>, files: Binding<Bool>,
                      onPick: @escaping (Data) -> Void) -> some View {
        modifier(ImageChooser(photos: photos, files: files, onPick: onPick))
    }
}

// MARK: - Aviso discreto (se quita solo)

@Observable
final class Toast {
    static let shared = Toast()

    private(set) var text: String?
    private(set) var icon = "checkmark.circle.fill"
    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {}

    func show(_ message: String, icon: String = "checkmark.circle.fill") {
        task?.cancel()
        self.icon = icon
        withAnimation(.spring(duration: 0.3)) { text = message }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { self?.text = nil }
            }
        }
    }
}

struct ToastOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text = Toast.shared.text {
                Label(text, systemImage: Toast.shared.icon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Carátula (con degradado de color si no hay imagen)

struct ArtworkView: View {
    let id: UUID
    let data: Data?
    var size: CGFloat = 48
    var corner: CGFloat? = nil

    private var placeholder: some View {
        let a = Double(id.uuid.0) / 255.0
        let b = Double(id.uuid.1) / 255.0
        return ZStack {
            LinearGradient(
                colors: [
                    Color(hue: a, saturation: 0.55, brightness: 0.90),
                    Color(hue: (a + 0.10 + b * 0.1).truncatingRemainder(dividingBy: 1),
                          saturation: 0.75, brightness: 0.55)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    var body: some View {
        Group {
            if let image = ImageCache.image(id: id, data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner ?? size * 0.14, style: .continuous))
    }
}

// MARK: - Portada de lista (imagen propia o mosaico)

struct PlaylistCover: View {
    let playlist: Playlist
    let songs: [Song]
    var size: CGFloat = 56

    var body: some View {
        let arts = Array(songs.filter { $0.displayArtwork != nil }.prefix(4))
        ZStack {
            Theme.gradient
            if let own = playlist.coverData {
                ArtworkView(id: playlist.id, data: own, size: size, corner: 0)
            } else if arts.count >= 4 {
                let h = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) { tile(arts[0], h); tile(arts[1], h) }
                    HStack(spacing: 0) { tile(arts[2], h); tile(arts[3], h) }
                }
            } else if let first = arts.first {
                ArtworkView(id: first.id, data: first.displayArtwork, size: size, corner: 0)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private func tile(_ s: Song, _ h: CGFloat) -> some View {
        ArtworkView(id: s.id, data: s.displayArtwork, size: h, corner: 0)
    }
}

// MARK: - Botones Reproducir / Aleatorio

struct PlayShuffleButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Reproducir", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onShuffle) {
                Label("Aleatorio", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .fontWeight(.semibold)
    }
}

// MARK: - Fila de canción

struct SongRow: View {
    let song: Song
    var selecting = false
    var selected = false
    /// Si se indica, el menú contextual ofrece "Quitar de esta lista".
    var onRemoveFromPlaylist: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(PlayerManager.self) private var player
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @State private var confirmDelete = false
    @State private var showPhotos = false
    @State private var showFiles = false

    private var isCurrent: Bool { player.currentTrack?.id == song.id }

    private func add(to playlist: Playlist) {
        if playlist.songIDs.contains(song.id) {
            Toast.shared.show("Ya está en «\(playlist.name)»", icon: "info.circle.fill")
        } else {
            playlist.songIDs.append(song.id)
            Toast.shared.show("Añadida a «\(playlist.name)»")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
            }
            ArtworkView(id: song.id, data: song.displayArtwork, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Theme.accent : Color.primary)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
            Text(song.duration.mmss)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Añadir a lista", systemImage: "text.badge.plus") {
                if playlists.isEmpty { Text("Primero crea una lista") }
                ForEach(playlists) { p in
                    Button {
                        add(to: p)
                    } label: {
                        if p.songIDs.contains(song.id) {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            }
            if let onRemoveFromPlaylist {
                Button("Quitar de esta lista", systemImage: "minus.circle",
                       action: onRemoveFromPlaylist)
            }
            Menu("Imagen", systemImage: "photo") {
                Button("Elegir de Fotos", systemImage: "photo.on.rectangle") { showPhotos = true }
                Button("Elegir de Archivos", systemImage: "folder") { showFiles = true }
                if song.customArtworkData != nil {
                    Button("Quitar imagen", systemImage: "trash", role: .destructive) {
                        song.customArtworkData = nil
                    }
                }
            }
            Button("Eliminar de la biblioteca", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        }
        .imageChooser(photos: $showPhotos, files: $showFiles) { data in
            song.customArtworkData = data
        }
        .confirmationDialog("¿Eliminar esta canción?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                LibraryManager.delete([song], in: context)
            }
        } message: {
            Text("Se borrará de la app y de tus listas.")
        }
    }
}

// MARK: - Mini reproductor flotante

struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerManager.self) private var player
    @State private var showFull = false

    private var progress: Double {
        player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        ArtworkView(id: track.id, data: track.artwork, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1).font(.subheadline.weight(.semibold))
                            Text(track.artist).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2).frame(width: 36)
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.title2).frame(width: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        GeometryReader { g in
                            Capsule().fill(Theme.accent)
                                .frame(width: max(0, g.size.width * progress), height: 2.5)
                        }
                        .frame(height: 2.5)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
                }
            }
            .sheet(isPresented: $showFull) {
                PlayerView().environment(player)
            }
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}
