#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

DOCKER=(docker)

if ! docker info >/dev/null 2>&1; then
  if id -nG "$(whoami)" | grep -qw docker || getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx "$(whoami)"; then
    exec sg docker -c "$0"
  fi

  if command -v sudo >/dev/null 2>&1; then
    echo "Docker daemon requires elevated access; using sudo."
    DOCKER=(sudo docker)
  else
    echo "Cannot access Docker daemon."
    echo "Run: sudo usermod -aG docker $(whoami)"
    echo "Then log out/in, or run this once with: sg docker -c './run.simple.sh'"
    exit 1
  fi
fi

export DATA_DIR="${DATA_DIR:-$HOME/data}"
export SSH_HOME="${SSH_HOME:-$HOME}"

mkdir -p "$DATA_DIR"

if ! "${DOCKER[@]}" image inspect devenv:latest >/dev/null 2>&1; then
  "${DOCKER[@]}" build \
    --tag devenv:latest \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    .
fi

env DATA_DIR="$DATA_DIR" SSH_HOME="$SSH_HOME" "${DOCKER[@]}" compose -f docker-compose.lima.yml up -d

if "${DOCKER[@]}" compose -f docker-compose.lima.yml exec -T devenv sh -lc 'command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1'; then
  echo "CUDA check passed: nvidia-smi is available inside devenv."
else
  echo "CUDA check skipped or failed: run 'docker compose -f docker-compose.lima.yml exec devenv nvidia-smi' for details."
fi
