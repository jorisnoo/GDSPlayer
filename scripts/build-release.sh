#!/bin/bash
set -euo pipefail

# Build, sign, and optionally notarize a macOS app
# This script is the single source of truth for the build process.
# Both local builds and GitHub Actions use this script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

# Load project config
CONFIG_FILE="$PROJECT_ROOT/.build-config"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: .build-config not found. Copy .build-config.example and configure."
    exit 1
fi

# Auto-detect if not specified
XCODE_PROJECT="${XCODE_PROJECT:-$(ls -d "$PROJECT_ROOT"/*.xcodeproj 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "")}"
XCODE_SCHEME="${XCODE_SCHEME:-$APP_NAME}"
NOTARY_PROFILE="${NOTARY_PROFILE:-$APP_NAME}"

# Validate required config
if [[ -z "$APP_NAME" ]]; then
    echo "Error: APP_NAME not set in .build-config"
    exit 1
fi

if [[ -z "$XCODE_PROJECT" ]]; then
    echo "Error: XCODE_PROJECT not set and could not auto-detect *.xcodeproj"
    exit 1
fi

# Default values
BUILD_ONLY=true
CLEAN=false
VERSION=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default notary profile for local builds (used when APPLE_ID is not set)
DEFAULT_NOTARY_PROFILE="$NOTARY_PROFILE"

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build, sign, and optionally notarize $APP_NAME.

Options:
    --notarize      Build, sign, package AND notarize (default: skip notarization)
    --clean         Remove build artifacts before building
    --version X.Y.Z Override version (default: from git tag)
    --help          Show this help message

Environment Variables (for notarization):
    NOTARY_PROFILE      Keychain profile name (recommended for local builds)

    Or use these three together:
    APPLE_ID            Apple ID email for notarization
    APPLE_APP_PASSWORD  App-specific password
    APPLE_TEAM_ID       Developer Team ID

    Optional:
    MACOS_CERTIFICATE_NAME  Certificate identity (default: "Developer ID Application")

Examples:
    # Build only (no notarization) - this is the default
    ./scripts/build-release.sh

    # Full build with notarization using keychain profile
    NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/build-release.sh --notarize

    # Full build with notarization using env vars (same as CI)
    APPLE_ID="dev@example.com" \\
    APPLE_APP_PASSWORD="xxxx-xxxx" \\
    APPLE_TEAM_ID="T84UJ8Z67C" \\
    ./scripts/build-release.sh --notarize

    # Clean build with version override and notarization (used by CI)
    ./scripts/build-release.sh --clean --notarize --version 1.0.0

One-time setup for keychain profile:
    xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
        --apple-id "your@email.com" \\
        --team-id "YOUR_TEAM_ID" \\
        --password "xxxx-xxxx-xxxx-xxxx"
EOF
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check xcodebuild
    if ! command -v xcodebuild &> /dev/null; then
        log_error "xcodebuild not found. Please install Xcode command line tools."
        exit 1
    fi

    # Check create-dmg
    if ! command -v create-dmg &> /dev/null; then
        log_error "create-dmg not found. Install with: brew install create-dmg"
        exit 1
    fi

    # Check for Developer ID certificate
    local cert_name="${MACOS_CERTIFICATE_NAME:-Developer ID Application}"
    if ! security find-identity -v -p codesigning | grep -q "$cert_name"; then
        log_error "Developer ID Application certificate not found in keychain."
        log_error "Make sure your signing certificate is installed."
        exit 1
    fi

    log_info "All prerequisites satisfied."
}

check_notarization_credentials() {
    # Prefer explicit Apple ID credentials (used by CI)
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        log_info "Using Apple ID credentials for notarization"
        return 0
    fi

    # Fall back to keychain profile (local builds)
    NOTARY_PROFILE="${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
    log_info "Using keychain profile: $NOTARY_PROFILE"
    return 0
}

get_version() {
    if [ -n "$VERSION" ]; then
        echo "$VERSION"
        return
    fi

    # Use git describe for version from tags
    local git_version
    git_version=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -n "$git_version" ]; then
        echo "$git_version"
        return
    fi

    log_error "No version found. Use --version or create a git tag"
    exit 1
}

clean_build() {
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    log_info "Build directory cleaned."
}

build_archive() {
    local version="$1"
    local team_id="${APPLE_TEAM_ID:-}"
    local cert_name="${MACOS_CERTIFICATE_NAME:-Developer ID Application}"

    log_info "Building and archiving..."

    # If APPLE_TEAM_ID is not set, try to extract from certificate
    if [ -z "$team_id" ]; then
        team_id=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')
        if [ -z "$team_id" ]; then
            log_error "Could not determine APPLE_TEAM_ID. Please set it explicitly."
            exit 1
        fi
        log_info "Using team ID from certificate: $team_id"
    fi

    xcodebuild archive \
        -project "$PROJECT_ROOT/$XCODE_PROJECT" \
        -scheme "$XCODE_SCHEME" \
        -configuration Release \
        -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$cert_name" \
        DEVELOPMENT_TEAM="$team_id" \
        MARKETING_VERSION="$version"

    log_info "Archive created successfully."
}

