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

# Ensure docker group is active in this session
if ! docker info &> /dev/null; then
    if groups | grep -q docker 2>/dev/null || id -nG | grep -q docker 2>/dev/null; then
        : # already in docker group but still failing - different issue
    elif grep -q "docker.*$(whoami)" /etc/group 2>/dev/null; then
        print_warning "Docker group not active in this session. Re-executing with docker group..."
        exec sg docker -c "$0 $*"
    else
        print_error "User $(whoami) is not in the docker group. Run: sudo usermod -aG docker $(whoami)"
        exit 1
    fi
fi

# Check if we're in the correct directory
if [[ ! -f "Dockerfile" ]]; then
    print_error "Dockerfile not found. Please run this script from the docker/devenv directory."
    exit 1
fi

print_step "🚀 Starting Lima DevEnv Setup"

# Step 1: Build the image if it doesn't exist
if ! docker images | grep -q "devenv.*latest"; then
    print_step "📦 Building devenv image..."
    ./lima-build.sh
else
    print_status "✅ devenv:latest image already exists"
    
    # Ask if user wants to rebuild
    read -p "Do you want to rebuild the image? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "🔄 Rebuilding devenv image..."
        ./lima-build.sh
    fi
fi

# Step 2: Prompt for /data mount directory
default_data_dir="/data"
read -p "Enter host directory to mount as /data in container [$default_data_dir]: " data_dir
data_dir="${data_dir:-$default_data_dir}"

# Expand ~ to home directory
data_dir="${data_dir/#\~/$HOME}"

if [[ ! -d "$data_dir" ]]; then
    print_warning "Directory '$data_dir' does not exist."
    read -p "Create it? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        mkdir -p "$data_dir"
        print_status "Created directory '$data_dir'"
    else
        print_error "Cannot proceed without a valid /data mount directory."
        exit 1
    fi
fi

export DATA_DIR="$data_dir"
print_status "Using '$data_dir' as /data mount"

# Step 3: Stop any existing containers
print_step "🛑 Stopping existing containers..."
docker compose -f docker-compose.lima.yml down --remove-orphans || true

# Step 4: Pull required images
print_step "📥 Pulling required images..."
images=(
    "redis:latest"
    "nats:latest"
    "docker.redpanda.com/redpandadata/redpanda:latest"
)

for image in "${images[@]}"; do
    print_status "Pulling $image..."
    retry docker pull $image
done

# Step 5: Start services
print_step "🚀 Starting services with docker-compose..."
docker compose -f docker-compose.lima.yml up -d

# Step 6: Wait for services to be ready
print_step "⏳ Waiting for services to start..."
sleep 10

# Step 7: Check service status
print_step "🔍 Checking service status..."
docker compose -f docker-compose.lima.yml ps

# Step 8: Show connection information
print_step "📋 Connection Information:"
echo
print_status "SSH into devenv container:"
echo "  ssh -p 2222 root@localhost"
echo
print_status "Service endpoints:"
echo "  Redis: localhost:6379 (internal: devenv-redis-1:6379)"
echo "  NATS: localhost:4222 (internal: nats:4222)"
echo "  NATS WebSocket: localhost:8081 (internal: nats-ws:8081)"
echo "  Redpanda Kafka: localhost:9092"
echo "  Redpanda Admin: localhost:8084"
echo
print_status "Mounted volumes:"
echo "  Host mono-root -> Container /mono-root"
echo "  Host $DATA_DIR -> Container /data"
echo "  Host ~/.ssh -> Container /tmp/.ssh (read-only)"
echo

# Step 9: Show logs command
print_status "To view logs: docker compose -f docker-compose.lima.yml logs -f [service_name]"
print_status "To stop all: docker compose -f docker-compose.lima.yml down"

print_step "✅ DevEnv setup complete!" 