#!/bin/bash

# Script to validate Docker Compose network configuration
# Checks if the network setup is correct for multi-repository development

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

print_status "🔍 Validating Docker Compose network configuration"

# Check if docker-compose.yml exists
if [ ! -f docker-compose.yml ]; then
    print_error "docker-compose.yml not found in current directory"
    exit 1
fi

# Validate docker-compose.yml syntax
print_status "Checking Docker Compose syntax..."
if docker compose config > /dev/null 2>&1; then
    print_success "✅ Docker Compose syntax is valid"
else
    print_error "❌ Docker Compose syntax is invalid"
    docker compose config
    exit 1
fi

# Check network configuration
print_status "Checking network configuration..."

# Check if network is defined as external
if docker compose config | grep -A 5 "networks:" | grep -q "external: true"; then
    print_success "✅ Network is configured as external"
else
    print_error "❌ Network should be configured as external: true"
fi

# Check if services are assigned to the network
print_status "Checking service network assignments..."

SERVICES=$(docker compose config --services)
SERVICES_WITH_NETWORK=0
TOTAL_SERVICES=0

for service in $SERVICES; do
    TOTAL_SERVICES=$((TOTAL_SERVICES + 1))
    
    # Check if service has platform-infrastructure network in the composed config
    if docker compose config | grep -A 100 "^  $service:" | grep -B 100 "^  [a-zA-Z-]*:" | grep -A 5 "networks:" | grep -q "platform-infrastructure"; then
        print_success "✅ Service '$service' is assigned to platform-infrastructure network"
        SERVICES_WITH_NETWORK=$((SERVICES_WITH_NETWORK + 1))
    else
        print_warning "⚠️  Service '$service' network assignment not detected"
    fi
done

print_status "Network assignment summary: $SERVICES_WITH_NETWORK/$TOTAL_SERVICES services explicitly assigned"

# Check if network exists
print_status "Checking if network exists..."
if docker network ls | grep -q "$NETWORK_NAME"; then
    print_success "✅ Network '$NETWORK_NAME' exists"
    
    # Show network details
    SUBNET=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
    GATEWAY=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "N/A")
    
    print_status "Network details:"
    echo "  Subnet: $SUBNET"
    echo "  Gateway: $GATEWAY"
else
    print_warning "⚠️  Network '$NETWORK_NAME' does not exist"
    print_status "Run: ./scripts/setup-network.sh to create it"
fi

# Test configuration by doing a dry run
print_status "Testing configuration with dry run..."
if docker compose up --dry-run > /dev/null 2>&1; then
    print_success "✅ Configuration test passed"
else
    print_error "❌ Configuration test failed"
    print_error "Try: docker compose up --dry-run"
fi

# Summary
echo ""
print_status "📋 Configuration Summary"
echo "========================"

echo "Network Configuration:"
docker compose config | grep -A 10 "networks:" | head -15

echo ""
echo "Service Network Assignments:"
for service in $SERVICES; do
    if docker compose config | grep -A 20 "^  $service:" | grep -q "networks:"; then
        echo "  ✅ $service: Explicitly assigned"
    else
        echo "  ⚠️  $service: Using default network"
    fi
done

echo ""
print_success "🎉 Network configuration validation completed!"

# Recommendations
echo ""
print_status "💡 Recommendations:"
echo "  1. Ensure all services are explicitly assigned to the network"
echo "  2. Use 'external: true' for the network definition"
echo "  3. Create the network before starting services: ./scripts/setup-network.sh"
echo "  4. Test connectivity after starting: ./scripts/test-network-connectivity.sh"