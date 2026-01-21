#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DENO_REPO="https://github.com/denoland/deno.git"
BUILD_DIR="/tmp/deno-build-$$"
INSTALL_DIR="${DENO_INSTALL:-$HOME/.deno}"
INSTALL_BIN="$INSTALL_DIR/bin"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verbose logging functions
log_verbose() {
    if [ "${VERBOSE:-false}" = "true" ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

log_build_progress() {
    if [ "${VERBOSE:-false}" = "true" ]; then
        echo -e "${GREEN}[BUILD]${NC} $1"
    else
        echo -n "."
    fi
}

# Function to run command with optional verbose output
run_with_progress() {
    local cmd="$1"
    local log_file="$2"
    local description="$3"
    
    if [ "${VERBOSE:-false}" = "true" ]; then
        log_info "Running: $description"
        log_verbose "Command: $cmd"
        echo -e "${BLUE}--- Build Output Start ---${NC}"
        if eval "$cmd" 2>&1 | tee "$log_file"; then
            echo -e "${BLUE}--- Build Output End ---${NC}"
            return 0
        else
            echo -e "${RED}--- Build Failed ---${NC}"
            return 1
        fi
    else
        log_info "$description (use --verbose to see build output)"
        echo -n "Progress: "
        if eval "$cmd" > "$log_file" 2>&1; then
            echo " ✅"
            return 0
        else
            echo " ❌"
            return 1
        fi
    fi
}

# Function to show build progress for long operations
show_progress_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    if [ "${VERBOSE:-false}" != "true" ]; then
        while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
            local temp=${spinstr#?}
            printf " [%c]  " "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
        printf "    \b\b\b\b"
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command_exists cargo; then
        missing_deps+=("cargo (Rust)")
    fi
    
    if ! command_exists git; then
        missing_deps+=("git")
    fi
    
    if ! command_exists protoc; then
        missing_deps+=("protobuf-compiler")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo
        echo "To install missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install -y git protobuf-compiler"
        echo "  macOS:         brew install git protobuf"
        echo "  Rust:          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        return 1
    fi
    
    log_success "All dependencies found"
}

# Function to cleanup on exit
cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Build Deno from source with intelligent version selection"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --dir DIR       Set custom installation directory (default: ~/.deno)"
    echo "  -b, --branch BRANCH Build from specific branch/tag (default: auto-select stable)"
    echo "  -j, --jobs N        Number of parallel jobs for building (default: auto)"
    echo "  --clean             Clean existing installation first"
    echo "  --force-main        Force building from main branch (may be unstable)"
    echo "  -v, --verbose       Show verbose build output in real-time"
    echo "  --quiet             Suppress most output (opposite of verbose)"
    echo
    echo "Notes:"
    echo "  - By default, automatically tries multiple stable releases until one builds successfully"
    echo "  - Detects dependency conflicts and automatically tries older stable versions"
    echo "  - Use --force-main or --branch main to build from the development branch"
    echo "  - Use --branch <version> to force building a specific version"
    echo "  - Tries building with locked dependencies first for better stability"
    echo "  - Use --verbose to see real-time build progress and compiler output"
    echo
    echo "Auto-selection behavior:"
    echo "  - Tries latest stable release first"
    echo "  - Falls back to recent stable releases if dependency conflicts occur"
    echo "  - Includes hardcoded known-working versions as last resort"
    echo
    echo "Environment variables:"
    echo "  DENO_INSTALL        Installation directory (default: ~/.deno)"
    echo "  CARGO_BUILD_JOBS    Number of parallel build jobs"
    echo "  FORCE_MAIN          Set to 'true' to force main branch (same as --force-main)"
    echo "  VERBOSE             Set to 'true' to enable verbose output"
    echo
    echo "Examples:"
    echo "  $0                  # Auto-select stable version (recommended)"
    echo "  $0 --verbose        # Auto-select with verbose build output"
    echo "  $0 --branch v1.45.0 # Build specific version"
    echo "  $0 --force-main     # Build from main branch"
    echo "  $0 --clean --verbose # Clean install with verbose output"
}

# Function to get latest stable release
get_latest_release() {
    local latest_tag
    latest_tag=$(curl -s https://api.github.com/repos/denoland/deno/releases/latest | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$' 2>/dev/null || echo "")
    echo "$latest_tag"
}

# Function to get recent stable releases (fallback versions)
get_recent_releases() {
    curl -s https://api.github.com/repos/denoland/deno/releases?per_page=10 2>/dev/null | \
    grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$' | head -n 5 || echo ""
}

# Function to detect dependency conflicts in build output
detect_dependency_conflict() {
    local build_log="$1"
    if grep -q "two different versions of crate.*are being used" "$build_log" 2>/dev/null; then
        return 0
    fi
    if grep -q "mismatched types.*expected.*found" "$build_log" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Function to try building multiple versions
try_build_versions() {
    local jobs="$1"
    local build_log="/tmp/deno-build.log"
    
    log_verbose "Starting multi-version build attempt with verbose=$VERBOSE"
    
    # Get potential versions to try
    log_info "Fetching available Deno versions..."
    local latest_release
    latest_release=$(get_latest_release)
    log_verbose "Latest release: $latest_release"
    
    local versions_to_try=()
    if [ -n "$latest_release" ]; then
        versions_to_try+=("$latest_release")
    fi
    
    # Add some known stable versions as fallbacks
    log_verbose "Fetching recent releases for fallback options..."
    local recent_releases
    if recent_releases=$(get_recent_releases); then
        while read -r version; do
            if [ -n "$version" ] && [[ "$version" != "$latest_release" ]]; then
                versions_to_try+=("$version")
                log_verbose "Added fallback version: $version"
            fi
        done <<< "$recent_releases"
    fi
    
    # Add some hardcoded stable versions as last resort
    versions_to_try+=("v1.45.5" "v1.44.4" "v1.43.6" "v1.42.4")
    log_info "Will try ${#versions_to_try[@]} versions: ${versions_to_try[*]}"
    
    for version in "${versions_to_try[@]}"; do
        log_info "🚀 Attempting to build Deno $version..."
        log_verbose "Build directory: $BUILD_DIR"
        
        # Clean and clone specific version
        cd /
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        
        log_verbose "Cloning repository for version $version..."
        if ! git clone --depth 1 --branch "$version" "$DENO_REPO" "$BUILD_DIR" 2>/dev/null; then
            log_warning "Failed to clone version $version, skipping..."
            continue
        fi
        
        cd "$BUILD_DIR"
        log_verbose "Working directory: $(pwd)"
        
        # Set build jobs if specified
        if [ -n "$jobs" ]; then
            export CARGO_BUILD_JOBS="$jobs"
            log_verbose "Using $jobs parallel build jobs"
        fi
        
        # Show cargo version and environment
        if [ "${VERBOSE:-false}" = "true" ]; then
            log_verbose "Cargo version: $(cargo --version)"
            log_verbose "Rust version: $(rustc --version)"
            log_verbose "Build environment ready for $version"
        fi
        
        # Try building with locked dependencies first
        local build_cmd="cargo install --path cli --root '$INSTALL_DIR' --force --locked"
        if run_with_progress "$build_cmd" "$build_log" "Building Deno $version with locked dependencies"; then
            log_success "🎉 Deno built successfully with locked dependencies (version: $version)!"
            rm -f "$build_log"
            return 0
        fi
        
        # Check if it's a dependency conflict
        if detect_dependency_conflict "$build_log"; then
            log_warning "⚠️  Dependency conflict detected in $version, trying next version..."
            if [ "${VERBOSE:-false}" = "true" ]; then
                log_verbose "Dependency conflict details:"
                grep -A 3 -B 3 "two different versions of crate\|mismatched types" "$build_log" | head -n 10
            fi
            continue
        fi
        
        # Try without locked dependencies
        build_cmd="cargo install --path cli --root '$INSTALL_DIR' --force"
        if run_with_progress "$build_cmd" "$build_log" "Building Deno $version without locked dependencies"; then
            log_success "🎉 Deno built successfully (version: $version)!"
            rm -f "$build_log"
            return 0
        fi
        
        # Check if it's a dependency conflict
        if detect_dependency_conflict "$build_log"; then
            log_warning "⚠️  Dependency conflict detected in $version, trying next version..."
            if [ "${VERBOSE:-false}" = "true" ]; then
                log_verbose "Dependency conflict details:"
                grep -A 3 -B 3 "two different versions of crate\|mismatched types" "$build_log" | head -n 10
            fi
            continue
        else
            log_warning "❌ Build failed for $version with other errors, trying next version..."
            if [ "${VERBOSE:-false}" = "true" ]; then
                log_verbose "Build error summary:"
                tail -n 10 "$build_log"
            fi
        fi
    done
    
    # If we get here, all versions failed
    log_error "💥 All attempted versions failed to build."
    log_error "This might be due to system-specific issues or missing dependencies."
    
    if [ -f "$build_log" ]; then
        log_error "Last build log (showing last 20 lines):"
        tail -n 20 "$build_log"
    fi
    
    rm -f "$build_log"
    return 1
}

# Function to build Deno
build_deno() {
    local branch="${1:-main}"
    local jobs="${2:-}"
    
    log_info "Creating build directory: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    # If specific branch/tag requested, try that first
    if [ "$branch" != "main" ] || [ "${FORCE_MAIN:-}" = "true" ]; then
        log_info "🎯 Building from specified branch/tag: $branch"
        log_verbose "Single version build mode selected"
        
        log_info "📥 Cloning Deno repository (ref: $branch)..."
        log_verbose "Repository: $DENO_REPO"
        log_verbose "Target directory: $BUILD_DIR"
        
        if ! git clone --depth 1 --branch "$branch" "$DENO_REPO" "$BUILD_DIR"; then
            log_error "❌ Failed to clone branch/tag: $branch"
            return 1
        fi
        
        cd "$BUILD_DIR"
        log_verbose "Working directory: $(pwd)"
        
        log_info "🔨 Building Deno from source..."
        log_info "⏱️  This may take 10-30 minutes depending on your system..."
        
        # Set build jobs if specified
        if [ -n "$jobs" ]; then
            export CARGO_BUILD_JOBS="$jobs"
            log_verbose "Using $jobs parallel build jobs"
        fi
        
        # Show build environment in verbose mode
        if [ "${VERBOSE:-false}" = "true" ]; then
            log_verbose "Build environment:"
            log_verbose "  - Cargo version: $(cargo --version)"
            log_verbose "  - Rust version: $(rustc --version)"
            log_verbose "  - Target directory: $INSTALL_DIR"
        fi
        
        local build_log="/tmp/deno-build-single.log"
        
        # Try building with locked dependencies first
        local build_cmd="cargo install --path cli --root '$INSTALL_DIR' --force --locked"
        if run_with_progress "$build_cmd" "$build_log" "Building Deno $branch with locked dependencies"; then
            log_success "🎉 Deno built successfully with locked dependencies!"
            rm -f "$build_log"
            return 0
        fi
        
        # Check for dependency conflicts
        if detect_dependency_conflict "$build_log"; then
            log_error "⚠️  Dependency conflict detected in $branch."
            if [ "${VERBOSE:-false}" = "true" ]; then
                log_verbose "Dependency conflict details:"
                grep -A 5 -B 5 "two different versions of crate\|mismatched types" "$build_log" | head -n 15
            fi
            log_error "💡 Try using a different version or let the script auto-select:"
            log_error "     $0  # Auto-select stable version"
            log_error "     $0 --branch v1.45.5  # Try known working version"
            rm -f "$build_log"
            return 1
        fi
        
        # Try without locked dependencies
        log_warning "⚠️  Locked build failed, trying without --locked flag..."
        build_cmd="cargo install --path cli --root '$INSTALL_DIR' --force"
        if run_with_progress "$build_cmd" "$build_log" "Building Deno $branch without locked dependencies"; then
            log_success "🎉 Deno built successfully!"
            rm -f "$build_log"
            return 0
        else
            log_error "❌ Build failed for $branch"
            if [ -f "$build_log" ]; then
                if [ "${VERBOSE:-false}" = "true" ]; then
                    log_error "Full build log:"
                    cat "$build_log"
                else
                    log_error "Build log (last 20 lines, use --verbose for full log):"
                    tail -n 20 "$build_log"
                fi
            fi
            rm -f "$build_log"
            return 1
        fi
    else
        # Auto-select stable version and try multiple if needed
        log_info "🤖 Auto-selecting stable version and trying multiple versions if needed..."
        log_verbose "Multi-version auto-selection mode enabled"
        log_info "🔨 Building Deno from source..."
        log_info "⏱️  This may take 10-30 minutes depending on your system..."
        log_verbose "Will automatically try multiple versions until one builds successfully"
        
        if try_build_versions "$jobs"; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to verify installation
verify_installation() {
    local deno_path="$INSTALL_BIN/deno"
    
    log_info "🔍 Verifying Deno installation..."
    log_verbose "Checking binary at: $deno_path"
    
    if [ -x "$deno_path" ]; then
        log_success "✅ Deno installed at: $deno_path"
        log_verbose "Binary permissions: $(ls -la "$deno_path")"
        log_verbose "Binary size: $(du -h "$deno_path" | cut -f1)"
        
        # Test the installation
        local version
        if version=$("$deno_path" --version 2>/dev/null); then
            log_success "🎉 Deno version: $(echo "$version" | head -n1)"
            
            if [ "${VERBOSE:-false}" = "true" ]; then
                log_verbose "Full version info:"
                echo "$version" | while read -r line; do
                    log_verbose "  $line"
                done
            fi
            
            # Show PATH info
            if [[ ":$PATH:" != *":$INSTALL_BIN:"* ]]; then
                log_warning "⚠️  Add $INSTALL_BIN to your PATH:"
                echo "  export PATH=\"$INSTALL_BIN:\$PATH\""
                log_verbose "Current PATH: $PATH"
            else
                log_success "✅ $INSTALL_BIN is already in PATH"
            fi
            
            # Test basic functionality
            log_verbose "Testing basic Deno functionality..."
            if "$deno_path" eval "console.log('Deno is working!')" 2>/dev/null; then
                log_verbose "✅ Basic Deno functionality test passed"
            else
                log_warning "⚠️  Basic functionality test failed"
            fi
            
        else
            log_error "❌ Deno binary exists but failed to run"
            log_verbose "Binary exists at $deno_path but --version command failed"
            return 1
        fi
    else
        log_error "❌ Deno binary not found at expected location: $deno_path"
        log_verbose "Expected location: $deno_path"
        log_verbose "Directory contents: $(ls -la "$(dirname "$deno_path")" 2>/dev/null || echo "Directory not found")"
        return 1
    fi
}

# Main function
main() {
    local branch="main"
    local jobs=""
    local clean_install=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dir)
                INSTALL_DIR="$2"
                INSTALL_BIN="$INSTALL_DIR/bin"
                shift 2
                ;;
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            --clean)
                clean_install=true
                shift
                ;;
            --force-main)
                export FORCE_MAIN=true
                branch="main"
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --quiet)
                verbose=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose environment variable
    if [ "$verbose" = "true" ] || [ "${VERBOSE:-}" = "true" ]; then
        export VERBOSE=true
        log_verbose "Verbose mode enabled"
    else
        export VERBOSE=false
    fi
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    log_info "🔨 Building Deno from source"
    log_info "📁 Installation directory: $INSTALL_DIR"
    log_verbose "Build configuration:"
    log_verbose "  - Branch: $branch"
    log_verbose "  - Jobs: ${jobs:-auto}"
    log_verbose "  - Clean install: $clean_install"
    log_verbose "  - Verbose: $VERBOSE"
    
    # Check dependencies
    check_dependencies
    
    # Clean existing installation if requested
    if [ "$clean_install" = true ]; then
        log_info "Cleaning existing installation..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # Create installation directory
    mkdir -p "$INSTALL_BIN"
    
    # Build Deno
    build_deno "$branch" "$jobs"
    
    # Verify installation
    verify_installation
    
    log_success "🎉 Deno build completed successfully!"
    
    if [ "${VERBOSE:-false}" = "true" ]; then
        log_verbose "Build summary:"
        log_verbose "  - Installation directory: $INSTALL_DIR"
        log_verbose "  - Branch/version: $branch"
        log_verbose "  - Build jobs: ${jobs:-auto}"
        log_verbose "  - Verbose mode: $VERBOSE"
        log_verbose "  - Clean install: $clean_install"
    fi
    
    log_info "🚀 Ready to use Deno! Try running: deno --version"
}

# Run main function with all arguments
main "$@" 