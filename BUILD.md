# Build Guide for GDS.FM

This document explains how to build GDS.FM for different distribution channels.

## Overview

GDS.FM supports two distribution channels:

1. **GitHub Distribution** - Non-sandboxed with AppUpdater for silent auto-updates
2. **App Store Distribution** - Sandboxed without AppUpdater

## Build Configurations

The project has four build configurations:

| Configuration    | Purpose               | Sandbox | AppUpdater | Entitlements                    |
|------------------|-----------------------|---------|------------|---------------------------------|
| Debug            | GitHub development    | NO      | Yes        | GDSPlayer.entitlements          |
| Release          | GitHub production     | NO      | Yes        | GDSPlayer.entitlements          |
| AppStore Debug   | App Store development | YES     | No         | GDSPlayer-AppStore.entitlements |
| AppStore Release | App Store production  | YES     | No         | GDSPlayer-AppStore.entitlements |

## Prerequisites

### Required Tools

- Xcode 15 or later
- `create-dmg` for creating disk images:
  ```bash
  brew install create-dmg
  ```

### Code Signing Certificates

For GitHub distribution:
- **Developer ID Application** certificate for code signing
- **Developer ID Installer** certificate (optional, for PKG installers)

For App Store distribution:
- **Mac App Distribution** certificate
- **Mac Installer Distribution** certificate (for App Store submission)

### Notarization Setup

For local builds with notarisation, store your credentials in the keychain:

```bash
xcrun notarytool store-credentials "GDSPlayer" \
    --apple-id "your@email.com" \
    --team-id "T84UJ8Z67C" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

## Building for GitHub Distribution

GitHub distribution builds are non-sandboxed and include AppUpdater for automatic silent updates.

### Local Build (No Notarization)

```bash
./scripts/build-release.sh
```

This creates:
- `build/GDSPlayer.xcarchive/` - Archive
- `build/export/GDS.FM.app` - Signed app bundle
- `build/GDS.FM-{version}.zip` - ZIP archive (for AppUpdater)
- `build/GDS.FM-{version}.dmg` - DMG installer (for manual downloads)

### Local Build with Notarization

Using keychain profile:
```bash
NOTARY_PROFILE="GDSPlayer" ./scripts/build-release.sh --notarise
```

Using environment variables:
```bash
APPLE_ID="dev@example.com" \
APPLE_APP_PASSWORD="xxxx-xxxx" \
APPLE_TEAM_ID="T84UJ8Z67C" \
./scripts/build-release.sh --notarise
```

### Clean Build with Custom Version

```bash
./scripts/build-release.sh --clean --notarise --version 1.2.3
```

### GitHub Actions Automated Build

GitHub Actions automatically builds and notarizes on tag push:

```bash
git tag 1.2.3
git push origin 1.2.3
```

The workflow:
1. Builds with `Release` configuration
2. Signs with Developer ID Application certificate
3. Notarizes both ZIP and DMG
4. Creates GitHub release
5. Uploads `GDS.FM-1.2.3.zip` and `GDS.FM-1.2.3.dmg`

## Building for App Store

App Store builds are sandboxed and exclude AppUpdater.

### Local Build

```bash
./scripts/build-appstore.sh --clean --version 1.2.3
```

This uses the `AppStore Release` configuration which:
- Enables sandbox via `GDSPlayer-AppStore.entitlements`
- Defines `APP_STORE` compilation flag (excludes AppUpdater)
- Uses App Store code signing

### Export for App Store Submission

After building, submit via Xcode:

1. Open Xcode
2. Window → Organizer
3. Select the archive
4. Click "Distribute App"
5. Choose "App Store Connect"
6. Follow the upload wizard

Or use command line:
```bash
xcrun altool --upload-app \
    --type macos \
    --file "build/GDS.FM-1.2.3.pkg" \
    --username "your@email.com" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

## AppUpdater Configuration

### Release Asset Naming

AppUpdater requires assets to be named exactly:

```
GDS.FM-{version}.zip
GDS.FM-{version}.dmg
```

The build scripts and GitHub Actions are configured to use the correct naming.

### Update Behavior

GitHub distribution builds check for updates every 24 hours:

1. Background check runs automatically
2. If update found, downloads silently
3. Installs automatically on download completion
4. User can also manually check via "Check for Updates" menu item
5. Update applies on next app launch

