import AVFoundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

enum RepeatMode: Int {
    case off, all, one

    var icon: String { self == .one ? "repeat.1" : "repeat" }

    var following: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

@Observable
final class PlayerManager {
    static let shared = PlayerManager()

    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off

    var currentTrack: Track? { queue.indices.contains(index) ? queue[index] : nil }
    /// Canciones que quedan por sonar después de la actual.
    var upcoming: [Track] { Array(queue.dropFirst(index + 1)) }

    @ObservationIgnored private var unshuffled: [Track] = []
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastSavedTime: Double = 0
    @ObservationIgnored private var restored = false

    private enum Keys {
        static let queue = "player.queue"
        static let unshuffled = "player.unshuffled"
        static let index = "player.index"
        static let time = "player.time"
        static let shuffle = "player.shuffle"
        static let repeatMode = "player.repeat"
    }

    private init() {
        let d = UserDefaults.standard
        isShuffled = d.bool(forKey: Keys.shuffle)
        repeatMode = RepeatMode(rawValue: d.integer(forKey: Keys.repeatMode)) ?? .off
        configureSession()
        configureRemoteCommands()
        observeTime()
        observeNotifications()
    }

    // MARK: - Reproducir

    /// Reproduce una lista empezando en `start`. Respeta el modo aleatorio si está activado.
    func play(_ songs: [Song], startAt start: Int = 0) {
        guard songs.indices.contains(start) else { return }
        let tracks = songs.map(Track.init)
        unshuffled = tracks
        if isShuffled {
            var rest = tracks
            let first = rest.remove(at: start)
            queue = [first] + rest.shuffled()
            index = 0
        } else {
            queue = tracks
            index = start
        }
        loadCurrent(autoplay: true)
    }

    /// Botón "Reproducir": en orden y con el aleatorio desactivado.
    func playInOrder(_ songs: [Song]) {
        setShuffle(false)
        play(songs)
    }

    /// Botón "Aleatorio": activa el aleatorio y empieza por una canción cualquiera.
    func playShuffled(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        setShuffle(true)
        play(songs, startAt: Int.random(in: songs.indices))
    }

    func toggle() { isPlaying ? pause() : resume() }

    func resume() {
        guard currentTrack != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        saveTime()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
            loadCurrent(autoplay: true)
        } else {
            index = 0
            loadCurrent(autoplay: repeatMode == .all)
        }
    }

