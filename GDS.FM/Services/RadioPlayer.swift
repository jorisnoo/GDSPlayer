import AVFoundation
import Foundation

enum PlaybackState {
    case stopped
    case loading
    case playing
}

@MainActor
final class RadioPlayer {
    private let streamURL = URL(string: "https://gdsfm.out.airtime.pro/gdsfm_a")!
    private let apiURL = URL(string: "https://gdsfm.airtime.pro/api/live-info-v2?timezone=utc")!

    private var player: AVPlayer?
    private var pollingTimer: Timer?
    private var timeControlStatusObserver: NSKeyValueObservation?

    private(set) var state: PlaybackState = .stopped
    private(set) var showName: String?
    private(set) var artistName: String?
    private(set) var trackTitle: String?

    var onStateChange: (() -> Void)?

    init() {
        Task {
            await fetchTrackInfo()
        }
        startPolling()
    }

    func togglePlayback() {
        switch state {
        case .stopped:
            play()
        case .loading, .playing:
            pause()
        }
    }

    func play() {
        if player == nil {
            let playerItem = AVPlayerItem(url: streamURL)
            player = AVPlayer(playerItem: playerItem)
            observePlaybackStatus()
        }

        state = .loading
        onStateChange?()
        player?.play()
    }

    func pause() {
        player?.pause()
        player = nil
        timeControlStatusObserver = nil
        state = .stopped
        onStateChange?()
    }

    private func observePlaybackStatus() {
        timeControlStatusObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch player.timeControlStatus {
                case .playing:
                    self.state = .playing
                    self.onStateChange?()
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
                    self.onStateChange?()
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchTrackInfo()
            }
        }
    }

    private func fetchTrackInfo() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            let liveInfo = try JSONDecoder().decode(LiveInfo.self, from: data)

            showName = liveInfo.shows.current?.name
            artistName = liveInfo.tracks.current?.metadata?.artistName
            trackTitle = liveInfo.tracks.current?.metadata?.trackTitle
            onStateChange?()
        } catch {
            print("Failed to fetch track info: \(error)")
        }
    }
}
