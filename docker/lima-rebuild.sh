#!/bin/bash
set -e
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_dockerfile

print_step "🔄 Rebuilding DevEnv Image and Restarting Services"

print_step "🛑 Stopping all services..."
docker compose -f docker-compose.lima.yml down --remove-orphans || true

print_step "🗑️  Removing existing devenv image..."
docker images | grep -q "devenv.*latest" && \
    docker rmi devenv:latest || print_warning "Could not remove devenv:latest (may be in use)"

print_step "🧹 Cleaning up dangling images..."
docker image prune -f || true

print_step "🔨 Rebuilding devenv image..."
retry docker build \
    --tag devenv:latest \
    --no-cache \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .
print_status "✅ Docker image rebuilt successfully!"

print_step "📥 Pulling latest service images..."
for image in "redis:latest" "nats:latest" "docker.redpanda.com/redpandadata/redpanda:latest"; do
    print_status "Pulling $image..."
    retry docker pull "$image"
done

print_step "🚀 Starting all services..."
docker compose -f docker-compose.lima.yml up -d

print_step "⏳ Waiting for services to start..."
sleep 15

print_step "🔍 Checking service status..."
docker compose -f docker-compose.lima.yml ps

show_image_info
print_step "✅ Rebuild and restart complete!"
print_status "SSH: ssh -p 2222 root@localhost"
print_status "Logs: docker compose -f docker-compose.lima.yml logs -f [service]"
