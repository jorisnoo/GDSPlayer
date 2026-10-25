import SwiftUI

#if !APP_STORE
import AppUpdater
#endif

@main
struct GDSPlayerApp: App {
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
    private var heartbeatTimer: Timer?
    private var rotationTimer: Timer?
    private var rotationAngle: CGFloat = 0
    private var rotationIncrement: CGFloat = 0
    private var currentRotatingSymbol: String?

    #if !APP_STORE
    let updates = AppUpdateController(owner: "jorisnoo", repo: "GDSPlayer", releasePrefix: "GDS.FM")
    #endif

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
            self?.updateTooltip()
            self?.buildMenu()
        }

        buildMenu()
        player.play()

        #if !APP_STORE
        updates.start()
        #endif

        Analytics.initialize()
        Analytics.appOpened()
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in
                Analytics.heartbeat()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if !APP_STORE
        let reply = updates.applicationShouldTerminate(sender)
        guard reply == .terminateNow else {
            // AppUpdater replies itself once the update is installed.
            if reply == .terminateLater { Task { await Analytics.appClosed() } }
            return reply
        }
        #endif

        // Quit only after app_closed has been sent, or the request dies with the process.
        Task {
            await Analytics.appClosed()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        let clickToPlay = PreferencesManager.shared.clickToPlay
        let isMenuClick = clickToPlay ? event.type == .rightMouseUp : event.type == .leftMouseUp

        if isMenuClick {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            player.togglePlayback()
        }
    }

    private func updateTooltip() {
        switch player.state {
        case .stopped:
            statusItem.button?.toolTip = nil
        case .loading, .playing:
            if let artistName = player.artistName, let trackTitle = player.trackTitle {
                statusItem.button?.toolTip = "\(artistName) — \(trackTitle)"
            } else {
                statusItem.button?.toolTip = "GDS.FM"
            }
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

        settingsMenu.addItem(.separator())

        let clickToPlay = PreferencesManager.shared.clickToPlay

        let clickToPlayItem = NSMenuItem(
            title: "Click to Play/Pause",
            action: #selector(selectClickAction(_:)),
            keyEquivalent: ""
        )
        clickToPlayItem.target = self
        clickToPlayItem.representedObject = true
        clickToPlayItem.state = clickToPlay ? .on : .off
        settingsMenu.addItem(clickToPlayItem)

        let clickToMenuItem = NSMenuItem(
            title: "Click to Open Menu",
            action: #selector(selectClickAction(_:)),
            keyEquivalent: ""
        )
        clickToMenuItem.target = self
        clickToMenuItem.representedObject = false
        clickToMenuItem.state = clickToPlay ? .off : .on
        settingsMenu.addItem(clickToMenuItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        #if !APP_STORE
        for item in updates.menuItems() { menu.addItem(item) }
        #endif

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func togglePlayback() {
        player.togglePlayback()
    }

    @objc private func openWebsite() {
        let url = "https://gds.fm"
        Analytics.outboundLinkClick(url: url)
        NSWorkspace.shared.open(URL(string: url)!)
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

        if let url = MusicSearchService.openSearch(
            artist: artist,
            track: track,
            service: PreferencesManager.shared.selectedMusicService
        ) {
            Analytics.outboundLinkClick(url: url)
        }
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

    @objc private func selectClickAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Bool else { return }

        PreferencesManager.shared.clickToPlay = value
    }
}
