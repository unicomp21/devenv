#!/bin/bash

set -euo pipefail

# Constants
FLUTTER_INSTALL_DIR="/opt/flutter"
FLUTTER_REPO="https://github.com/flutter/flutter.git"
FLUTTER_CHANNEL="stable"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warn() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

detect_architecture() {
    local arch
    if command -v dpkg >/dev/null 2>&1; then
        arch=$(dpkg --print-architecture)
    elif command -v uname >/dev/null 2>&1; then
        case "$(uname -m)" in
            x86_64) arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *) arch="unknown" ;;
        esac
    else
        arch="unknown"
    fi
    echo "$arch"
}

install_dependencies() {
    log_info "📦 Installing build dependencies..."
    
    local deps=(
        "git" "curl" "unzip" "xz-utils" "zip" "libglu1-mesa"
        "clang" "cmake" "ninja-build" "pkg-config" "libgtk-3-dev"
        "liblzma-dev" "libstdc++-12-dev" "jq"
    )
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y --no-install-recommends "${deps[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum update -y
        yum install -y "${deps[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm "${deps[@]}"
    else
        log_error "❌ Unsupported package manager. Please install dependencies manually."
        exit 1
    fi
}


build_flutter_from_source() {
    log_info "🔨 Building Flutter from source..."
    
    # Clone Flutter repository
    log_info "📥 Cloning Flutter repository..."
    mkdir -p /opt
    
    if [ -d "$FLUTTER_INSTALL_DIR" ]; then
        log_warn "⚠️  Flutter directory already exists. Removing..."
        rm -rf "$FLUTTER_INSTALL_DIR"
    fi
    
    git clone -b "$FLUTTER_CHANNEL" "$FLUTTER_REPO" "$FLUTTER_INSTALL_DIR"
    
    # Set git safe directory
    log_info "🔧 Configuring Flutter..."
    git config --global --add safe.directory "$FLUTTER_INSTALL_DIR"
    
    # Run Flutter's bootstrap script to download Dart SDK and other dependencies
    log_info "📦 Downloading Dart SDK and dependencies..."
    export PUB_CACHE="$FLUTTER_INSTALL_DIR/.pub-cache"
    
    if ! "$FLUTTER_INSTALL_DIR/bin/flutter" --version; then
        log_warn "⚠️  Initial Flutter bootstrap may have failed, continuing..."
    fi
    
    # Pre-populate any required artifacts
    log_info "🏗️  Pre-populating Flutter artifacts..."
    "$FLUTTER_INSTALL_DIR/bin/flutter" precache || true
}


configure_flutter() {
    log_info "⚙️  Configuring Flutter..."
    
    # Add Flutter to PATH in bashrc
    local bashrc_path="$HOME/.bashrc"
    local flutter_path_export="export PATH=\"$FLUTTER_INSTALL_DIR/bin:\$PATH\""
    local dart_path_export="export PATH=\"$FLUTTER_INSTALL_DIR/bin/cache/dart-sdk/bin:\$PATH\""
    
    if [ -f "$bashrc_path" ]; then
        if ! grep -q "$FLUTTER_INSTALL_DIR/bin" "$bashrc_path"; then
            echo "" >> "$bashrc_path"
            echo "# Flutter PATH" >> "$bashrc_path"
            echo "$flutter_path_export" >> "$bashrc_path"
            echo "$dart_path_export" >> "$bashrc_path"
            log_success "✅ Added Flutter to PATH in ~/.bashrc"
        fi
    fi
    
    # Set environment variables for current session
    export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
    export PATH="$FLUTTER_INSTALL_DIR/bin/cache/dart-sdk/bin:$PATH"
    
    # Disable analytics
    "$FLUTTER_INSTALL_DIR/bin/flutter" config --no-analytics
    
    # Enable web support
    "$FLUTTER_INSTALL_DIR/bin/flutter" config --enable-web
    
    # Accept Android licenses (suppress errors on ARM64)
    log_info "📝 Attempting to accept Android licenses..."
    if ! echo "y" | "$FLUTTER_INSTALL_DIR/bin/flutter" doctor --android-licenses 2>/dev/null; then
        log_warn "⚠️  Could not accept Android licenses automatically"
    fi
    
    log_success "✅ Flutter configuration complete"
}

run_flutter_doctor() {
    log_info ""
    log_info "🏥 Running Flutter doctor..."
    log_info ""
    
    "$FLUTTER_INSTALL_DIR/bin/flutter" doctor -v
}

main() {
    log_info "🚀 Starting Flutter installation..."
    log_info ""
    
    local arch
    arch=$(detect_architecture)
    log_info "🖥️  Detected architecture: $arch"
    
    log_info "🏗️  Building Flutter from source"
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
}

# Error handling
trap 'log_error "❌ Flutter installation failed"; exit 1' ERR

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

source ~/.bashrc
dart --disable-analytics
