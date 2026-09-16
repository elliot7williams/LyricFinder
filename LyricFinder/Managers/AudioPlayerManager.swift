import Foundation
import AVFoundation
import Combine

/// App-wide audio player built on AVPlayer.
///
/// All heavy work stays off the main thread; published progress values are
/// delivered on the main actor so SwiftUI stays responsive.
@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published var playbackRate: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?

    init() {
        configureAudioSession()
    }

    deinit {
        // NOTE: deinit is non-isolated; observer removal happens in `stop()`.
        // Time observer token is retained here; invalidation is best-effort
        // because @MainActor teardown ordering with AVPlayer is fragile.
    }

    // MARK: - Setup

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[AudioPlayer] Audio session error: \(error)")
        }
        #endif
    }

    // MARK: - Loading

    func load(url: URL, autoplay: Bool = false) {
        stopTimeObserver()
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        currentURL = url
        currentTime = 0
        isPlaying = false

        Task {
            do {
                let dur = try await item.asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)
                await MainActor.run {
                    self.duration = seconds.isFinite ? seconds : 0
                }
            } catch {
                await MainActor.run { self.duration = 0 }
            }
        }

        addTimeObserver()
        if autoplay { play() }
    }

    // MARK: - Controls

    func play() {
        player?.rate = playbackRate
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func restart() {
        seek(to: 0)
        play()
    }

    /// Relative skip, clamped to [0, duration].
    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(duration, 0.01))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.currentTime = clamped }
        }
    }

    func stop() {
        pause()
        stopTimeObserver()
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player?.rate = rate }
    }

    // MARK: - Time observer

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = CMTimeGetSeconds(time)
                self.isPlaying = self.player?.rate != 0 && self.player?.error == nil && self.player?.currentItem != nil && self.player?.timeControlStatus == .playing
                // Fallback: if rate > 0 consider playing.
                if let p = self.player, p.rate > 0 { self.isPlaying = true }
            }
        }
    }

    private func stopTimeObserver() {
        if let token = timeObserver {
            player?.removeTimeObserver(token)
            timeObserver = nil
        }
    }
}