### Update Validation

AppUpdater validates:
- Assets are downloaded from GitHub releases only
- Code-signing identity matches current installation
- Version numbers (semantic versioning)

## Build Script Options

### build-release.sh

```bash
./scripts/build-release.sh [OPTIONS]

Options:
  --notarise               Build, sign, package AND notarise
  --clean                  Remove build artifacts before building
  --version X.Y.Z          Override version (default: from git tag)
  --configuration CONFIG   Build configuration (default: Release)
                          Options: Debug, Release, AppStore Debug, AppStore Release
  --help                   Show help message
```

### build-appstore.sh

Wrapper script that calls `build-release.sh` with `--configuration "AppStore Release"`.

```bash
./scripts/build-appstore.sh [OPTIONS]

Accepts same options as build-release.sh except --configuration
```

## Troubleshooting

### AppUpdater Not Finding Updates

Check these common issues:

1. **Asset naming** - Must be exactly `GDS.FM-{version}.zip`
2. **releasePrefix** - Code uses `"GDS.FM"` in `GDSPlayerApp.swift:48`
3. **Version format** - Must use semantic versioning (X.Y.Z)
4. **GitHub URL** - Check `Info.plist` for correct `GitHubOwner` and `GitHubRepo`
5. **Code signing** - Update must be signed with same Developer ID

### Notarization Fails

Common causes:
- Invalid credentials or expired app-specific password
- Certificate not in keychain
- App not properly code-signed
- Missing hardened runtime entitlements

Check notarization log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "GDSPlayer"
```

### Sandbox Issues

If app doesn't work in sandbox:
- Check entitlements in `GDSPlayer-AppStore.entitlements`
- Verify network client entitlement is present
- Test with AppStore Debug configuration first

## Key Differences Between Distributions

| Aspect              | GitHub Distribution      | App Store Distribution          |
|---------------------|--------------------------|---------------------------------|
| Build Config        | Debug/Release            | AppStore Debug/Release          |
| Entitlements        | GDSPlayer.entitlements   | GDSPlayer-AppStore.entitlements |
| Sandbox             | NO                       | YES                             |
| APP_STORE Flag      | Not defined              | Defined                         |
| AppUpdater          | Compiled in, active      | Compiled out                    |
| Auto-updates        | Silent install every 24h | Not available                   |
| Code Signing        | Developer ID             | App Store                       |
| Distribution        | DMG + GitHub releases    | App Store only                  |
| "Check for Updates" | Menu item visible        | Menu item hidden                |

## Security Considerations

- AppUpdater validates code-signing identity
- Downloads only from authenticated GitHub releases
- Sandbox prevents App Store builds from self-updating
- Silent install only works for non-sandboxed builds
- All builds require proper code signing

## Release Checklist

### For GitHub Release

- [ ] Update version in git tag
- [ ] Update CHANGELOG.md
- [ ] Push tag to GitHub
- [ ] Wait for GitHub Actions to complete
- [ ] Verify assets named correctly (`GDS.FM-*.zip` and `GDS.FM-*.dmg`)
- [ ] Test auto-update on previous version
- [ ] Verify DMG works for manual installation

### For App Store Release

- [ ] Build with `./scripts/build-appstore.sh`
- [ ] Test in sandboxed environment
- [ ] Verify AppUpdater not present (`nm -g` output)
- [ ] Submit via Xcode Organizer
- [ ] Wait for App Store review
- [ ] Monitor crash reports and feedback

## Environment Variables

### For Notarization

```bash
# Option 1: Keychain profile (recommended for local builds)
NOTARY_PROFILE="GDSPlayer"

# Option 2: Direct credentials (used by CI)
APPLE_ID="dev@example.com"
APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
APPLE_TEAM_ID="T84UJ8Z67C"
```

### For Code Signing

```bash
# Override certificate name
MACOS_CERTIFICATE_NAME="Developer ID Application: Your Name (TEAMID)"
```

## Additional Resources

- [Apple Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Sandbox Documentation](https://developer.apple.com/documentation/security/app_sandbox)
- [AppUpdater GitHub Repository](https://github.com/jorisnoo/AppUpdater)
- [Code Signing Guide](https://developer.apple.com/support/code-signing/)
