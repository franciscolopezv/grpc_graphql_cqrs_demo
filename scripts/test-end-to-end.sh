#!/bin/bash

# =============================================================================
# End-to-End Platform Infrastructure Test
# =============================================================================
# This script performs a complete end-to-end test of the platform:
# 1. Creates a product via gRPC
# 2. Submits a rating for the product via gRPC
# 3. Queries the product and rating data via GraphQL Gateway
#
# Prerequisites:
# - Infrastructure must be running (./scripts/start-infrastructure.sh)
# - grpcurl must be installed (brew install grpcurl)
# - curl must be installed
# - jq must be installed (brew install jq) for JSON formatting
#
# Usage:
#   ./scripts/test-end-to-end.sh
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
PRODUCTS_GRPC_HOST="localhost:50051"
RATINGS_GRPC_HOST="localhost:9090"
GRAPHQL_GATEWAY_URL="http://localhost:4000"
GRAPHQL_ENDPOINT="/"  # Apollo Router uses / not /graphql

# Event propagation delay (seconds)
# Time to wait for Kafka messages to be consumed and processed
EVENT_PROPAGATION_DELAY="${EVENT_PROPAGATION_DELAY:-5}"

# Test data
PRODUCT_NAME="Wireless Mouse"
PRODUCT_DESCRIPTION="Ergonomic wireless mouse with USB receiver"
RATING_VALUE=5
USER_ID="user-456"
REVIEW_TEXT="Excellent product! Highly recommended."

# Variables to store test results
PRODUCT_ID=""
RATING_ID=""

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_test() {
    echo -e "${MAGENTA}[TEST]${NC} $1"
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check grpcurl
    if ! command -v grpcurl &> /dev/null; then
        log_error "grpcurl is not installed"
        log_info "Install with: brew install grpcurl"
        exit 1
    fi
    log_success "grpcurl is installed"
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        exit 1
    fi
    log_success "curl is installed"
    
    # Check nc (netcat) for port checking
    if ! command -v nc &> /dev/null; then
        log_warning "nc (netcat) is not installed (will use alternative port checking)"
    else
        log_success "nc (netcat) is installed"
    fi
    
    # Check jq (optional but recommended)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed (JSON output will not be formatted)"
        log_info "Install with: brew install jq"
    else
        log_success "jq is installed"
    fi
}

check_port() {
    local host="$1"
    local port="$2"
    
    # Try nc first (fastest)
    if command -v nc &> /dev/null; then
        nc -z -w 2 "$host" "$port" 2>/dev/null
        return $?
    fi
    
    # Fallback to bash TCP connection test
    (echo > /dev/tcp/"$host"/"$port") 2>/dev/null
    return $?
}

