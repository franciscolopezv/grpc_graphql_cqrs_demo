#!/bin/bash

# Script to test database connectivity for service development
# This simulates how a service would connect to the shared PostgreSQL

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

print_status "🔍 Testing database connectivity for service development"

# Test database connectivity from within the network (simulating a service)
print_status "Testing database connection from within Docker network..."

# Test connection to each database
DATABASES=("products_db" "ratings_db" "platform_db")

for db in "${DATABASES[@]}"; do
    print_status "Testing connection to $db..."
    
    if docker run --rm --network "$NETWORK_NAME" postgres:15-alpine \
        psql "postgresql://postgres:postgres@postgres:5432/$db" \
        -c "SELECT current_database(), version();" > /dev/null 2>&1; then
        print_success "✅ Successfully connected to $db"
    else
        print_error "❌ Failed to connect to $db"
    fi
done

# Test creating a table (simulating service initialization)
print_status "Testing table creation (simulating service initialization)..."

docker run --rm --network "$NETWORK_NAME" postgres:15-alpine \
    psql "postgresql://postgres:postgres@postgres:5432/products_db" \
    -c "
    CREATE TABLE IF NOT EXISTS test_products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO test_products (name) VALUES ('Test Product 1'), ('Test Product 2');
    
    SELECT * FROM test_products;
    " && print_success "✅ Table creation and data insertion successful"

# Test from host machine (external access)
print_status "Testing database connection from host machine..."

if docker exec postgres psql -U postgres -d products_db -c "SELECT COUNT(*) FROM test_products;" > /dev/null 2>&1; then
    print_success "✅ Host machine can connect to database"
else
    print_error "❌ Host machine cannot connect to database"
fi

# Show connection examples
print_status "📋 Database Connection Examples"
echo "================================"
echo ""
echo "🔗 Connection Strings for Services:"
echo "  Products DB:  postgresql://postgres:postgres@postgres:5432/products_db"
echo "  Ratings DB:   postgresql://postgres:postgres@postgres:5432/ratings_db"
echo "  Platform DB:  postgresql://postgres:postgres@postgres:5432/platform_db"
echo ""
echo "🔗 Connection from Host Machine:"
echo "  Products DB:  postgresql://postgres:postgres@localhost:5432/products_db"
echo "  Ratings DB:   postgresql://postgres:postgres@localhost:5432/ratings_db"
echo "  Platform DB:  postgresql://postgres:postgres@localhost:5432/platform_db"
echo ""
echo "🛠️  Useful Commands:"
echo "  Connect to DB: docker exec -it postgres psql -U postgres -d products_db"
echo "  List DBs:      docker exec postgres psql -U postgres -c '\\l'"
echo "  List Tables:   docker exec postgres psql -U postgres -d products_db -c '\\dt'"

print_success "🎉 Database connectivity test completed!"