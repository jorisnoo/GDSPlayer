import AppKit
import AVFoundation
import Foundation
import MediaPlayer
import Network

private extension String {
    var decodingHTMLEntities: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              )
        else { return self }
        return attributed.string
    }
}

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
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemNotificationObservers: [NSObjectProtocol] = []
    private var mediaKeyMonitor: Any?

    private let pathMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var desiresPlayback = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

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
        setupRemoteCommandCenter()
        setupMediaKeyMonitor()
        startNetworkMonitor()
    }

    deinit {
        pathMonitor.cancel()
        reconnectTask?.cancel()
    }

    private func setupMediaKeyMonitor() {
        mediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }

            let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
            let keyFlags = (event.data1 & 0x0000FFFF)
            let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA

            // Only respond on key down
            guard keyState else { return }

            Task { @MainActor [weak self] in
                switch keyCode {
                case 16: // Play/Pause
                    self?.togglePlayback()
                case 19: // Next (optional)
                    break
                case 20: // Previous (optional)
                    break
                default:
                    break
                }
            }
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayback()
            }
            return .success
        }

        // Disable unused commands
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = trackTitle ?? "GDS.FM"
        info[MPMediaItemPropertyArtist] = artistName ?? showName ?? "Live Radio"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true

        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.nowPlayingInfo = info
        nowPlayingCenter.playbackState = .playing
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
        desiresPlayback = true
        reconnectAttempt = 0
        startStream()
        Analytics.playbackStarted()
    }

    func pause() {
        desiresPlayback = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        teardownStream()
        state = .stopped
        onStateChange?()
        Analytics.playbackStopped()

        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.playbackState = .stopped
        nowPlayingCenter.nowPlayingInfo = nil
    }

    private func startStream() {
        teardownStream()

        let playerItem = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        observePlaybackStatus(on: player)
        observeItem(playerItem)

        state = .loading
        onStateChange?()
        player.play()
        updateNowPlayingInfo()
    }

    private func teardownStream() {
        player?.pause()
        player = nil
        timeControlStatusObserver = nil
        itemStatusObserver = nil
        itemNotificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotificationObservers = []
    }

    private func observePlaybackStatus(on player: AVPlayer) {
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch player.timeControlStatus {
                case .playing:
                    self.reconnectAttempt = 0
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

    private func observeItem(_ item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, item.status == .failed else { return }
                self.handleStreamFailure()
            }
        }

        let center = NotificationCenter.default
        let stalled = center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = .loading
                self.onStateChange?()
            }
        }
        let failed = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleStreamFailure()
            }
        }
        itemNotificationObservers = [stalled, failed]
    }

    private func handleStreamFailure() {
        guard desiresPlayback else { return }
        teardownStream()
        state = .loading
        onStateChange?()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard desiresPlayback else { return }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30.0)

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  self.desiresPlayback,
                  self.isNetworkAvailable
            else { return }
            self.startStream()
        }
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleNetworkChange(isAvailable: available)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.gds.fm.network-monitor"))
    }

    private func handleNetworkChange(isAvailable: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = isAvailable

        guard desiresPlayback else { return }

        if !isAvailable, wasAvailable {
            reconnectTask?.cancel()
            teardownStream()
            state = .loading
            onStateChange?()
        } else if isAvailable, !wasAvailable {
            reconnectAttempt = 0
            startStream()
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

            let current = liveInfo.tracks.current?.artistAndTitle
            showName = liveInfo.shows.current?.name
            artistName = current?.artist?.decodingHTMLEntities
            trackTitle = current?.title?.decodingHTMLEntities
            onStateChange?()

            if state == .playing {
                updateNowPlayingInfo()
            }
        } catch {
            print("Failed to fetch track info: \(error)")
        }
    }
}
