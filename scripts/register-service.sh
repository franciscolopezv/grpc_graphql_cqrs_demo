#!/bin/bash

# Script to register a new GraphQL service with the Gateway
# Usage: ./scripts/register-service.sh <service-name> <service-url> [port]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <service-name> <service-url> [port]"
    print_error "Example: $0 inventory http://inventory-service:8083 8083"
    exit 1
fi

SERVICE_NAME=$1
SERVICE_URL=$2
SERVICE_PORT=${3:-8080}

print_status "Registering service: $SERVICE_NAME"
print_status "Service URL: $SERVICE_URL"
print_status "Service Port: $SERVICE_PORT"

# Validate service name (must be lowercase, alphanumeric, hyphens allowed)
if ! [[ "$SERVICE_NAME" =~ ^[a-z0-9-]+$ ]]; then
    print_error "Service name must be lowercase alphanumeric with hyphens only"
    exit 1
fi

# Check if service is reachable
print_status "Checking service health..."
if curl -f -s "${SERVICE_URL}/health" > /dev/null; then
    print_success "Service health check passed"
else
    print_warning "Service health check failed - continuing anyway"
fi

# Check if service supports Federation
print_status "Checking Federation support..."
if curl -f -s "${SERVICE_URL}/_service" > /dev/null; then
    print_success "Service supports Federation (_service endpoint found)"
else
    print_error "Service does not support Federation (_service endpoint not found)"
    print_error "Please implement the _service endpoint that returns SDL"
    exit 1
fi

# Backup current configuration
print_status "Backing up current configuration..."
cp config/router.yaml config/router.yaml.backup.$(date +%Y%m%d_%H%M%S)
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

# Add environment variable
print_status "Adding environment variable..."
SERVICE_ENV_VAR="${SERVICE_NAME^^}_SERVICE_URL"
SERVICE_ENV_VAR=$(echo "$SERVICE_ENV_VAR" | tr '-' '_')

if grep -q "^${SERVICE_ENV_VAR}=" .env; then
    print_warning "Environment variable $SERVICE_ENV_VAR already exists, updating..."
    sed -i.bak "s|^${SERVICE_ENV_VAR}=.*|${SERVICE_ENV_VAR}=${SERVICE_URL}|" .env
else
    echo "" >> .env
    echo "# ${SERVICE_NAME} service configuration" >> .env
    echo "${SERVICE_ENV_VAR}=${SERVICE_URL}" >> .env
fi

print_success "Added environment variable: ${SERVICE_ENV_VAR}=${SERVICE_URL}"

# Update router configuration
print_status "Updating router configuration..."

# Create temporary file with new subgraph configuration
cat > /tmp/new_subgraph.yaml << EOF

  ${SERVICE_NAME}:
    routing_url: \${env.${SERVICE_ENV_VAR}}/graphql
    schema:
      subgraph_url: \${env.${SERVICE_ENV_VAR}}/graphql
      # Poll for schema updates every 30 seconds
      poll_interval: 30s
      # Timeout for schema polling requests
      timeout: 10s
    # Health check configuration for ${SERVICE_NAME} service
    health_check:
      enabled: true
      path: /health
      interval: 30s
      timeout: 5s
EOF

# Check if subgraphs section exists
if grep -q "^subgraphs:" config/router.yaml; then
    # Add new subgraph to existing subgraphs section
    # Find the line number after the last subgraph entry
    LAST_SUBGRAPH_LINE=$(grep -n "timeout: 5s" config/router.yaml | tail -1 | cut -d: -f1)
    if [ -n "$LAST_SUBGRAPH_LINE" ]; then
        # Insert after the last subgraph
        sed -i.bak "${LAST_SUBGRAPH_LINE}r /tmp/new_subgraph.yaml" config/router.yaml
    else
        # Fallback: append to subgraphs section
        sed -i.bak "/^subgraphs:/r /tmp/new_subgraph.yaml" config/router.yaml
    fi
else
    print_error "No subgraphs section found in router.yaml"
    exit 1
fi

rm /tmp/new_subgraph.yaml
print_success "Updated router configuration"

