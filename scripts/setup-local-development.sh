#!/bin/bash

# Complete setup script for local development environment
# This script sets up everything needed for multi-repository development

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

print_header() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_header "🚀 Platform Infrastructure Local Development Setup"

# Check prerequisites
print_status "Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker and try again."
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check Docker Compose
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not available. Please install Docker Compose and try again."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Setup network
print_header "📡 Setting up shared Docker network"
if ! docker network ls | grep -q "platform-infrastructure"; then
    ./scripts/setup-network.sh
else
    print_success "Network 'platform-infrastructure' already exists"
fi

# Step 2: Setup environment
print_header "⚙️  Setting up environment configuration"

if [ ! -f .env ]; then
    print_status "Creating .env file from template..."
    cp .env.template .env
    print_success ".env file created"
else
    print_warning ".env file already exists"
fi

# Step 3: Start infrastructure services
print_header "🏗️  Starting platform infrastructure services"

print_status "Starting services with Docker Compose..."
docker compose up -d

print_status "Waiting for services to be healthy..."

# Wait for services to be ready
MAX_WAIT=120
WAIT_TIME=0

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker compose ps --format json | jq -r '.[].State' | grep -v "running" > /dev/null; then
        echo -n "."
        sleep 5
        WAIT_TIME=$((WAIT_TIME + 5))
    else
        break
    fi
done

echo ""

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    print_warning "Services may still be starting. Check status with: docker compose ps"
else
    print_success "All services are running"
fi

# Step 4: Verify setup
print_header "🔍 Verifying setup"

print_status "Checking service health..."

# Check PostgreSQL
if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
    print_success "✅ PostgreSQL is ready"
else
    print_error "❌ PostgreSQL is not ready"
fi

# Check Kafka
if docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    print_success "✅ Kafka is ready"
else
    print_error "❌ Kafka is not ready"
fi

# Check GraphQL Gateway
if curl -f -s http://localhost:4000/health > /dev/null 2>&1; then
    print_success "✅ GraphQL Gateway is ready"
else
    print_error "❌ GraphQL Gateway is not ready"
fi

# Step 5: Test network connectivity
print_header "🌐 Testing network connectivity"
./scripts/test-network-connectivity.sh

# Step 6: Display summary
print_header "📋 Setup Summary"

echo "✅ Platform infrastructure is ready for development!"
echo ""
echo "🔗 Service Endpoints:"
echo "  - GraphQL Gateway: http://localhost:4000"
echo "  - GraphQL Playground: http://localhost:4000 (if enabled)"
echo "  - PostgreSQL: localhost:5432"
echo "  - Kafka: localhost:9092"
echo "  - Zookeeper: localhost:2181"
echo ""
echo "📊 Service Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "🌐 Network Information:"
echo "  - Network Name: platform-infrastructure"
echo "  - Subnet: $(docker network inspect platform-infrastructure --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')"
echo "  - Gateway: $(docker network inspect platform-infrastructure --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')"
echo ""
echo "📚 Next Steps:"
echo "  1. Clone your service repositories"
echo "  2. Copy the docker-compose template:"
echo "     curl -o docker-compose.yml https://raw.githubusercontent.com/your-org/platform-infrastructure/main/docs/examples/service-docker-compose-template.yml"
echo "  3. Customize the template for your service"
echo "  4. Start your service: docker compose up -d"
echo "  5. Register GraphQL services: ./scripts/register-service.sh <service-name> <service-url>"
echo ""
echo "🛠️  Useful Commands:"
echo "  - View logs: docker compose logs -f"
echo "  - Stop services: docker compose down"
echo "  - Test connectivity: ./scripts/test-network-connectivity.sh"
echo "  - Clean up network: ./scripts/cleanup-network.sh"
echo ""
echo "📖 Documentation:"
echo "  - Local Development Guide: docs/local-development-setup.md"
echo "  - GraphQL Gateway Guide: README-GraphQL-Gateway.md"
echo "  - Service Registration: docs/examples/new-service-registration.md"

print_success "🎉 Setup completed successfully!"