#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

COMPOSE_FILE="docker-compose.lima.yml"

# Function to print usage
print_usage() {
    echo -e "${BLUE}Lima DevEnv Docker Compose Wrapper${NC}"
    echo
    echo "Usage: $0 <command> [options]"
    echo
    echo "Common commands:"
    echo "  ps                    Show service status"
    echo "  up [service]          Start services (or specific service)"
    echo "  down                  Stop all services"
    echo "  logs [service]        Show logs (add -f to follow)"
    echo "  restart [service]     Restart services (or specific service)"
    echo "  stop [service]        Stop services (or specific service)"
    echo "  start [service]       Start services (or specific service)"
    echo "  exec <service> <cmd>  Execute command in service"
    echo "  build [service]       Build services (or specific service)"
    echo
    echo "Examples:"
    echo "  $0 ps                 # Show all service status"
    echo "  $0 up -d              # Start all services in background"
    echo "  $0 logs -f devenv     # Follow devenv logs"
    echo "  $0 exec devenv bash   # Get shell in devenv container"
    echo "  $0 restart devenv     # Restart only devenv service"
    echo
    echo "Services: devenv, redis, nats, redpanda"
}

# Check if we're in the correct directory
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} $COMPOSE_FILE not found. Please run this script from the docker/devenv directory."
    exit 1
fi

# If no arguments provided, show usage
if [[ $# -eq 0 ]]; then
    print_usage
    exit 0
fi

# Handle help flag
if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    print_usage
    exit 0
fi

# Execute docker compose command with Lima compose file
echo -e "${GREEN}[INFO]${NC} Running: docker compose -f $COMPOSE_FILE $@"
docker compose -f "$COMPOSE_FILE" "$@" 