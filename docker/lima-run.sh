#!/bin/bash
set -e
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_dockerfile

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