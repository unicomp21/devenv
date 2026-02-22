#!/bin/bash
set -e
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_dockerfile

print_step "⚡ Quick DevEnv Image Rebuild"

print_step "🛑 Stopping devenv container..."
docker compose -f docker-compose.lima.yml stop devenv || true
docker compose -f docker-compose.lima.yml rm -f devenv || true

print_step "🗑️  Removing existing devenv image..."
docker images | grep -q "devenv.*latest" && \
    docker rmi devenv:latest || print_warning "Could not remove devenv:latest (may be in use)"

print_step "🔨 Rebuilding devenv image..."
retry docker build \
    --tag devenv:latest \
    --no-cache \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .
print_status "✅ Docker image rebuilt successfully!"

print_step "🚀 Starting devenv container..."
docker compose -f docker-compose.lima.yml up -d devenv

print_step "⏳ Waiting for devenv to start..."
sleep 10

print_step "🔍 Checking devenv status..."
docker compose -f docker-compose.lima.yml ps devenv

show_image_info
print_step "✅ Quick rebuild complete!"
print_status "SSH: ssh -p 2222 root@localhost"
print_status "Other services (Redis, NATS, Redpanda) are still running"
print_status "Logs: docker compose -f docker-compose.lima.yml logs -f devenv"
