#!/bin/bash
source "$(dirname "$0")/lima-lib.sh"

check_docker
check_compose

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
if check_port 2222; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  Redis (port 6379): "
if check_port 6379; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  NATS (port 4222): "
if check_port 4222; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo -n "  Redpanda (port 9092): "
if check_port 9092; then
    echo -e "${GREEN}✅ Available${NC}"
else
    echo -e "${RED}❌ Not available${NC}"
fi

echo

print_status "Use 'docker compose -f docker-compose.lima.yml logs -f [service]' to view logs"
print_status "Use './lima-rebuild.sh' to rebuild all services"
print_status "Use './lima-rebuild-quick.sh' to rebuild only devenv" 