#!/bin/bash
set -e
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_compose

print_step "🔄 Resetting DevEnv Container to Clean State"

# Step 1: Check if devenv container exists
CONTAINER_EXISTS=$(docker compose -f docker-compose.lima.yml ps -q devenv 2>/dev/null || echo "")
if [[ -z "$CONTAINER_EXISTS" ]]; then
    print_warning "DevEnv container doesn't exist. Creating fresh container..."
else
    print_status "Found existing devenv container"
fi

# Step 2: Stop the devenv container
print_step "🛑 Stopping devenv container..."
docker compose -f docker-compose.lima.yml stop devenv || true

# Step 3: Remove the devenv container (this removes any runtime changes)
print_step "🗑️  Removing devenv container (preserves image)..."
docker compose -f docker-compose.lima.yml rm -f devenv || true

# Step 4: Remove any anonymous volumes associated with devenv
print_step "🧹 Cleaning up anonymous volumes..."
docker volume prune -f || true

# Step 5: Check if devenv image exists
if ! docker images | grep -q "devenv.*latest"; then
    print_error "DevEnv image 'devenv:latest' not found!"
    print_status "Please build the image first with: ./lima-build.sh"
    exit 1
fi

# Step 6: Create and start fresh devenv container
print_step "🚀 Creating fresh devenv container from clean image..."
docker compose -f docker-compose.lima.yml up -d devenv

# Step 7: Wait for container to be ready
print_step "⏳ Waiting for devenv to start..."
sleep 10

# Step 8: Verify container is running
print_step "🔍 Verifying devenv container status..."
if docker compose -f docker-compose.lima.yml ps devenv | grep -q "Up"; then
    print_status "✅ DevEnv container is running"
else
    print_error "❌ DevEnv container failed to start"
    print_status "Check logs with: ./lima-compose.sh logs devenv"
    exit 1
fi

# Step 9: Test SSH connectivity
print_step "🔗 Testing SSH connectivity..."
sleep 5  # Give SSH service time to start
if check_port 2222; then
    print_status "✅ SSH service is available on port 2222"
else
    print_warning "⚠️  SSH service not yet available (may still be starting)"
fi

# Step 10: Show container info
CONTAINER_ID=$(docker compose -f docker-compose.lima.yml ps -q devenv)
IMAGE_ID=$(docker inspect $CONTAINER_ID --format='{{.Image}}' | cut -c1-12)
print_status "Container reset complete!"
echo "  Container ID: $CONTAINER_ID"
echo "  Image ID: $IMAGE_ID"
echo "  SSH Access: ssh -p 2222 root@localhost"

echo

print_step "✅ DevEnv container reset to clean state!"
print_status "The container is now running fresh from the image"
print_status "Any changes made during previous sessions have been discarded"
print_status "Mounted volumes (/mono-root, /data, ~/.ssh) are preserved"

echo

print_status "Next steps:"
echo "  - Connect: ssh -p 2222 root@localhost"
echo "  - View logs: ./lima-compose.sh logs -f devenv"
echo "  - Check status: ./lima-status.sh" 