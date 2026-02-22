#!/bin/bash
set -e
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_dockerfile

print_status "Building devenv Docker image..."
retry docker build \
    --tag devenv:latest \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .

print_status "✅ Docker image built successfully!"
show_image_info
print_status "🚀 Ready to run: docker compose -f docker-compose.lima.yml up -d"