    func previous() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            loadCurrent(autoplay: true)
        }
    }

    func seek(to time: Double) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        updateNowPlaying()
        saveTime()
    }

    // MARK: - Aleatorio y repetir

    func toggleShuffle() {
        if isShuffled {
            // Volver al orden original, dejando la canción actual donde está.
            let current = currentTrack
            let present = Set(queue.map(\.id))
            var ordered = unshuffled.filter { present.contains($0.id) }
            let known = Set(ordered.map(\.id))
            // Canciones añadidas con "a continuación" mientras estaba el aleatorio.
            let extras = queue.filter { !known.contains($0.id) }
            if let c = current, let i = ordered.firstIndex(where: { $0.id == c.id }) {
                ordered.insert(contentsOf: extras, at: i + 1)
                queue = ordered
                index = i
            } else {
                queue = ordered + extras
                index = max(0, queue.firstIndex(where: { $0.id == current?.id }) ?? 0)
            }
            unshuffled = []
            setShuffle(false)
        } else {
            guard queue.indices.contains(index) else {
                setShuffle(true)
                return
            }
            unshuffled = queue
            var rest = queue
            let first = rest.remove(at: index)
            queue = [first] + rest.shuffled()
            index = 0
            setShuffle(true)
        }
        saveQueue()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.following
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Keys.repeatMode)
    }

    private func setShuffle(_ on: Bool) {
        isShuffled = on
        UserDefaults.standard.set(on, forKey: Keys.shuffle)
    }

    // MARK: - Cola

    /// Pone la canción justo después de la que suena.
    func playNext(_ song: Song) {
        guard currentTrack != nil else {
            play([song])
            return
        }
        if currentTrack?.id == song.id {
            Toast.shared.show("Ya está sonando", icon: "info.circle.fill")
            return
        }
        dropOccurrences(of: song.id)
        queue.insert(Track(song: song), at: index + 1)
        saveQueue()
        Toast.shared.show("Se reproducirá a continuación",
                          icon: "text.line.first.and.arrowtriangle.forward")
    }

    /// Pone la canción al final de la cola.
    func addToQueue(_ song: Song) {
        guard currentTrack != nil else {
            play([song])
            return
        }
        if currentTrack?.id == song.id {
            Toast.shared.show("Ya está sonando", icon: "info.circle.fill")
            return
        }
        dropOccurrences(of: song.id)
        queue.append(Track(song: song))
        saveQueue()
        Toast.shared.show("Añadida a la cola", icon: "text.line.last.and.arrowtriangle.forward")
    }

    /// Salta a una canción de la cola.
    func jump(to id: UUID) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        index = i
        loadCurrent(autoplay: true)
    }

    func removeUpcoming(at offsets: IndexSet) {
        for o in offsets.sorted(by: >) {
            let i = index + 1 + o
            if queue.indices.contains(i) { queue.remove(at: i) }
        }
        saveQueue()
    }

    func moveUpcoming(from source: IndexSet, to destination: Int) {
        var up = upcoming
        up.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue.prefix(index + 1)) + up
        saveQueue()
    }

    /// Evita canciones repetidas en la cola (la actual no se toca).
    private func dropOccurrences(of id: UUID) {
        var removedBefore = 0
        var i = queue.count - 1
        while i >= 0 {
            if queue[i].id == id {
                queue.remove(at: i)
                if i < index { removedBefore += 1 }
            }
            i -= 1
        }
        index -= removedBefore
    }

    /// Llamar antes de borrar una canción.
    func remove(id: UUID) {
        unshuffled.removeAll { $0.id == id }
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        if i == index {
            player.pause()
            player.replaceCurrentItem(with: nil)
            queue = []
            unshuffled = []
            index = 0
            isPlaying = false
            currentTime = 0
            duration = 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        } else {
            queue.remove(at: i)
            if i < index { index -= 1 }
        }
        saveQueue()
    }

    // MARK: - Recordar lo último que sonaba

    private func saveQueue() {
        let d = UserDefaults.standard
        d.set(queue.map { $0.id.uuidString }, forKey: Keys.queue)
        d.set(isShuffled ? unshuffled.map { $0.id.uuidString } : [String](), forKey: Keys.unshuffled)
        d.set(index, forKey: Keys.index)
        if queue.isEmpty { d.set(0.0, forKey: Keys.time) }
    }

    func saveTime() {
        guard currentTrack != nil else { return }
        UserDefaults.standard.set(currentTime, forKey: Keys.time)
        lastSavedTime = currentTime
    }

    /// Al abrir la app: recupera la cola, la canción y el minuto (en pausa).
    func restore(from songs: [Song]) {
        guard !restored else { return }
        restored = true
        guard queue.isEmpty else { return }

        let d = UserDefaults.standard
        guard let ids = d.stringArray(forKey: Keys.queue), !ids.isEmpty else { return }
        let savedTime = d.double(forKey: Keys.time)
        let savedIndex = d.integer(forKey: Keys.index)
        let map = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })

        func tracks(from list: [String]) -> [Track] {
            list.compactMap { UUID(uuidString: $0) }.compactMap { map[$0] }.map(Track.init)
        }

        let restoredQueue = tracks(from: ids)
        guard !restoredQueue.isEmpty else { return }
        let currentID = ids.indices.contains(savedIndex) ? UUID(uuidString: ids[savedIndex]) : nil

        queue = restoredQueue
        unshuffled = tracks(from: d.stringArray(forKey: Keys.unshuffled) ?? [])

        if let currentID, let i = restoredQueue.firstIndex(where: { $0.id == currentID }) {
            index = i
            loadCurrent(autoplay: false)
            if savedTime > 1, savedTime < max(duration - 2, 0) {
                seek(to: savedTime)
            }
        } else {
            index = 0
            loadCurrent(autoplay: false)
        }
    }

    // MARK: - Interno

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack else { return }
        player.replaceCurrentItem(with: AVPlayerItem(asset: LibraryManager.preciseAsset(track.url)))
        currentTime = 0
        duration = track.duration
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
        updateNowPlaying()
        saveQueue()
        saveTime()
    }

    private func trackFinished() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            if time.seconds.isFinite { self.currentTime = time.seconds }
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            if self.isPlaying, abs(self.currentTime - self.lastSavedTime) >= 5 {
                self.saveTime()
            }
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.trackFinished() }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.isPlaying = false
                self.updateNowPlaying()
            case .ended:
                if let opt = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: opt).contains(.shouldResume) {
                    self.resume()
                }
            @unknown default: break
            }
        }
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let data = t.artwork, let img = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
