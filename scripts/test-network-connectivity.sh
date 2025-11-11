#!/bin/bash

# Script to test network connectivity between services
# Helps verify that all services can communicate properly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

NETWORK_NAME="platform-infrastructure"

print_status "🔍 Testing network connectivity for platform infrastructure"

# Check if network exists
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    print_error "Network '$NETWORK_NAME' does not exist"
    print_error "Run: ./scripts/setup-network.sh"
    exit 1
fi

# Test function
test_connectivity() {
    local service=$1
    local port=$2
    local description=$3
    
    print_status "Testing $description ($service:$port)..."
    
    if docker run --rm --network "$NETWORK_NAME" alpine sh -c "nc -z $service $port" 2>/dev/null; then
        print_success "✅ $description is reachable"
        return 0
    else
        print_error "❌ $description is not reachable"
        return 1
    fi
}

# Test HTTP endpoint
test_http_endpoint() {
    local service=$1
    local port=$2
    local path=$3
    local description=$4
    
    print_status "Testing $description (http://$service:$port$path)..."
    
    if docker run --rm --network "$NETWORK_NAME" alpine sh -c "wget -q -O- http://$service:$port$path" >/dev/null 2>&1; then
        print_success "✅ $description HTTP endpoint is working"
        return 0
    else
        print_error "❌ $description HTTP endpoint is not working"
        return 1
    fi
}

# Test DNS resolution
test_dns() {
    local service=$1
    local description=$2
    
    print_status "Testing DNS resolution for $description ($service)..."
    
    if docker run --rm --network "$NETWORK_NAME" alpine nslookup "$service" >/dev/null 2>&1; then
        print_success "✅ $description DNS resolution works"
        return 0
    else
        print_error "❌ $description DNS resolution failed"
        return 1
    fi
}

echo "🌐 Network Connectivity Tests"
echo "=============================="

# Test DNS resolution first
print_status "🔍 Testing DNS Resolution..."
test_dns "postgres" "PostgreSQL"
test_dns "kafka" "Kafka"
test_dns "zookeeper" "Zookeeper"
test_dns "graphql-gateway" "GraphQL Gateway"

echo ""

# Test basic connectivity
print_status "🔍 Testing Basic Connectivity..."
test_connectivity "postgres" "5432" "PostgreSQL Database"
test_connectivity "kafka" "9092" "Kafka (External)"
test_connectivity "kafka" "29092" "Kafka (Internal)"
test_connectivity "zookeeper" "2181" "Zookeeper"
test_connectivity "graphql-gateway" "4000" "GraphQL Gateway"

echo ""

# Test HTTP endpoints
print_status "🔍 Testing HTTP Endpoints..."
test_http_endpoint "graphql-gateway" "4000" "/health" "GraphQL Gateway Health"

echo ""

# Test database connectivity
print_status "🔍 Testing Database Connectivity..."
if docker run --rm --network "$NETWORK_NAME" postgres:15-alpine sh -c "pg_isready -h postgres -p 5432 -U postgres" >/dev/null 2>&1; then
    print_success "✅ PostgreSQL is accepting connections"
else
    print_error "❌ PostgreSQL is not accepting connections"
fi

echo ""

# Test Kafka functionality
print_status "🔍 Testing Kafka Functionality..."
if docker run --rm --network "$NETWORK_NAME" confluentinc/cp-kafka:7.4.0 kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1; then
    print_success "✅ Kafka broker is responding"
else
    print_error "❌ Kafka broker is not responding"
fi

echo ""

# List all containers on the network
print_status "📋 Containers on network '$NETWORK_NAME':"
docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} ({{.IPv4Address}}){{"\n"}}{{end}}' | sort

echo ""

# Test external service connectivity (if any services are running)
print_status "🔍 Testing External Service Connectivity..."

# Check for common service ports
EXTERNAL_SERVICES=(
    "products-service:8081:Products Service"
    "ratings-service:8082:Ratings Service"
    "inventory-service:8083:Inventory Service"
    "users-service:8084:Users Service"
)

for service_info in "${EXTERNAL_SERVICES[@]}"; do
    IFS=':' read -r service port description <<< "$service_info"
    
    # Check if container exists on network
    if docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -q "$service"; then
        test_connectivity "$service" "$port" "$description"
        test_http_endpoint "$service" "$port" "/health" "$description Health Check"
    else
        print_warning "⚠️  $description ($service) not found on network"
    fi
done

echo ""

# Summary
print_status "📊 Network Connectivity Summary"
echo "================================"

# Count containers on network
CONTAINER_COUNT=$(docker network inspect "$NETWORK_NAME" --format '{{len .Containers}}')
print_status "Total containers on network: $CONTAINER_COUNT"

# Network details
SUBNET=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
GATEWAY=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
print_status "Network subnet: $SUBNET"
print_status "Network gateway: $GATEWAY"

echo ""
print_success "🎉 Network connectivity test completed!"
echo ""
echo "💡 Tips:"
echo "  - If services are not reachable, check if they're running: docker compose ps"
echo "  - If DNS resolution fails, recreate the network: ./scripts/setup-network.sh"
echo "  - For service-specific issues, check logs: docker logs <service-name>"
echo "  - To add a new service to the network, use: docker run --network $NETWORK_NAME ..."