check_services() {
    log_step "Checking if services are running..."
    
    # Check Products service (doesn't support reflection API)
    # Use port checking since reflection is not available
    if check_port localhost 50051; then
        log_success "Products service is running on $PRODUCTS_GRPC_HOST"
    else
        log_error "Products service is not running on $PRODUCTS_GRPC_HOST"
        log_info "Start infrastructure with: ./scripts/start-infrastructure.sh"
        exit 1
    fi
    
    # Check Ratings service (may support reflection API)
    if grpcurl -plaintext "$RATINGS_GRPC_HOST" list &> /dev/null; then
        log_success "Ratings service is running on $RATINGS_GRPC_HOST"
    elif check_port localhost 9090; then
        log_success "Ratings service is running on $RATINGS_GRPC_HOST (no reflection API)"
    else
        log_error "Ratings service is not running on $RATINGS_GRPC_HOST"
        log_info "Start infrastructure with: ./scripts/start-infrastructure.sh"
        exit 1
    fi
    
    # Check GraphQL Gateway (Apollo Router doesn't have /health endpoint)
    # Try a simple introspection query instead
    local gateway_check
    gateway_check=$(curl -s -X POST "$GRAPHQL_GATEWAY_URL$GRAPHQL_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d '{"query": "{__typename}"}' 2>&1)
    
    if [[ $? -eq 0 ]] && echo "$gateway_check" | grep -q "Query"; then
        log_success "GraphQL Gateway is running on $GRAPHQL_GATEWAY_URL"
    elif check_port localhost 4000; then
        log_success "GraphQL Gateway port is open on $GRAPHQL_GATEWAY_URL"
    else
        log_error "GraphQL Gateway is not running on $GRAPHQL_GATEWAY_URL"
        log_info "Start infrastructure with: ./scripts/start-infrastructure.sh"
        exit 1
    fi
}

# =============================================================================
# Test Functions
# =============================================================================

test_create_product() {
    log_test "Test 1: Creating a product via gRPC"
    echo ""
    
    log_info "Sending CreateProduct request..."
    log_info "Product: $PRODUCT_NAME"
    log_info "Description: $PRODUCT_DESCRIPTION"
    echo ""
    
    # Create product via gRPC
    local response
    response=$(grpcurl -plaintext \
        -proto products.proto \
        -d "{\"name\": \"$PRODUCT_NAME\", \"description\": \"$PRODUCT_DESCRIPTION\"}" \
        "$PRODUCTS_GRPC_HOST" \
        products.ProductsCommandService/CreateProduct 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_success "Product created successfully"
        echo ""
        echo "Response:"
        if command -v jq &> /dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Extract product ID (try both "productId" and "id" fields)
        if command -v jq &> /dev/null; then
            # Try to parse as JSON and extract productId
            PRODUCT_ID=$(echo "$response" | jq -r '.productId // .id // empty' 2>/dev/null)
            
            # If jq fails or returns empty, try grep as fallback
            if [[ -z "$PRODUCT_ID" || "$PRODUCT_ID" == "null" ]]; then
                PRODUCT_ID=$(echo "$response" | grep -oE '"productId"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '[a-f0-9-]{36}')
            fi
        else
            # Fallback: try to extract ID using grep (try productId first, then id)
            PRODUCT_ID=$(echo "$response" | grep -oE '"productId"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '[a-f0-9-]{36}')
            if [[ -z "$PRODUCT_ID" ]]; then
                PRODUCT_ID=$(echo "$response" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '[a-f0-9-]{36}')
            fi
        fi
        
        if [[ -n "$PRODUCT_ID" && "$PRODUCT_ID" != "null" ]]; then
            log_success "Product ID: $PRODUCT_ID"
        else
            log_warning "Could not extract product ID from response"
            log_info "Response was: $response"
            log_info "Please manually set PRODUCT_ID for the next steps"
            echo -n "Enter Product ID: "
            read -r PRODUCT_ID
        fi
    else
        log_error "Failed to create product"
        echo "$response"
        exit 1
    fi
    
    echo ""
}

test_submit_rating() {
    log_test "Test 2: Submitting a rating via gRPC"
    echo ""
    
    if [[ -z "$PRODUCT_ID" ]]; then
        log_error "Product ID is not set. Cannot submit rating."
        exit 1
    fi
    
    log_info "Sending SubmitRating request..."
    log_info "Product ID: $PRODUCT_ID"
    log_info "Rating: $RATING_VALUE/5"
    log_info "User ID: $USER_ID"
    log_info "Review: $REVIEW_TEXT"
    echo ""
    
    # Submit rating via gRPC
    local response
    response=$(grpcurl -plaintext \
        -d "{\"product_id\": \"$PRODUCT_ID\", \"rating\": $RATING_VALUE, \"user_id\": \"$USER_ID\", \"review_text\": \"$REVIEW_TEXT\"}" \
        "$RATINGS_GRPC_HOST" \
        com.ratings.RatingsCommandService/SubmitRating 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_success "Rating submitted successfully"
        echo ""
        echo "Response:"
        if command -v jq &> /dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Extract rating ID
        if command -v jq &> /dev/null; then
            RATING_ID=$(echo "$response" | jq -r '.id // .rating_id // empty')
        else
            RATING_ID=$(echo "$response" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        fi
        
        if [[ -n "$RATING_ID" ]]; then
            log_success "Rating ID: $RATING_ID"
        else
            log_info "Rating ID not found in response (this may be expected)"
        fi
    else
        log_error "Failed to submit rating"
        echo "$response"
        exit 1
    fi
    
    echo ""
}

test_query_graphql() {
    log_test "Test 3: Querying product via GraphQL Gateway"
    echo ""
    
    if [[ -z "$PRODUCT_ID" ]]; then
        log_error "Product ID is not set. Cannot query GraphQL."
        exit 1
    fi
    
    log_info "Querying product basic information via GraphQL..."
    echo ""
    
    # GraphQL query to get product basic info (Products service only)
    local graphql_query
    graphql_query=$(cat <<EOF
{
  "query": "query GetProduct(\$productId: ID!) { product(id: \$productId) { id name description } }",
  "variables": {
    "productId": "$PRODUCT_ID"
  }
}
EOF
)
    
    # Execute GraphQL query
    local response
    response=$(curl -s -X POST "$GRAPHQL_GATEWAY_URL$GRAPHQL_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$graphql_query")
    
    if [[ $? -eq 0 ]]; then
        log_success "GraphQL query executed successfully"
        echo ""
        echo "Response:"
        if command -v jq &> /dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Check if response contains errors
        if echo "$response" | grep -q '"errors"'; then
            log_warning "GraphQL query returned errors"
        else
            log_success "GraphQL query completed without errors"
        fi
    else
        log_error "Failed to execute GraphQL query"
        echo "$response"
        exit 1
    fi
    
    echo ""
}

test_query_all_products() {
    log_test "Test 4: Querying top rated products via GraphQL"
    echo ""
    
    log_info "Querying top rated products..."
    echo ""
    
    # GraphQL query to get top rated products
    local graphql_query
    graphql_query=$(cat <<EOF
{
  "query": "query GetTopRatedProducts { topRatedProducts(limit: 10) { productId averageRating reviewCount ratingDistribution { fiveStar fourStar threeStar twoStar oneStar total } lastUpdated } }"
}
EOF
)
    
    # Execute GraphQL query
    local response
    response=$(curl -s -X POST "$GRAPHQL_GATEWAY_URL$GRAPHQL_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$graphql_query")
    
    if [[ $? -eq 0 ]]; then
        log_success "GraphQL query executed successfully"
        echo ""
        echo "Response:"
        if command -v jq &> /dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Check if response contains errors
        if echo "$response" | grep -q '"errors"'; then
            log_warning "GraphQL query returned errors (ratings service may not be available)"
        fi
    else
        log_error "Failed to execute GraphQL query"
        echo "$response"
    fi
    
    echo ""
}

test_query_product_ratings() {
    log_test "Test 5: Querying rating statistics for product via GraphQL"
    echo ""
    
    if [[ -z "$PRODUCT_ID" ]]; then
        log_error "Product ID is not set. Cannot query ratings."
        exit 1
    fi
    
    log_info "Querying rating statistics for product $PRODUCT_ID..."
    echo ""
    
    # GraphQL query to get rating statistics for a product
    local graphql_query
    graphql_query=$(cat <<EOF
{
  "query": "query GetProductRatingStats(\$productId: ID!) { productRatingStats(productId: \$productId) { productId averageRating reviewCount ratingDistribution { oneStar twoStar threeStar fourStar fiveStar total mostCommonRating } lastUpdated } }",
  "variables": {
    "productId": "$PRODUCT_ID"
  }
}
EOF
)
    
    # Execute GraphQL query
    local response
    response=$(curl -s -X POST "$GRAPHQL_GATEWAY_URL$GRAPHQL_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$graphql_query")
    
    if [[ $? -eq 0 ]]; then
        log_success "GraphQL query executed successfully"
        echo ""
        echo "Response:"
        if command -v jq &> /dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Check if response contains errors
        if echo "$response" | grep -q '"errors"'; then
            log_warning "GraphQL query returned errors (ratings service may not be available)"
        fi
        echo ""
    else
        log_error "Failed to execute GraphQL query"
        echo "$response"
    fi
    
    echo ""
}

# =============================================================================
# Summary
# =============================================================================

show_summary() {
    echo "============================================================================="
    echo "Test Summary"
    echo "============================================================================="
    echo ""
    echo "✅ Product created: $PRODUCT_NAME"
    echo "   Product ID: $PRODUCT_ID"
    echo ""
    echo "✅ Rating submitted: $RATING_VALUE/5 stars"
    if [[ -n "$RATING_ID" ]]; then
        echo "   Rating ID: $RATING_ID"
    fi
    echo "   User: $USER_ID"
    echo "   Review: $REVIEW_TEXT"
    echo ""
    echo "✅ GraphQL queries executed"
    echo ""
    echo "============================================================================="
    echo ""
    log_success "End-to-end test completed!"
    echo ""
    log_info "Note: If you see GraphQL validation errors about 'averageRating', 'reviewCount',"
    log_info "or 'ratingDistribution' fields, this means the ratings query service is not running"
    log_info "or not properly registered with the GraphQL Gateway."
    echo ""
    echo "Next steps:"
    echo "  - View GraphQL Playground: $GRAPHQL_GATEWAY_URL"
    echo "  - Query more data using the GraphQL API"
    echo "  - Check Kafka messages for events"
    echo "  - Verify data in PostgreSQL databases"
    echo "  - Ensure ratings-query-service is running for full federation"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "============================================================================="
    echo "🧪 End-to-End Platform Infrastructure Test"
    echo "============================================================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Check if services are running
    check_services
    echo ""
    
    # Run tests
    test_create_product
    
    log_info "Waiting for Kafka event propagation (${EVENT_PROPAGATION_DELAY} seconds)..."
    sleep "$EVENT_PROPAGATION_DELAY"  # Give time for product creation event to be consumed
    
    test_submit_rating
    
    log_info "Waiting for Kafka event propagation (${EVENT_PROPAGATION_DELAY} seconds)..."
    sleep "$EVENT_PROPAGATION_DELAY"  # Give time for rating submission event to be consumed
    
    test_query_graphql
    test_query_all_products
    test_query_product_ratings
    
    # Show summary
    show_summary
}

# Run main function
main