export_app() {
    local team_id="${APPLE_TEAM_ID:-}"

    # If APPLE_TEAM_ID is not set, try to extract from certificate
    if [ -z "$team_id" ]; then
        team_id=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')
    fi

    log_info "Exporting app..."

    # Create ExportOptions.plist
    cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$team_id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -exportPath "$BUILD_DIR/export"

    log_info "App exported successfully."
}

create_zip() {
    local version="$1"
    local zip_path="$BUILD_DIR/$APP_NAME-$version.zip"

    log_info "Creating ZIP archive..."

    cd "$BUILD_DIR/export"
    ditto -c -k --keepParent "$APP_NAME.app" "$zip_path"

    log_info "ZIP created: $zip_path"
}

create_dmg() {
    local version="$1"
    local dmg_path="$BUILD_DIR/$APP_NAME-$version.dmg"

    log_info "Creating DMG..."

    # Remove existing DMG if present (create-dmg fails otherwise)
    rm -f "$dmg_path"

    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "$APP_NAME.app" \
        "$dmg_path" \
        "$BUILD_DIR/export/$APP_NAME.app"

    log_info "DMG created: $dmg_path"
}

sign_dmg() {
    local version="$1"
    local dmg_path="$BUILD_DIR/$APP_NAME-$version.dmg"
    local cert_name="${MACOS_CERTIFICATE_NAME:-Developer ID Application}"

    log_info "Signing DMG..."
    codesign --force --sign "$cert_name" "$dmg_path"
    log_info "DMG signed successfully."
}

notarize_file() {
    local file_path="$1"

    log_info "Notarizing: $file_path"

    # Prefer explicit Apple ID credentials (used by CI)
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        xcrun notarytool submit "$file_path" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait
    else
        xcrun notarytool submit "$file_path" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
    fi

    log_info "Notarization complete for: $file_path"
}

staple_app() {
    log_info "Stapling notarization ticket to app..."
    xcrun stapler staple "$BUILD_DIR/export/$APP_NAME.app"
    log_info "App stapled successfully."
}

staple_dmg() {
    local version="$1"
    local dmg_path="$BUILD_DIR/$APP_NAME-$version.dmg"

    log_info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$dmg_path"
    log_info "DMG stapled successfully."
}

verify_notarization() {
    local version="$1"
    local dmg_path="$BUILD_DIR/$APP_NAME-$version.dmg"

    log_info "Verifying notarization..."
    spctl -a -vvv -t install "$dmg_path"
    log_info "Notarization verified successfully."
}

print_summary() {
    local version="$1"
    local notarized="$2"

    echo ""
    echo "========================================"
    echo "Build Summary"
    echo "========================================"
    echo "App:          $APP_NAME"
    echo "Version:      $version"
    echo "Build Dir:    $BUILD_DIR"
    echo ""
    echo "Artifacts:"
    echo "  - $BUILD_DIR/$APP_NAME.xcarchive/"
    echo "  - $BUILD_DIR/export/$APP_NAME.app"
    echo "  - $BUILD_DIR/$APP_NAME-$version.zip"
    echo "  - $BUILD_DIR/$APP_NAME-$version.dmg"
    echo ""
    if [ "$notarized" = "true" ]; then
        echo "Status: Notarized and stapled"
    else
        echo "Status: Built and signed (not notarized)"
    fi
    echo "========================================"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --notarize)
            BUILD_ONLY=false
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting $APP_NAME build process..."

    # Check prerequisites
    check_prerequisites

    # Check notarization credentials if needed
    if [ "$BUILD_ONLY" = false ]; then
        check_notarization_credentials
    fi

    # Get version
    local version
    version=$(get_version)
    log_info "Building version: $version"

    # Clean if requested
    if [ "$CLEAN" = true ]; then
        clean_build
    fi

    # Create build directory
    mkdir -p "$BUILD_DIR"

    # Build and archive
    build_archive "$version"

    # Export app
    export_app

    # Create ZIP
    create_zip "$version"

    # Notarize if not build-only
    if [ "$BUILD_ONLY" = false ]; then
        # Notarize ZIP
        notarize_file "$BUILD_DIR/$APP_NAME-$version.zip"

        # Staple app
        staple_app

        # Recreate ZIP with stapled app
        log_info "Recreating ZIP with stapled app..."
        rm "$BUILD_DIR/$APP_NAME-$version.zip"
        create_zip "$version"

        # Create DMG with stapled app
        create_dmg "$version"

        # Sign the DMG
        sign_dmg "$version"

        # Notarize DMG
        notarize_file "$BUILD_DIR/$APP_NAME-$version.dmg"

        # Staple DMG
        staple_dmg "$version"

        # Re-sign DMG after stapling (stapling modifies the file)
        sign_dmg "$version"

        # Verify
        verify_notarization "$version"

        print_summary "$version" "true"
    else
        # For build-only, create DMG without signing/notarization
        create_dmg "$version"
        print_summary "$version" "false"
    fi

    log_info "Build complete!"
}

main
