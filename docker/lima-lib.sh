#!/bin/bash
# Shared functions for lima-*.sh scripts. Source this file, do not execute directly.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

retry() {
    local n=1 max=3 delay=5
    while true; do
        echo "Attempt $n/$max..."
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max in $delay seconds..."
                sleep $delay
            else
                echo "The command has failed after $n attempts."
                return 1
            fi
        }
    done
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Make sure you're running this in the Lima VM."
        exit 1
    fi
    # Ensure docker group is active in this session
    if ! docker info &> /dev/null; then
        if grep -q "docker.*$(whoami)" /etc/group 2>/dev/null; then
            print_warning "Docker group not active in this session. Re-executing with docker group..."
            exec sg docker -c "$0 $*"
        else
            print_error "User $(whoami) is not in the docker group. Run: sudo usermod -aG docker $(whoami)"
            exit 1
        fi
    fi
}

check_dockerfile() {
    if [[ ! -f "Dockerfile" ]]; then
        print_error "Dockerfile not found. Please run this script from the docker directory."
        exit 1
    fi
}

show_image_info() {
    local size id
    size=$(docker images devenv:latest --format "{{.Size}}" | head -1)
    id=$(docker images devenv:latest --format "{{.ID}}" | head -1)
    print_status "Image ID: $id  Size: $size"
}
