import AppKit
import AVFoundation
import Foundation
import MediaPlayer

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
    private var mediaKeyMonitor: Any?

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
        if player == nil {
            let playerItem = AVPlayerItem(url: streamURL)
            player = AVPlayer(playerItem: playerItem)
            observePlaybackStatus()
        }

        state = .loading
        onStateChange?()
        player?.play()
        updateNowPlayingInfo()
        Analytics.playbackStarted()
    }

    func pause() {
        player?.pause()
        player = nil
        timeControlStatusObserver = nil
        state = .stopped
        onStateChange?()
        Analytics.playbackStopped()

        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.playbackState = .stopped
        nowPlayingCenter.nowPlayingInfo = nil
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
            artistName = liveInfo.tracks.current?.metadata?.artistName?.decodingHTMLEntities
            trackTitle = liveInfo.tracks.current?.metadata?.trackTitle?.decodingHTMLEntities
            onStateChange?()

            if state == .playing {
                updateNowPlayingInfo()
            }
        } catch {
            print("Failed to fetch track info: \(error)")
        }
    }
}