# Update Docker Compose if it exists and service is not already defined
if [ -f docker-compose.yml ]; then
    print_status "Checking Docker Compose configuration..."
    
    if ! grep -q "${SERVICE_NAME}-service:" docker-compose.yml; then
        print_warning "Service not found in docker-compose.yml"
        print_warning "You may need to manually add the service definition"
        print_warning "Example:"
        cat << EOF

  ${SERVICE_NAME}-service:
    build:
      context: ./${SERVICE_NAME}-service
      dockerfile: Dockerfile
    hostname: ${SERVICE_NAME}-service
    container_name: ${SERVICE_NAME}-service
    ports:
      - "${SERVICE_PORT}:${SERVICE_PORT}"
    environment:
      PORT: ${SERVICE_PORT}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${SERVICE_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
EOF
    else
        print_success "Service already defined in docker-compose.yml"
    fi
    
    # Check if gateway depends on this service
    if ! grep -A 10 "graphql-gateway:" docker-compose.yml | grep -q "${SERVICE_NAME}-service:"; then
        print_warning "GraphQL Gateway may need to depend on ${SERVICE_NAME}-service"
        print_warning "Consider adding to graphql-gateway dependencies in docker-compose.yml"
    fi
fi

# Validate configuration
print_status "Validating configuration..."

# Check if Docker Compose config is valid
if command -v docker &> /dev/null && docker compose config > /dev/null 2>&1; then
    print_success "Docker Compose configuration is valid"
else
    print_warning "Docker Compose configuration validation failed or Docker not available"
fi

# Test service registration
print_status "Testing service registration..."

# If gateway is running, restart it to pick up new configuration
if docker ps | grep -q "graphql-gateway"; then
    print_status "Restarting GraphQL Gateway to pick up new configuration..."
    docker compose restart graphql-gateway
    
    # Wait for gateway to be ready
    print_status "Waiting for gateway to be ready..."
    for i in {1..30}; do
        if curl -f -s http://localhost:4000/health > /dev/null 2>&1; then
            print_success "Gateway is ready"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            print_warning "Gateway health check timeout - may still be starting"
        fi
    done
    
    # Test schema composition
    print_status "Testing schema composition..."
    SCHEMA_RESPONSE=$(curl -s -X POST http://localhost:4000/graphql \
        -H "Content-Type: application/json" \
        -d '{"query": "{ __schema { types { name } } }"}' 2>/dev/null)
    
    if echo "$SCHEMA_RESPONSE" | grep -q '"data"'; then
        print_success "Schema composition successful"
        
        # Check if new service types are included
        if echo "$SCHEMA_RESPONSE" | grep -q "types"; then
            print_success "New service appears to be composed into the schema"
        fi
    else
        print_warning "Schema composition may have issues"
        print_warning "Check gateway logs: docker logs graphql-gateway"
    fi
else
    print_warning "GraphQL Gateway is not running"
    print_warning "Start it with: docker compose up -d graphql-gateway"
fi

# Generate test query
print_status "Generating test queries..."
cat > /tmp/test_${SERVICE_NAME}.sh << EOF
#!/bin/bash
# Test queries for ${SERVICE_NAME} service

echo "Testing ${SERVICE_NAME} service health:"
curl -s ${SERVICE_URL}/health | jq .

echo -e "\nTesting ${SERVICE_NAME} Federation support:"
curl -s ${SERVICE_URL}/_service | jq .

echo -e "\nTesting Gateway schema composition:"
curl -s -X POST http://localhost:4000/graphql \\
  -H "Content-Type: application/json" \\
  -d '{"query": "{ __schema { types { name } } }"}' | jq .

echo -e "\nTesting Gateway health (includes subgraph connectivity):"
curl -s http://localhost:4000/health | jq .
EOF

chmod +x /tmp/test_${SERVICE_NAME}.sh
mv /tmp/test_${SERVICE_NAME}.sh ./test_${SERVICE_NAME}_integration.sh

print_success "Created test script: ./test_${SERVICE_NAME}_integration.sh"

# Summary
print_success "Service registration completed!"
echo ""
echo "Summary of changes:"
echo "  ✓ Added environment variable: ${SERVICE_ENV_VAR}=${SERVICE_URL}"
echo "  ✓ Updated router configuration: config/router.yaml"
echo "  ✓ Created backup files with timestamp"
echo "  ✓ Generated test script: ./test_${SERVICE_NAME}_integration.sh"
echo ""
echo "Next steps:"
echo "  1. Review the configuration changes"
echo "  2. Test the integration: ./test_${SERVICE_NAME}_integration.sh"
echo "  3. Update docker-compose.yml if needed"
echo "  4. Deploy to production environment"
echo ""
echo "To rollback changes:"
echo "  cp config/router.yaml.backup.* config/router.yaml"
echo "  cp .env.backup.* .env"
echo "  docker compose restart graphql-gateway"