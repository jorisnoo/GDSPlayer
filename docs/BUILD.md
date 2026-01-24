# Build & Release Guide

This document explains how to build, sign, notarize, and release GDS.FM.

## Prerequisites

- Xcode 15+ with command line tools
- `create-dmg` (install via `brew install create-dmg`)
- Apple Developer ID Application certificate in your keychain
- Apple Developer account for notarization

## One-Time Setup: Notarization Credentials

Store your notarization credentials in the keychain (recommended for local builds):

```bash
xcrun notarytool store-credentials "GDS.FM" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

The password is an app-specific password generated at [appleid.apple.com](https://appleid.apple.com).

## Building Locally

### Build, Sign, and Notarize (Recommended)

```bash
./scripts/build-release.sh
```

### Build Without Notarization (Faster, for Testing)

```bash
./scripts/build-release.sh --build-only
```

### Clean Build With Version Override

```bash
./scripts/build-release.sh --clean --version 1.2.3
```

### Using Environment Variables Instead of Keychain Profile

```bash
APPLE_ID="dev@example.com" \
APPLE_APP_PASSWORD="xxxx-xxxx" \
APPLE_TEAM_ID="YOUR_TEAM_ID" \
./scripts/build-release.sh
```

## Build Script Options

| Option | Description |
|--------|-------------|
| `--build-only` | Build, sign, and package without notarization |
| `--clean` | Remove build artifacts before building |
| `--version X.Y.Z` | Override version (default: read from `version.yml`) |
| `--help` | Show help message |

## Build Artifacts

After a successful build, artifacts are placed in `build/`:

| Artifact | Description |
|----------|-------------|
| `build/GDS.FM.xcarchive/` | Xcode archive |
| `build/export/GDS.FM.app` | Signed application |
| `build/GDS.FM-X.Y.Z.zip` | ZIP archive for Sparkle updates |
| `build/GDS.FM-X.Y.Z.dmg` | DMG for distribution |

## Retrying Notarization

If the build succeeds but notarization fails, use the standalone notarize script:

```bash
./scripts/notarize.sh build/GDS.FM-1.0.0.dmg
```

Or notarize multiple files:

```bash
./scripts/notarize.sh build/GDS.FM-1.0.0.zip build/GDS.FM-1.0.0.dmg
```

---

## Automated Releases (GitHub Actions)

Releases are automated via GitHub Actions. The workflow triggers when you push a version tag.

### Creating a Release

1. Update `CHANGELOG.md` with release notes under a heading like `## 1.2.3`
2. Push the version tag:

```bash
git tag 1.2.3
git push origin 1.2.3
```

### What the Workflow Does

1. Extracts version from the tag
2. Syncs version to Xcode project and commits
3. Builds, signs, and notarizes the app
4. Creates a GitHub Release with the DMG and ZIP
5. Extracts release notes from `CHANGELOG.md`

### Required GitHub Secrets

Configure these secrets in your repository settings:

| Secret | Description |
|--------|-------------|
| `MACOS_CERTIFICATE` | Base64-encoded `.p12` certificate |
| `MACOS_CERTIFICATE_PWD` | Password for the `.p12` file |
| `MACOS_CERTIFICATE_NAME` | Certificate identity (e.g., `Developer ID Application: Your Name (TEAMID)`) |
| `MACOS_CI_KEYCHAIN_PWD` | Password for the temporary CI keychain |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |

### Exporting Your Certificate

```bash
# Export from Keychain Access as .p12, then:
base64 -i Certificates.p12 | pbcopy
# Paste into MACOS_CERTIFICATE secret
```

---

## Troubleshooting

### "Developer ID Application certificate not found"

Make sure your certificate is installed in the login keychain and is valid. Check with:

```bash
security find-identity -v -p codesigning
```

### Notarization Fails With "Invalid Credentials"

Verify your keychain profile is set up correctly:

```bash
xcrun notarytool history --keychain-profile "GDS.FM"
```

### "create-dmg not found"

Install it via Homebrew:

```bash
brew install create-dmg
```
