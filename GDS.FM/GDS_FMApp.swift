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
        switch player.state {
        case .stopped:
            stopRotation()
            statusItem.button?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "GDS.FM")
        case .loading:
            startRotation()
        case .playing:
            stopRotation()
            statusItem.button?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "GDS.FM")
        }
    }

    private func startRotation() {
        guard rotationTimer == nil else { return }

        rotationAngle = 0
        updateRotatingIcon()

        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rotationAngle -= 30
                self?.updateRotatingIcon()
            }
        }
    }

    private func updateRotatingIcon() {
        guard let image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Loading") else { return }

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
            let item = NSMenuItem(title: "\(artistName) — \(trackTitle)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let trackTitle = player.trackTitle {
            let item = NSMenuItem(title: trackTitle, action: nil, keyEquivalent: "")
            item.isEnabled = false
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
}
