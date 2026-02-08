import SwiftUI

#if !APP_STORE
import AppUpdater
import Version

enum UpdateCheckSource {
    case automatic
    case manual
}
#endif

#if !APP_STORE
import os.log

extension Logger {
    static let appUpdater = Logger(subsystem: "com.gds.fm", category: "AppUpdater")
}
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
    private var rotationTimer: Timer?
    private var rotationAngle: CGFloat = 0
    private var rotationIncrement: CGFloat = 0
    private var currentRotatingSymbol: String?

    #if !APP_STORE
    var updater: AppUpdater?
    var currentCheckSource: UpdateCheckSource?
    private var isInstallingUpdate = false

    func setupAppUpdater() {
        guard let owner = Bundle.main.object(forInfoDictionaryKey: "GitHubOwner") as? String,
              let repo = Bundle.main.object(forInfoDictionaryKey: "GitHubRepo") as? String else {
            Logger.appUpdater.warning("AppUpdater not configured - check Info.plist for GitHubOwner and GitHubRepo")
            return
        }

        let updater = AppUpdater(
            owner: owner,
            repo: repo,
            releasePrefix: "GDS.FM",
            interval: 24 * 60 * 60  // Check every 24 hours
        )

        Logger.appUpdater.info("AppUpdater initialized")

        // Setup download callbacks
        updater.onDownloadSuccess = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, let updater = self.updater else { return }

                Logger.appUpdater.info("✅ Update download completed")

                guard case .downloaded(let release, let asset, let newBundle) = updater.state else {
                    Logger.appUpdater.warning("Download success but state is not .downloaded")
                    return
                }

                // Determine action based on check source
                let checkSource = self.currentCheckSource ?? .automatic
                self.currentCheckSource = nil // Clear

                switch checkSource {
                case .automatic:
                    Logger.appUpdater.info("Automatic update - storing for installation on quit")
                    self.storeDeferredUpdate(release, asset, newBundle)

                case .manual:
                    Logger.appUpdater.info("Manual update - showing dialog")
                    await self.showManualUpdateDialog(release, asset, newBundle)
                }
            }
        }

        updater.onDownloadFail = { error in
            Task { @MainActor in
                Logger.appUpdater.error("❌ Update download failed: \(error)")
            }
        }

        updater.onInstallFail = { error in
            Task { @MainActor in
                Logger.appUpdater.error("❌ Installation failed: \(error)")

                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not install update: \(error)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        self.updater = updater
    }

    private func storeDeferredUpdate(_ release: Release, _ asset: Release.Asset, _ bundle: Bundle) {
        do {
            let persistedURL = try DeferredUpdate.persistBundle(bundle)
            Logger.appUpdater.info("Persisted update bundle to: \(persistedURL.path)")

            let deferredUpdate = DeferredUpdate(
                bundlePath: persistedURL.path,
                releaseVersion: release.tagName.description,
                releaseName: release.name,
                assetName: asset.name
            )

            PreferencesManager.shared.deferredUpdate = deferredUpdate
            Logger.appUpdater.info("Stored deferred update: \(deferredUpdate.releaseVersion)")
        } catch {
            Logger.appUpdater.error("Failed to store deferred update: \(error)")
        }
    }

    private func clearDeferredUpdate() {
        PreferencesManager.shared.deferredUpdate = nil
        DeferredUpdate.cleanup()
        Logger.appUpdater.info("Cleaned up pending updates directory")
    }

    private func validateDeferredUpdate() {
        guard let deferredUpdate = PreferencesManager.shared.deferredUpdate else {
            return
        }

        if !deferredUpdate.isValid {
            Logger.appUpdater.info("Deferred update bundle not found at \(deferredUpdate.bundlePath), clearing")
            clearDeferredUpdate()
        }
    }

    private func showManualUpdateDialog(_ release: Release, _ asset: Release.Asset, _ bundle: Bundle) async {
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = "Version \(release.tagName) is ready to install. Would you like to restart now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart and Update")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Install immediately
            do {
                try await updater?.installThrowing(bundle)
            } catch {
                Logger.appUpdater.error("Failed to install: \(error)")

                let errorAlert = NSAlert()
                errorAlert.messageText = "Installation Failed"
                errorAlert.informativeText = "Could not install update: \(error.localizedDescription)"
                errorAlert.alertStyle = .warning
                errorAlert.addButton(withTitle: "OK")
                errorAlert.runModal()
            }
        } else {
            // Store for later
            Logger.appUpdater.info("User deferred update installation")
            storeDeferredUpdate(release, asset, bundle)
        }
    }

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
        setupAppUpdater()
        validateDeferredUpdate()
        #endif

        Analytics.initialize()
        Analytics.appOpened()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if !APP_STORE
        if let deferredUpdate = PreferencesManager.shared.deferredUpdate {
            guard !isInstallingUpdate else {
                Logger.appUpdater.info("Installation already in progress")
                return .terminateLater
            }

            Logger.appUpdater.info("Installing deferred update on quit: \(deferredUpdate.releaseVersion)")

            guard let bundle = deferredUpdate.loadBundle() else {
                Logger.appUpdater.error("Failed to load deferred bundle at: \(deferredUpdate.bundlePath)")
                clearDeferredUpdate()
                return .terminateNow
            }

            isInstallingUpdate = true

            Task { @MainActor in
                defer { isInstallingUpdate = false }
                do {
                    // Replace bundle without relaunching - user just wants to quit
                    try updater?.replaceBundle(bundle)
                    Logger.appUpdater.info("✅ Update installed on quit")
                    clearDeferredUpdate()
                } catch {
                    Logger.appUpdater.error("Failed to install deferred update: \(error)")
                }
                sender.reply(toApplicationShouldTerminate: true)
            }

            return .terminateLater
        }
        #endif

        return .terminateNow
    }

    #if !APP_STORE
    @objc func checkForUpdates() {
        guard let updater else {
            Logger.appUpdater.warning("⚠️ AppUpdater not initialized - check Info.plist for GitHubOwner and GitHubRepo")
            return
        }

        Logger.appUpdater.info("🔍 Starting manual update check")

        // Clear any existing deferred update
        if PreferencesManager.shared.deferredUpdate != nil {
            Logger.appUpdater.info("Clearing existing deferred update for manual check")
            clearDeferredUpdate()
        }

        // Mark as manual check
        currentCheckSource = .manual

        updater.check(
            success: { [weak self] in
                Task { @MainActor [weak self] in
                    Logger.appUpdater.info("✅ Update downloaded successfully")
                    self?.updater?.onDownloadSuccess?()
                }
            },
            fail: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.currentCheckSource = nil // Clear on failure

                    if let updateError = error as? AppUpdater.Error, case .noValidUpdate = updateError {
                        Logger.appUpdater.info("ℹ️ No updates available")

                        let alert = NSAlert()
                        alert.messageText = "No Updates Available"
                        alert.informativeText = "You're running the latest version of GDS.FM."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    } else {
                        Logger.appUpdater.error("❌ Update check error: \(error)")

                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not check for updates. Please try again later."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        )
    }

    @objc func installDeferredUpdateFromMenu() {
        guard let deferredUpdate = PreferencesManager.shared.deferredUpdate else {
            Logger.appUpdater.warning("No deferred update available")
            return
        }

        guard let bundle = deferredUpdate.loadBundle() else {
            Logger.appUpdater.error("Failed to load deferred bundle")

            let alert = NSAlert()
            alert.messageText = "Installation Failed"
            alert.informativeText = "Could not load the update bundle. The update has been cleared."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

            clearDeferredUpdate()
            return
        }

        Task { @MainActor in
            do {
                Logger.appUpdater.info("Installing update from menu")
                try await updater?.installThrowing(bundle)
            } catch {
                Logger.appUpdater.error("Failed to install from menu: \(error)")

                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not install update: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    #endif

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
        if PreferencesManager.shared.deferredUpdate != nil {
            let installItem = NSMenuItem(
                title: "Install Update & Restart",
                action: #selector(installDeferredUpdateFromMenu),
                keyEquivalent: ""
            )
            installItem.target = self
            menu.addItem(installItem)
        } else {
            let updateItem = NSMenuItem(
                title: "Check for Updates...",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
        }
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
