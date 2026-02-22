#!/bin/bash

set -euo pipefail

# Constants
FLUTTER_INSTALL_DIR="/opt/flutter"
FLUTTER_REPO="https://github.com/flutter/flutter.git"
FLUTTER_CHANNEL="stable"

source "$(dirname "$0")/flutter-lib.sh"

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
