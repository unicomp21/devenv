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

# Check if we're in Lima VM
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Make sure you're running this in the Lima VM."
    exit 1
fi

# Check if we're in the correct directory
if [[ ! -f "docker-compose.lima.yml" ]]; then
    print_error "docker-compose.lima.yml not found. Please run this script from the docker/devenv directory."
    exit 1
fi

print_step "🔥 FULL RESET - This will remove ALL containers and data!"
print_warning "This will delete:"
echo "  - All containers (devenv, redis, nats, redpanda)"
echo "  - All named volumes (nats-data, redpanda-data)"
echo "  - All anonymous volumes"
echo "  - Redis data, NATS data, Redpanda data"
echo
print_warning "This will PRESERVE:"
echo "  - Docker images (devenv:latest, redis:latest, etc.)"
echo "  - Mounted host directories (/mono-root, /data, ~/.ssh)"
echo

# Confirmation prompt
read -p "Are you sure you want to proceed with FULL RESET? (type 'yes' to confirm): " -r
if [[ ! $REPLY == "yes" ]]; then
    print_status "Reset cancelled."
    exit 0
fi

print_step "🛑 Stopping all services..."
docker compose -f docker-compose.lima.yml down --remove-orphans || true

print_step "🗑️  Removing all containers..."
docker compose -f docker-compose.lima.yml rm -f || true

print_step "🧹 Removing all volumes (including data)..."
docker compose -f docker-compose.lima.yml down -v || true

print_step "🧽 Cleaning up anonymous volumes..."
docker volume prune -f || true

print_step "🔍 Verifying cleanup..."
REMAINING_CONTAINERS=$(docker compose -f docker-compose.lima.yml ps -q 2>/dev/null || echo "")
if [[ -n "$REMAINING_CONTAINERS" ]]; then
    print_warning "Some containers still exist, force removing..."
    docker rm -f $REMAINING_CONTAINERS || true
fi

print_step "📋 Checking required images..."
MISSING_IMAGES=()

if ! docker images | grep -q "devenv.*latest"; then
    MISSING_IMAGES+=("devenv:latest")
fi

if ! docker images | grep -q "redis.*latest"; then
    MISSING_IMAGES+=("redis:latest")
fi

if ! docker images | grep -q "nats.*latest"; then
    MISSING_IMAGES+=("nats:latest")
fi

if ! docker images | grep -q "redpanda"; then
    MISSING_IMAGES+=("docker.redpanda.com/redpandadata/redpanda:latest")
fi

if [[ ${#MISSING_IMAGES[@]} -gt 0 ]]; then
    print_warning "Missing images detected:"
    for img in "${MISSING_IMAGES[@]}"; do
        echo "  - $img"
    done
    echo
    
    if [[ " ${MISSING_IMAGES[@]} " =~ " devenv:latest " ]]; then
        print_error "DevEnv image missing! Please build it first:"
        print_status "Run: ./lima-build.sh"
        exit 1
    fi
    
    print_step "📥 Pulling missing service images..."
    for img in "${MISSING_IMAGES[@]}"; do
        if [[ "$img" != "devenv:latest" ]]; then
            print_status "Pulling $img..."
            docker pull "$img"
        fi
    done
fi

print_step "🚀 Starting all services fresh..."
docker compose -f docker-compose.lima.yml up -d

print_step "⏳ Waiting for services to start..."
sleep 15

print_step "🔍 Checking service status..."
docker compose -f docker-compose.lima.yml ps

print_step "🔗 Testing connectivity..."
sleep 5

# Test each service
services_status=""

if nc -z localhost 2222 2>/dev/null; then
    services_status+="  DevEnv SSH (2222): ✅\n"
else
    services_status+="  DevEnv SSH (2222): ❌\n"
fi

if nc -z localhost 6379 2>/dev/null; then
    services_status+="  Redis (6379): ✅\n"
else
    services_status+="  Redis (6379): ❌\n"
fi

if nc -z localhost 4222 2>/dev/null; then
    services_status+="  NATS (4222): ✅\n"
else
    services_status+="  NATS (4222): ❌\n"
fi

if nc -z localhost 9092 2>/dev/null; then
    services_status+="  Redpanda (9092): ✅\n"
else
    services_status+="  Redpanda (9092): ❌\n"
fi

echo -e "$services_status"

print_step "✅ Full reset complete!"
print_status "All services are running fresh with clean data"
print_status "All previous data has been removed"
print_status "Mounted volumes from host are preserved"

echo

print_status "Connection info:"
echo "  SSH: ssh -p 2222 root@localhost"
echo "  Redis: localhost:6379"
echo "  NATS: localhost:4222"
echo "  Redpanda: localhost:9092"

echo

print_status "Next steps:"
echo "  - Check status: ./lima-status.sh"
echo "  - View logs: ./lima-compose.sh logs -f"
echo "  - Connect to devenv: ssh -p 2222 root@localhost" 