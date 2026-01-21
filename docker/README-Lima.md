# DevEnv in Lima VM

This guide explains how to build and run the development environment in a Lima VM.

## Prerequisites

1. Lima VM should be running with Docker installed
2. You should be in the Lima VM shell
3. Navigate to the `docker/devenv` directory in your mono-root

## Quick Start

### 1. Launch Lima VM
From your host machine:
```bash
cd lima
./launch.sh
```

### 2. Navigate to devenv directory
Once in the Lima VM:
```bash
cd /Users/$(whoami)/repo/dev/mono-root/docker/devenv
```

### 3. Build and run everything
```bash
./lima-run.sh
```

This script will:
- Build the devenv Docker image if it doesn't exist
- Pull required service images (Redis, NATS, Redpanda)
- Start all services using docker-compose
- Show connection information

## Manual Steps

### Build the devenv image only
```bash
./lima-build.sh
```

### Start services with existing image
```bash
docker compose -f docker-compose.lima.yml up -d
```

### Stop all services
```bash
docker compose -f docker-compose.lima.yml down
```

### Rebuild image and restart all services (when Dockerfile changes)
```bash
./lima-rebuild.sh
```

### Quick rebuild (only devenv container, keeps other services running)
```bash
./lima-rebuild-quick.sh
```

### Check service status
```bash
./lima-status.sh
```

### Docker compose wrapper (shorthand commands)
```bash
./lima-compose.sh ps              # Show service status
./lima-compose.sh logs -f devenv  # Follow devenv logs
./lima-compose.sh restart devenv  # Restart devenv service
```

### Reset devenv container to clean state
```bash
./lima-reset.sh                   # Reset only devenv container (keeps other services)
./lima-reset-full.sh              # Full reset - all containers and data (requires confirmation)
```

## Services and Ports

| Service | Host Port | Container Port | Description |
|---------|-----------|----------------|-------------|
| DevEnv SSH | 2222 | 22 | SSH access to development environment |
| Redis | 6379 | 6379 | Redis database |
| NATS | 4222 | 4222 | NATS messaging |
| NATS Management | 8222 | 8222 | NATS web interface |
| Redpanda Kafka | 9092 | 9092 | Kafka API |
| Redpanda Admin | 8084 | 8084 | Redpanda admin interface |

## Connecting to DevEnv

### SSH Access
```bash
ssh -p 2222 root@localhost
```

### From Host Machine (if port forwarding is set up)
```bash
ssh -p 2222 root@localhost
```

## Volume Mounts

- `../..` (mono-root) → `/mono-root` in container
- `/data` → `/data` in container  
- `~/.ssh` → `/tmp/.ssh` in container (read-only)
- Docker socket mounted for Docker-in-Docker support

## Environment Variables

The following environment variables can be set:
- `OPENAI_API_KEY`
- `OPENAI_API_ENDPOINT`
- `NATS_ENDPOINT`
- `NATS_JS_ENDPOINT`
- `NATS_WS_ENDPOINT`
- `REDIS_ENDPOINT`

## Troubleshooting

### Check service status
```bash
# Detailed status with resource usage and connection tests
./lima-status.sh

# Simple status
./lima-compose.sh ps
# or
docker compose -f docker-compose.lima.yml ps
```

### View logs
```bash
# All services
./lima-compose.sh logs -f
# or
docker compose -f docker-compose.lima.yml logs -f

# Specific service
./lima-compose.sh logs -f devenv
./lima-compose.sh logs -f redis
./lima-compose.sh logs -f nats
./lima-compose.sh logs -f redpanda
```

### Rebuild image manually
```bash
docker rmi devenv:latest
./lima-build.sh
```

### Automated rebuild and restart
```bash
# Full rebuild - stops all services, rebuilds image, restarts everything
./lima-rebuild.sh

# Quick rebuild - only rebuilds and restarts devenv container
./lima-rebuild-quick.sh
```

### Reset containers to clean state
```bash
# Reset only devenv container (fast, keeps other services running)
./lima-reset.sh

# Full reset - all containers and data (requires confirmation)
./lima-reset-full.sh
```

### Clean up everything
```bash
./lima-compose.sh down -v
docker system prune -f
```

## Development Tools Included

The devenv container includes:
- **Languages**: Node.js, Python, Rust, Go, Kotlin, Zig, Deno, Bun
- **Build Tools**: CMake, Ninja, Make, Cargo
- **Development**: Git, SSH, Emacs, Clang tools
- **Cloud**: AWS CLI, kubectl, Helm, k9s
- **Containers**: Docker, Docker Compose
- **Testing**: Playwright (as per testing guidelines)
- **Networking**: ngrok, cloudflared, rclone

## File Structure

```
docker/devenv/
├── Dockerfile              # Main development environment
├── docker-compose.yml      # Original compose file (builds image)
├── docker-compose.lima.yml # Lima-specific (uses pre-built image)
├── lima-build.sh          # Build script for Lima
├── lima-run.sh            # Complete setup script for Lima
├── lima-rebuild.sh        # Full rebuild and restart script
├── lima-rebuild-quick.sh  # Quick devenv-only rebuild script
├── lima-reset.sh          # Reset devenv container to clean state
├── lima-reset-full.sh     # Full reset - all containers and data
├── lima-status.sh         # Enhanced service status checker
├── lima-compose.sh        # Docker compose wrapper script
├── entrypoint.sh          # Container startup script
├── setup-ssh.sh           # SSH configuration script
├── git.config.ssh         # Git configuration
└── README-Lima.md         # This file
```

## Notes

- The Lima-specific compose file (`docker-compose.lima.yml`) uses the pre-built `devenv:latest` image instead of building it each time
- SSH keys from the host are mounted read-only into the container
- The container runs as root for development convenience
- Docker socket is mounted for Docker-in-Docker capabilities
- All services are connected via a custom bridge network 