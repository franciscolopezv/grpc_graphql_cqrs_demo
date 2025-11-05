#!/bin/bash

# Script to register a new GraphQL service with Apollo Studio (No Gateway Restart Required!)
# Usage: ./scripts/register-service-apollo.sh <service-name> <service-url> <schema-file>

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
if [ $# -lt 3 ]; then
    print_error "Usage: $0 <service-name> <service-url> <schema-file>"
    print_error "Example: $0 inventory http://inventory-service:8083 ./inventory-service/schema.graphql"
    exit 1
fi

SERVICE_NAME=$1
SERVICE_URL=$2
SCHEMA_FILE=$3

print_status "🚀 Registering service with Apollo Studio (Zero Downtime!)"
print_status "Service: $SERVICE_NAME"
print_status "URL: $SERVICE_URL"
print_status "Schema: $SCHEMA_FILE"

# Validate inputs
if ! [[ "$SERVICE_NAME" =~ ^[a-z0-9-]+$ ]]; then
    print_error "Service name must be lowercase alphanumeric with hyphens only"
    exit 1
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    print_error "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# Check required environment variables
if [ -z "$APOLLO_KEY" ]; then
    print_error "APOLLO_KEY environment variable is required"
    print_error "Get your API key from: https://studio.apollographql.com/"
    exit 1
fi

if [ -z "$APOLLO_GRAPH_REF" ]; then
    print_error "APOLLO_GRAPH_REF environment variable is required"
    print_error "Format: your-graph-id@your-variant (e.g., platform-api@production)"
    exit 1
fi

# Check if Apollo Rover is installed
if ! command -v rover &> /dev/null; then
    print_status "Installing Apollo Rover..."
    if command -v npm &> /dev/null; then
        npm install -g @apollo/rover
    elif command -v curl &> /dev/null; then
        curl -sSL https://rover.apollo.dev/nix/latest | sh
        export PATH="$HOME/.rover/bin:$PATH"
    else
        print_error "Please install Apollo Rover: https://www.apollographql.com/docs/rover/getting-started"
        exit 1
    fi
fi

# Validate service is reachable
print_status "🔍 Validating service..."
if curl -f -s "${SERVICE_URL}/health" > /dev/null; then
    print_success "Service health check passed"
else
    print_warning "Service health check failed - continuing anyway"
fi

# Check Federation support
if curl -f -s "${SERVICE_URL}/_service" > /dev/null; then
    print_success "Service supports Federation"
else
    print_error "Service does not support Federation (_service endpoint missing)"
    exit 1
fi

# Validate schema file
print_status "🔍 Validating schema..."
if grep -q "@key\|@shareable\|@external" "$SCHEMA_FILE"; then
    print_success "Schema contains Federation directives"
else
    print_warning "Schema may be missing Federation directives"
fi

# Check current subgraphs
print_status "📋 Checking existing subgraphs..."
EXISTING_SUBGRAPHS=$(rover subgraph list "$APOLLO_GRAPH_REF" 2>/dev/null || echo "")

if echo "$EXISTING_SUBGRAPHS" | grep -q "$SERVICE_NAME"; then
    print_warning "Subgraph '$SERVICE_NAME' already exists - will update"
    ACTION="update"
else
    print_success "New subgraph '$SERVICE_NAME' will be created"
    ACTION="create"
fi

# Publish schema to Apollo Studio
print_status "🚀 Publishing schema to Apollo Studio..."
if rover subgraph publish "$APOLLO_GRAPH_REF" \
    --name "$SERVICE_NAME" \
    --schema "$SCHEMA_FILE" \
    --routing-url "$SERVICE_URL/graphql"; then
    
    print_success "Schema published successfully!"
    
    if [ "$ACTION" = "create" ]; then
        print_success "✨ New service '$SERVICE_NAME' registered!"
    else
        print_success "🔄 Service '$SERVICE_NAME' updated!"
    fi
else
    print_error "Failed to publish schema"
    exit 1
fi

# Check composition status
print_status "🔍 Checking schema composition..."
sleep 2  # Give Apollo Studio time to process

COMPOSITION_STATUS=$(rover supergraph fetch "$APOLLO_GRAPH_REF" --output - 2>/dev/null | head -1 || echo "error")

if [[ "$COMPOSITION_STATUS" == *"schema"* ]] || [[ "$COMPOSITION_STATUS" == *"directive"* ]]; then
    print_success "Schema composition successful!"
else
    print_warning "Schema composition may have issues - check Apollo Studio"
fi

# Gateway will auto-update (no restart needed!)
print_status "⏱️  Gateway will automatically update in ~10 seconds..."

# Wait and test gateway update
print_status "🧪 Testing gateway update..."
for i in {1..12}; do
    sleep 5
    
    # Test if gateway has the new service
    GATEWAY_SCHEMA=$(curl -s -X POST http://localhost:4000/graphql \
        -H "Content-Type: application/json" \
        -d '{"query": "{ __schema { types { name } } }"}' 2>/dev/null || echo "")
    
    if echo "$GATEWAY_SCHEMA" | grep -q '"data"'; then
        print_success "Gateway is responding"
        
        # Check if new types are available (basic check)
        TYPE_COUNT=$(echo "$GATEWAY_SCHEMA" | grep -o '"name"' | wc -l)
        if [ "$TYPE_COUNT" -gt 10 ]; then
            print_success "Schema appears to be composed (found $TYPE_COUNT types)"
            break
        fi
    fi
    
    if [ $i -eq 12 ]; then
        print_warning "Gateway update verification timed out"
        print_warning "Check gateway logs: docker logs graphql-gateway"
    else
        echo -n "."
    fi
done

echo ""

# Generate test queries
print_status "📝 Generating test queries..."
cat > "./test_${SERVICE_NAME}_apollo.sh" << EOF
#!/bin/bash
# Test queries for ${SERVICE_NAME} service (Apollo Studio mode)

echo "🔍 Testing ${SERVICE_NAME} service health:"
curl -s ${SERVICE_URL}/health | jq . 2>/dev/null || curl -s ${SERVICE_URL}/health

echo -e "\n🔍 Testing ${SERVICE_NAME} Federation support:"
curl -s ${SERVICE_URL}/_service | jq . 2>/dev/null || curl -s ${SERVICE_URL}/_service

echo -e "\n🔍 Testing Gateway schema (should include ${SERVICE_NAME} types):"
curl -s -X POST http://localhost:4000/graphql \\
  -H "Content-Type: application/json" \\
  -d '{"query": "{ __schema { types { name } } }"}' | jq . 2>/dev/null || \\
curl -s -X POST http://localhost:4000/graphql \\
  -H "Content-Type: application/json" \\
  -d '{"query": "{ __schema { types { name } } }"}'

echo -e "\n🔍 Testing Gateway health:"
curl -s http://localhost:4000/health | jq . 2>/dev/null || curl -s http://localhost:4000/health

echo -e "\n📊 Apollo Studio Dashboard:"
echo "https://studio.apollographql.com/graph/$(echo $APOLLO_GRAPH_REF | cut -d'@' -f1)"
EOF

chmod +x "./test_${SERVICE_NAME}_apollo.sh"

# Create rollback script
cat > "./rollback_${SERVICE_NAME}.sh" << EOF
#!/bin/bash
# Rollback ${SERVICE_NAME} service registration

echo "🔄 Rolling back ${SERVICE_NAME} service..."

# Delete subgraph from Apollo Studio
rover subgraph delete "$APOLLO_GRAPH_REF" --name "$SERVICE_NAME"

echo "✅ Service ${SERVICE_NAME} removed from Apollo Studio"
echo "⏱️  Gateway will automatically update in ~10 seconds"
EOF

chmod +x "./rollback_${SERVICE_NAME}.sh"

# Summary
print_success "🎉 Service registration completed!"
echo ""
echo "📋 Summary:"
echo "  ✅ Schema published to Apollo Studio"
echo "  ✅ Gateway will auto-update (NO RESTART NEEDED!)"
echo "  ✅ Generated test script: ./test_${SERVICE_NAME}_apollo.sh"
echo "  ✅ Generated rollback script: ./rollback_${SERVICE_NAME}.sh"
echo ""
echo "🔗 Links:"
echo "  📊 Apollo Studio: https://studio.apollographql.com/graph/$(echo $APOLLO_GRAPH_REF | cut -d'@' -f1)"
echo "  🧪 Test your service: ./test_${SERVICE_NAME}_apollo.sh"
echo ""
echo "🚀 Next steps:"
echo "  1. Wait ~10 seconds for gateway to update"
echo "  2. Test the integration: ./test_${SERVICE_NAME}_apollo.sh"
echo "  3. Monitor in Apollo Studio dashboard"
echo "  4. Deploy to other environments using the same process"
echo ""
echo "💡 Benefits of Apollo Studio approach:"
echo "  ✅ Zero downtime deployments"
echo "  ✅ Schema validation and change detection"
echo "  ✅ Team collaboration and approval workflows"
echo "  ✅ Performance monitoring and analytics"
echo "  ✅ Easy rollbacks if needed"