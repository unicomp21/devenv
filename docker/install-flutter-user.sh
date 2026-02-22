#!/bin/bash

set -euo pipefail

# Constants
FLUTTER_INSTALL_DIR="$HOME/flutter"
FLUTTER_REPO="https://github.com/flutter/flutter.git"
FLUTTER_CHANNEL="stable"

source "$(dirname "$0")/flutter-lib.sh"

get_latest_flutter_release() {
    local releases_url="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
    local releases_json

    releases_json=$(curl -s "$releases_url")

    # Parse JSON to find latest stable release for x64
    echo "$releases_json" | jq -r '.releases[] | select(.channel == "stable" and .dart_sdk_arch == "x64") | .archive' | head -1
}

download_flutter_binary() {
    local archive_name="$1"
    local download_url="https://storage.googleapis.com/flutter_infra_release/releases/$archive_name"
    local archive_path="/tmp/flutter.tar.xz"

    log_info "📥 Downloading Flutter from $download_url..."

    curl -L -o "$archive_path" "$download_url"

    log_info "📦 Extracting Flutter SDK..."
    mkdir -p "$FLUTTER_INSTALL_DIR"

    tar -xf "$archive_path" -C "$FLUTTER_INSTALL_DIR" --strip-components=1

    rm -f "$archive_path"
}

main() {
    log_info "🚀 Starting Flutter installation..."
    log_info ""

    local arch
    arch=$(detect_architecture)
    log_info "🖥️  Detected architecture: $arch"

    if [ "$arch" = "arm64" ]; then
        log_info "🏗️  ARM64 detected - will build Flutter from source"
        log_info "⏱️  This process may take 10-20 minutes..."
        log_info ""

        # Install build dependencies
        if [ "$EUID" -eq 0 ]; then
            install_dependencies
        else
            log_warn "⚠️  Not running as root - make sure build dependencies are installed"
        fi

        # Build from source
        build_flutter_from_source
    else
        log_info "📦 x64 detected - will download prebuilt Flutter binary"

        # Check if jq is available for JSON parsing
        if ! command -v jq >/dev/null 2>&1; then
            log_error "❌ jq is required for JSON parsing. Please install jq first."
            exit 1
        fi

        # Get latest Flutter release
        local release_archive
        release_archive=$(get_latest_flutter_release)

        if [ -z "$release_archive" ]; then
            log_error "❌ Could not find stable Flutter release"
            exit 1
        fi

        log_info "📌 Found Flutter release: $release_archive"

        # Download and extract
        download_flutter_binary "$release_archive"
    fi

    # Configure Flutter
    configure_flutter

    # Run Flutter doctor
    run_flutter_doctor

    log_success ""
    log_success "✨ Flutter installation complete!"
    log_success "📍 Flutter installed to: $FLUTTER_INSTALL_DIR"
    log_success "💡 Run 'source ~/.bashrc' or start a new shell to use Flutter"
    log_success "📖 Visit https://flutter.dev/docs to get started"
    log_success ""

    if [ "$arch" = "arm64" ]; then
        log_info "📝 Note: On ARM64 Linux, some Flutter features may have limitations."
        log_info "   The Flutter team is working on improving ARM64 Linux support."
    fi
}

# Error handling
trap 'log_error "❌ Flutter installation failed"; exit 1' ERR

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
