#!/bin/bash

# Script to test GraphQL Gateway connectivity to subgraph services
# This verifies that the gateway can reach your running services

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

# Load environment variables
if [ -f .env ]; then
    source .env
fi

print_status "🔍 Testing GraphQL Gateway connectivity to subgraph services"

# Test Products Service
print_status "Testing Products Service connectivity..."
PRODUCTS_URL="${PRODUCTS_SERVICE_URL:-http://localhost:8082}"

if curl -f -s "${PRODUCTS_URL}/health" > /dev/null 2>&1; then
    print_success "✅ Products Service health check passed ($PRODUCTS_URL/health)"
else
    print_error "❌ Products Service health check failed ($PRODUCTS_URL/health)"
    print_error "   Make sure your Products Service is running on the correct port"
fi

if curl -f -s "${PRODUCTS_URL}/graphql" -X POST -H "Content-Type: application/json" -d '{"query": "{ __typename }"}' > /dev/null 2>&1; then
    print_success "✅ Products Service GraphQL endpoint accessible ($PRODUCTS_URL/graphql)"
else
    print_warning "⚠️  Products Service GraphQL endpoint not accessible ($PRODUCTS_URL/graphql)"
fi

# Test Ratings Service
print_status "Testing Ratings Service connectivity..."
RATINGS_URL="${RATINGS_SERVICE_URL:-http://localhost:8083}"

if curl -f -s "${RATINGS_URL}/health" > /dev/null 2>&1; then
    print_success "✅ Ratings Service health check passed ($RATINGS_URL/health)"
else
    print_error "❌ Ratings Service health check failed ($RATINGS_URL/health)"
    print_error "   Make sure your Ratings Service is running on the correct port"
fi

if curl -f -s "${RATINGS_URL}/graphql" -X POST -H "Content-Type: application/json" -d '{"query": "{ __typename }"}' > /dev/null 2>&1; then
    print_success "✅ Ratings Service GraphQL endpoint accessible ($RATINGS_URL/graphql)"
else
    print_warning "⚠️  Ratings Service GraphQL endpoint not accessible ($RATINGS_URL/graphql)"
fi

# Test GraphQL Gateway
print_status "Testing GraphQL Gateway..."
GATEWAY_URL="http://localhost:${GRAPHQL_GATEWAY_PORT:-4000}"

if curl -f -s "${GATEWAY_URL}/health" > /dev/null 2>&1; then
    print_success "✅ GraphQL Gateway health check passed ($GATEWAY_URL/health)"
else
    print_error "❌ GraphQL Gateway health check failed ($GATEWAY_URL/health)"
    print_error "   Check GraphQL Gateway logs: docker logs graphql-gateway"
fi

# Test Federation Schema Composition
print_status "Testing schema composition..."
if curl -f -s "${GATEWAY_URL}/graphql" -X POST -H "Content-Type: application/json" -d '{"query": "{ __schema { types { name } } }"}' > /dev/null 2>&1; then
    print_success "✅ GraphQL Gateway schema composition working"
else
    print_warning "⚠️  GraphQL Gateway schema composition may have issues"
fi

# Summary
echo ""
print_status "📋 Service Configuration Summary"
echo "=================================="
echo "Products Service: $PRODUCTS_URL"
echo "Ratings Service:  $RATINGS_URL"
echo "GraphQL Gateway:  $GATEWAY_URL"
echo ""
echo "🔧 Configuration Files:"
echo "  Environment: .env"
echo "  Router Config: config/router.yaml"
echo ""
echo "💡 Next Steps:"
echo "  1. Ensure both services are running and healthy"
echo "  2. Check that services implement GraphQL Federation"
echo "  3. Register services with gateway if needed"
echo "  4. Test federated queries"

print_success "🎉 Service connectivity test completed!"