#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STATUS]${NC} $1"
}

print_section() {
    echo -e "${CYAN}$1${NC}"
}

# Check if we're in Lima VM
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker not found. Make sure you're running this in the Lima VM."
    exit 1
fi

# Check if we're in the correct directory
if [[ ! -f "docker-compose.lima.yml" ]]; then
    echo -e "${RED}[ERROR]${NC} docker-compose.lima.yml not found. Please run this script from the docker/devenv directory."
    exit 1
fi

print_header "🔍 DevEnv Services Status"
echo

# Show detailed service status
print_section "📊 Service Status:"
docker compose -f docker-compose.lima.yml ps

echo

# Show running containers with more details
print_section "🐳 Container Details:"
docker compose -f docker-compose.lima.yml ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo

# Show service health and resource usage
print_section "💾 Resource Usage:"
CONTAINER_IDS=$(docker compose -f docker-compose.lima.yml ps -q)
if [[ -n "$CONTAINER_IDS" ]]; then
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $CONTAINER_IDS
else
    echo "No containers running"
fi

echo

# Show service endpoints
print_section "🌐 Service Endpoints:"
echo "  DevEnv SSH:      localhost:2222"
echo "  Redis:           localhost:6379"
echo "  NATS:            localhost:4222"
echo "  NATS Management: localhost:8222"
echo "  Redpanda Kafka:  localhost:9092"
echo "  Redpanda Admin:  localhost:8084"

echo

# Show volume information
print_section "💽 Volumes:"
docker compose -f docker-compose.lima.yml config --volumes

echo

# Show network information
print_section "🌐 Networks:"
docker compose -f docker-compose.lima.yml config --services | while read service; do
    networks=$(docker compose -f docker-compose.lima.yml config | grep -A 10 "services:" | grep -A 5 "$service:" | grep "networks:" -A 5 | grep -v "networks:" | sed 's/^[[:space:]]*//' | head -5)
    if [[ -n "$networks" ]]; then
        echo "  $service: $networks"
    fi
done

echo

# Quick connection test
print_section "🔗 Quick Connection Test:"
echo -n "  DevEnv SSH (port 2222): "
if nc -z localhost 2222 2>/dev/null; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  Redis (port 6379): "
if nc -z localhost 6379 2>/dev/null; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  NATS (port 4222): "
if nc -z localhost 4222 2>/dev/null; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  Redpanda (port 9092): "
if nc -z localhost 9092 2>/dev/null; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo

print_status "Use 'docker compose -f docker-compose.lima.yml logs -f [service]' to view logs"
print_status "Use './lima-rebuild.sh' to rebuild all services"
print_status "Use './lima-rebuild-quick.sh' to rebuild only devenv" 