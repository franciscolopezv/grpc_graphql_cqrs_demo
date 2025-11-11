#!/bin/bash

# Script to set up shared Docker network for multi-repository development
# This creates a shared network that all services can use for communication

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

print_status "Setting up shared Docker network for multi-repository development"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if network already exists
if docker network ls | grep -q "$NETWORK_NAME"; then
    print_warning "Network '$NETWORK_NAME' already exists"
    
    # Get network details
    NETWORK_INFO=$(docker network inspect "$NETWORK_NAME" 2>/dev/null)
    SUBNET=$(echo "$NETWORK_INFO" | grep -o '"Subnet": "[^"]*"' | cut -d'"' -f4)
    GATEWAY=$(echo "$NETWORK_INFO" | grep -o '"Gateway": "[^"]*"' | cut -d'"' -f4)
    
    print_status "Existing network details:"
    echo "  Name: $NETWORK_NAME"
    echo "  Subnet: $SUBNET"
    echo "  Gateway: $GATEWAY"
    
    # Ask if user wants to recreate
    read -p "Do you want to recreate the network? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing existing network..."
        
        # Stop any containers using the network
        CONTAINERS=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
        if [ -n "$CONTAINERS" ]; then
            print_warning "Stopping containers using the network: $CONTAINERS"
            for container in $CONTAINERS; do
                docker stop "$container" 2>/dev/null || true
            done
        fi
        
        docker network rm "$NETWORK_NAME"
        print_success "Existing network removed"
    else
        print_success "Using existing network"
        exit 0
    fi
fi

# Create the network
print_status "Creating shared Docker network: $NETWORK_NAME"

docker network create \
    --driver bridge \
    --subnet=172.20.0.0/16 \
    --gateway=172.20.0.1 \
    --opt com.docker.network.bridge.name=br-platform \
    --label "purpose=platform-infrastructure" \
    --label "environment=development" \
    "$NETWORK_NAME"

print_success "Network '$NETWORK_NAME' created successfully!"

# Display network information
print_status "Network details:"
docker network inspect "$NETWORK_NAME" --format '
  Name: {{.Name}}
  ID: {{.Id}}
  Driver: {{.Driver}}
  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}
  Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}
  Created: {{.Created}}'

print_success "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Start platform infrastructure: docker compose up -d"
echo "  2. In other repositories, use this network in docker-compose.yml:"
echo ""
echo "     networks:"
echo "       default:"
echo "         name: platform-infrastructure"
echo "         external: true"
echo ""
echo "  3. Services can now communicate using container names:"
echo "     - PostgreSQL: postgres:5432"
echo "     - Kafka: kafka:29092"
echo "     - GraphQL Gateway: graphql-gateway:4000"
echo ""
echo "🔍 Useful commands:"
echo "  - List network containers: docker network inspect platform-infrastructure"
echo "  - Remove network: ./scripts/cleanup-network.sh"
echo "  - Test connectivity: docker run --rm --network platform-infrastructure alpine ping postgres"