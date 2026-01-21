#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to retry commands
retry() {
    local n=1
    local max=3
    local delay=5
    while true; do
        echo "Attempt $n/$max..."
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max in $delay seconds..."
                sleep $delay;
            else
                echo "The command has failed after $n attempts."
                return 1
            fi
        }
    done
}

# Check if we're in Lima VM
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Make sure you're running this in the Lima VM."
    exit 1
fi

# Check if we're in the correct directory
if [[ ! -f "Dockerfile" ]]; then
    print_error "Dockerfile not found. Please run this script from the docker/devenv directory."
    exit 1
fi

print_status "Building devenv Docker image..."

# Build the image with proper context and caching
print_status "Starting Docker build process..."
retry docker build \
    --tag devenv:latest \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .

if [[ $? -eq 0 ]]; then
    print_status "✅ Docker image built successfully!"
else
    print_error "❌ Docker build failed!"
    exit 1
fi

# Check if image exists
if docker images | grep -q "devenv.*latest"; then
    print_status "✅ Image 'devenv:latest' is available"
    docker images | grep devenv
else
    print_error "❌ Image build verification failed"
    exit 1
fi

print_status "🚀 Ready to run with docker-compose!"
print_status "Run: docker compose up -d"
print_status "Or use the existing run.sh script"

# Optional: Show image size
IMAGE_SIZE=$(docker images devenv:latest --format "table {{.Size}}" | tail -n 1)
print_status "Image size: $IMAGE_SIZE" 