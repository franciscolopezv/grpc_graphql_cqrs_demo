#!/bin/bash

# Script to clean up the shared Docker network
# This will stop all containers and remove the network

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

print_status "Cleaning up shared Docker network: $NETWORK_NAME"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if network exists
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    print_warning "Network '$NETWORK_NAME' does not exist"
    exit 0
fi

# Get containers using the network
print_status "Checking for containers using the network..."
CONTAINERS=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")

if [ -n "$CONTAINERS" ]; then
    print_warning "Found containers using the network:"
    for container in $CONTAINERS; do
        echo "  - $container"
    done
    
    read -p "Do you want to stop these containers? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping containers..."
        for container in $CONTAINERS; do
            print_status "Stopping $container..."
            docker stop "$container" 2>/dev/null || print_warning "Failed to stop $container"
        done
        print_success "Containers stopped"
    else
        print_error "Cannot remove network while containers are using it"
        print_error "Please stop the containers manually or run with -f flag"
        exit 1
    fi
fi

# Remove the network
print_status "Removing network: $NETWORK_NAME"
if docker network rm "$NETWORK_NAME"; then
    print_success "Network '$NETWORK_NAME' removed successfully!"
else
    print_error "Failed to remove network '$NETWORK_NAME'"
    exit 1
fi

print_success "✅ Cleanup complete!"
echo ""
echo "📋 To recreate the network:"
echo "  ./scripts/setup-network.sh"