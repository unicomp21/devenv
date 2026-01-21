#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
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

print_step "⚡ Quick DevEnv Image Rebuild"

# Step 1: Stop only the devenv container
print_step "🛑 Stopping devenv container..."
docker compose -f docker-compose.lima.yml stop devenv || true
docker compose -f docker-compose.lima.yml rm -f devenv || true

# Step 2: Remove the existing devenv image
print_step "🗑️  Removing existing devenv image..."
if docker images | grep -q "devenv.*latest"; then
    docker rmi devenv:latest || print_warning "Could not remove devenv:latest image (may be in use)"
fi

# Step 3: Rebuild the devenv image
print_step "🔨 Rebuilding devenv image..."
retry docker build \
    --tag devenv:latest \
    --no-cache \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .

if [[ $? -eq 0 ]]; then
    print_status "✅ Docker image rebuilt successfully!"
else
    print_error "❌ Docker build failed!"
    exit 1
fi

# Step 4: Start only the devenv container
print_step "🚀 Starting devenv container..."
docker compose -f docker-compose.lima.yml up -d devenv

# Step 5: Wait for devenv to be ready
print_step "⏳ Waiting for devenv to start..."
sleep 10

# Step 6: Check devenv status
print_step "🔍 Checking devenv status..."
docker compose -f docker-compose.lima.yml ps devenv

# Step 7: Show connection information
print_step "📋 DevEnv is ready!"
echo
print_status "SSH into devenv container:"
echo "  ssh -p 2222 root@localhost"
echo

# Step 8: Show image info
IMAGE_SIZE=$(docker images devenv:latest --format "table {{.Size}}" | tail -n 1)
IMAGE_ID=$(docker images devenv:latest --format "table {{.ID}}" | tail -n 1)
print_status "New image info:"
echo "  Image ID: $IMAGE_ID"
echo "  Size: $IMAGE_SIZE"
echo

print_step "✅ Quick rebuild complete!"
print_status "Other services (Redis, NATS, Redpanda) are still running"
print_status "To view devenv logs: docker compose -f docker-compose.lima.yml logs -f devenv" 