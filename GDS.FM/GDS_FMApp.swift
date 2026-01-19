import SwiftUI

@main
struct GDS_FMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var player = RadioPlayer()
    private var rotationTimer: Timer?
    private var rotationAngle: CGFloat = 0
    private var rotationIncrement: CGFloat = 0
    private var currentRotatingSymbol: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "GDS.FM")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        player.onStateChange = { [weak self] in
            self?.updateIcon()
            self?.buildMenu()
        }

        buildMenu()
        player.play()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            player.togglePlayback()
        }
    }

    private func updateIcon() {
        let showVinyl = PreferencesManager.shared.showVinylIcon

        switch player.state {
        case .stopped:
            stopRotation()
            if showVinyl {
                statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc.fill", accessibilityDescription: "GDS.FM")
            } else {
                statusItem.button?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "GDS.FM")
            }
        case .loading:
            startRotation(symbolName: "circle.dashed", interval: 0.1, increment: -30)
        case .playing:
            if showVinyl {
                startRotation(symbolName: "opticaldisc.fill", interval: 0.05, increment: -3)
            } else {
                stopRotation()
                statusItem.button?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "GDS.FM")
            }
        }
    }

    private func startRotation(symbolName: String, interval: TimeInterval, increment: CGFloat) {
        stopRotation()
        currentRotatingSymbol = symbolName
        rotationIncrement = increment
        rotationAngle = 0
        updateRotatingIcon()

        rotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rotationAngle += self.rotationIncrement
                self.updateRotatingIcon()
            }
        }
    }

    private func updateRotatingIcon() {
        guard let symbolName = currentRotatingSymbol,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "GDS.FM") else {
            return
        }

        let rotatedImage = NSImage(size: image.size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.width / 2, yBy: rect.height / 2)
            transform.rotate(byDegrees: self.rotationAngle)
            transform.translateX(by: -rect.width / 2, yBy: -rect.height / 2)
            transform.concat()
            image.draw(in: rect)
            return true
        }

        rotatedImage.isTemplate = true
        statusItem.button?.image = rotatedImage
    }

    private func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        currentRotatingSymbol = nil
    }

    @discardableResult
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "GDS.FM", action: #selector(openWebsite), keyEquivalent: "")
        headerItem.target = self
        menu.addItem(headerItem)

        menu.addItem(.separator())

        if let showName = player.showName {
            let item = NSMenuItem(title: showName, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if let trackTitle = player.trackTitle, let artistName = player.artistName {
            let item = NSMenuItem(title: "\(artistName) — \(trackTitle)", action: #selector(searchTrack(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["artist": artistName, "track": trackTitle]
            menu.addItem(item)
        } else if let trackTitle = player.trackTitle {
            let item = NSMenuItem(title: trackTitle, action: #selector(searchTrack(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["artist": "", "track": trackTitle]
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let playPauseTitle: String
        switch player.state {
        case .stopped:
            playPauseTitle = "Play"
        case .loading:
            playPauseTitle = "Stop"
        case .playing:
            playPauseTitle = "Pause"
        }

        let playPauseItem = NSMenuItem(
            title: playPauseTitle,
            action: #selector(togglePlayback),
            keyEquivalent: "p"
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        menu.addItem(.separator())

        let settingsMenu = NSMenu()

        // Music Service header
        let musicServiceHeader = NSMenuItem(title: "Music Service", action: nil, keyEquivalent: "")
        musicServiceHeader.isEnabled = false
        settingsMenu.addItem(musicServiceHeader)

        for service in MusicService.allCases {
            let serviceItem = NSMenuItem(
                title: service.displayName,
                action: #selector(selectMusicService(_:)),
                keyEquivalent: ""
            )
            serviceItem.target = self
            serviceItem.representedObject = service
            if service == PreferencesManager.shared.selectedMusicService {
                serviceItem.state = .on
            }
            settingsMenu.addItem(serviceItem)
        }

        settingsMenu.addItem(.separator())

        // Icon settings
        let vinylIconItem = NSMenuItem(
            title: "Show Vinyl Icon",
            action: #selector(toggleVinylIcon(_:)),
            keyEquivalent: ""
        )
        vinylIconItem.target = self
        vinylIconItem.state = PreferencesManager.shared.showVinylIcon ? .on : .off
        settingsMenu.addItem(vinylIconItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func togglePlayback() {
        player.togglePlayback()
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://gds.fm")!)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func searchTrack(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let artist = info["artist"],
              let track = info["track"] else {
            return
        }

        MusicSearchService.openSearch(
            artist: artist,
            track: track,
            service: PreferencesManager.shared.selectedMusicService
        )
    }

    @objc private func selectMusicService(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? MusicService else {
            return
        }

        PreferencesManager.shared.selectedMusicService = service
    }

    @objc private func toggleVinylIcon(_ sender: NSMenuItem) {
        PreferencesManager.shared.showVinylIcon.toggle()
        updateIcon()
    }
}
