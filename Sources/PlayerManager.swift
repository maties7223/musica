import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
final class PlayerManager {
    static let shared = PlayerManager()

    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    var currentTrack: Track? { queue.indices.contains(index) ? queue[index] : nil }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?

    private init() {
        configureSession()
        configureRemoteCommands()
        observeTime()
        observeNotifications()
    }

    // MARK: - Control

    func play(_ songs: [Song], startAt start: Int = 0) {
        guard songs.indices.contains(start) else { return }
        queue = songs.map(Track.init)
        index = start
        loadCurrent(autoplay: true)
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
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
            loadCurrent(autoplay: true)
        } else {
            index = 0
            loadCurrent(autoplay: false)
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
    }

    /// Llamar antes de borrar una canción.
    func remove(id: UUID) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        if i == index {
            player.pause()
            player.replaceCurrentItem(with: nil)
            queue = []
            index = 0
            isPlaying = false
            currentTime = 0
            duration = 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        } else {
            queue.remove(at: i)
            if i < index { index -= 1 }
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
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.next() }

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
