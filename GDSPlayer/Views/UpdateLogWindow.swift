import SwiftUI
import UniformTypeIdentifiers

#if !APP_STORE
import AppUpdater
import Version
#endif

struct UpdateLogWindow: View {
    #if !APP_STORE
    @ObservedObject var updater: AppUpdater
    #endif

    var body: some View {
        #if !APP_STORE
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AppUpdater Status")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task {
                        do {
                            try await updater.checkThrowing()
                        } catch {
                            // Error will be shown in Last Error section
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current State Section
                    GroupBox {
                        stateView
                    } label: {
                        Text("Current State")
                            .font(.headline)
                    }

                    // Available Releases Section
                    GroupBox {
                        releasesView
                    } label: {
                        Text("Available Releases")
                            .font(.headline)
                    }

                    // Last Error Section
                    if let lastError = updater.lastError {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lastError.localizedDescription)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Last Error", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("Check for Updates") {
                    Task {
                        do {
                            try await updater.checkThrowing()
                        } catch {
                            // Error will be shown in Last Error section
                        }
                    }
                }

                Button("Copy State Info") {
                    copyStateInfo()
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 500)
        #else
        EmptyView()
        #endif
    }

    #if !APP_STORE
    @ViewBuilder
    private var stateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch updater.state {
            case .none:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No updates available")
                }

            case .newVersionDetected(let release, let asset):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Update found: \(release.tagName.description)")
                            .font(.headline)
                    }
                    Text("Asset: \(asset.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Release: \(release.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .downloading(let release, _, let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Downloading: \(release.tagName.description)")
                            .font(.headline)
                    }
                    ProgressView(value: fraction) {
                        HStack {
                            Text("\(Int(fraction * 100))%")
                                .font(.caption)
                            Spacer()
                        }
                    }
                }

            case .downloaded(let release, let asset, _):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Downloaded: \(release.tagName.description)")
                            .font(.headline)
                    }
                    Text("Asset: \(asset.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Ready to install")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    @ViewBuilder
    private var releasesView: some View {
        if updater.releases.isEmpty {
            Text("No releases fetched yet. Click 'Check for Updates' to fetch releases.")
                .foregroundColor(.secondary)
                .padding(8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(updater.releases.enumerated()), id: \.offset) { index, release in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(release.tagName.description)
                                .font(.headline)
                            Spacer()
                            if release.prerelease {
                                Text("Pre-release")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(release.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !release.body.isEmpty {
                            Text(release.body)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(8)

                    if index < updater.releases.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func copyStateInfo() {
        var info = "AppUpdater Status\n"
        info += "=================\n\n"

        info += "Current State:\n"
        switch updater.state {
        case .none:
            info += "  No updates available\n"
        case .newVersionDetected(let release, let asset):
            info += "  Update found: \(release.tagName.description)\n"
            info += "  Asset: \(asset.name)\n"
            info += "  Release: \(release.name)\n"
        case .downloading(let release, _, let fraction):
            info += "  Downloading: \(release.tagName.description)\n"
            info += "  Progress: \(Int(fraction * 100))%\n"
        case .downloaded(let release, let asset, _):
            info += "  Downloaded: \(release.tagName.description)\n"
            info += "  Asset: \(asset.name)\n"
            info += "  Ready to install\n"
        }

        info += "\nAvailable Releases:\n"
        if updater.releases.isEmpty {
            info += "  No releases fetched yet\n"
        } else {
            for release in updater.releases {
                info += "  - \(release.tagName.description)"
                if release.prerelease {
                    info += " (pre-release)"
                }
                info += "\n"
            }
        }

        if let lastError = updater.lastError {
            info += "\nLast Error:\n"
            info += "  \(lastError.localizedDescription)\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
    #endif

}
