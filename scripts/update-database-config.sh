#!/bin/bash

# Script to update database configuration from platform_user to postgres
# This fixes the PostgreSQL user configuration across all files

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

print_status "🔄 Updating database configuration from platform_user to postgres"

# Files to update
FILES=(
    "docs/examples/new-service-registration.md"
    "docs/local-development-setup.md"
    "scripts/setup-local-development.sh"
    "scripts/test-network-connectivity.sh"
    "scripts/start-infrastructure.sh"
    ".env.template"
    "README-GraphQL-Gateway.md"
    "tests/setup.js"
    "tests/docker-compose.test.js"
    "tests/docker-compose-simple.test.js"
    "docs/postgresql-setup.md"
)

# Update each file
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        print_status "Updating $file..."
        
        # Update connection strings
        sed -i.bak 's/postgresql:\/\/platform_user:platform_password@/postgresql:\/\/postgres:postgres@/g' "$file"
        
        # Update psql commands
        sed -i.bak 's/psql -U platform_user/psql -U postgres/g' "$file"
        sed -i.bak 's/pg_isready -U platform_user/pg_isready -U postgres/g' "$file"
        
        # Update environment variables in examples
        sed -i.bak 's/POSTGRES_USER=platform_user/POSTGRES_USER=postgres/g' "$file"
        sed -i.bak 's/POSTGRES_PASSWORD=platform_password/POSTGRES_PASSWORD=postgres/g' "$file"
        
        # Update user references in text
        sed -i.bak 's/platform_user/postgres/g' "$file"
        sed -i.bak 's/platform_password/postgres/g' "$file"
        
        # Remove backup file
        rm -f "$file.bak"
        
        print_success "✅ Updated $file"
    else
        print_warning "⚠️  File not found: $file"
    fi
done

print_success "🎉 Database configuration update completed!"
echo ""
echo "📋 Summary of changes:"
echo "  - Changed database user from 'platform_user' to 'postgres'"
echo "  - Changed database password from 'platform_password' to 'postgres'"
echo "  - Updated all connection strings and commands"
echo ""
echo "💡 Next steps:"
echo "  1. Restart services if needed: docker compose restart"
echo "  2. Test database connectivity: docker exec postgres psql -U postgres -c 'SELECT version();'"