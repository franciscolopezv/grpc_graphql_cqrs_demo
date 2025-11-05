#!/bin/bash

# =============================================================================
# Platform Infrastructure Configuration Validation Script
# =============================================================================
# This script validates that all required environment variables are set
# and have valid values before starting the infrastructure services.
#
# Usage:
#   ./scripts/validate-config.sh [environment]
#
# Arguments:
#   environment: Optional environment name (development, staging, production)
#
# Exit codes:
#   0: All validations passed
#   1: Validation failed
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_TEMPLATE="$PROJECT_ROOT/.env.template"

# Environment type (development, staging, production)
ENVIRONMENT="${1:-development}"

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

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
    ((VALIDATION_WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((VALIDATION_ERRORS++))
}

# =============================================================================
# Validation Functions
# =============================================================================

check_env_file() {
    log_info "Checking environment file..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_info "Copy .env.template to .env and configure your values:"
        log_info "  cp .env.template .env"
        return 1
    fi
    
    log_success ".env file found"
    return 0
}

load_env_file() {
    log_info "Loading environment variables from .env file..."
    
    # Load .env file while preserving existing environment variables
    set -a
    source "$ENV_FILE"
    set +a
    
    log_success "Environment variables loaded"
}

validate_required_vars() {
    log_info "Validating required environment variables..."
    
    local required_vars=(
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "POSTGRES_HOST"
        "POSTGRES_PORT"
        "POSTGRES_MULTIPLE_DATABASES"
        "GRAPHQL_GATEWAY_PORT"
        "PRODUCTS_SERVICE_URL"
        "RATINGS_SERVICE_URL"
        "KAFKA_ZOOKEEPER_CONNECT"
        "ZOOKEEPER_CLIENT_PORT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
        else
            log_success "$var is set"
        fi
    done
}

validate_port_numbers() {
    log_info "Validating port number configurations..."
    
    local port_vars=(
        "POSTGRES_PORT"
        "GRAPHQL_GATEWAY_PORT"
        "ZOOKEEPER_CLIENT_PORT"
        "KAFKA_JMX_PORT"
    )
    
    for var in "${port_vars[@]}"; do
        local port_value="${!var:-}"
        if [[ -n "$port_value" ]]; then
            if [[ ! "$port_value" =~ ^[0-9]+$ ]] || [[ "$port_value" -lt 1 ]] || [[ "$port_value" -gt 65535 ]]; then
                log_error "$var has invalid port number: $port_value (must be 1-65535)"
            else
                log_success "$var has valid port number: $port_value"
            fi
        fi
    done
}

validate_service_urls() {
    log_info "Validating service URL configurations..."
    
    local url_vars=(
        "PRODUCTS_SERVICE_URL"
        "RATINGS_SERVICE_URL"
    )
    
    for var in "${url_vars[@]}"; do
        local url_value="${!var:-}"
        if [[ -n "$url_value" ]]; then
            if [[ ! "$url_value" =~ ^https?:// ]]; then
                log_error "$var has invalid URL format: $url_value (must start with http:// or https://)"
            else
                log_success "$var has valid URL format: $url_value"
            fi
        fi
    done
}

validate_database_config() {
    log_info "Validating database configuration..."
    
    # Check database names
    local db_names="${POSTGRES_MULTIPLE_DATABASES:-}"
    if [[ -n "$db_names" ]]; then
        IFS=',' read -ra DB_ARRAY <<< "$db_names"
        for db in "${DB_ARRAY[@]}"; do
            db=$(echo "$db" | xargs) # trim whitespace
            if [[ ! "$db" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
                log_error "Invalid database name: $db (must start with letter, contain only letters, numbers, and underscores)"
            else
                log_success "Valid database name: $db"
            fi
        done
    fi
    
    # Check password strength for non-development environments
    if [[ "$ENVIRONMENT" != "development" ]]; then
        local password="${POSTGRES_PASSWORD:-}"
        if [[ ${#password} -lt 12 ]]; then
            log_warning "PostgreSQL password is shorter than 12 characters (recommended for $ENVIRONMENT)"
        fi
        
        if [[ "$password" == *"password"* ]] || [[ "$password" == *"123"* ]]; then
            log_warning "PostgreSQL password appears to be weak (contains common patterns)"
        fi
    fi
}

validate_kafka_config() {
    log_info "Validating Kafka configuration..."
    
    # Check replication factors for production
    if [[ "$ENVIRONMENT" == "production" ]]; then
        local replication_factor="${KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR:-1}"
        if [[ "$replication_factor" -lt 3 ]]; then
            log_warning "Kafka replication factor is $replication_factor (recommended: 3+ for production)"
        fi
    fi
    
    # Validate Zookeeper connection string
    local zk_connect="${KAFKA_ZOOKEEPER_CONNECT:-}"
    if [[ -n "$zk_connect" ]]; then
        if [[ ! "$zk_connect" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
            log_error "Invalid Zookeeper connection string: $zk_connect (expected format: host:port)"
        else
            log_success "Valid Zookeeper connection string: $zk_connect"
        fi
    fi
}

validate_logging_config() {
    log_info "Validating logging configuration..."
    
    local valid_log_levels=("error" "warn" "info" "debug" "trace")
    
    local log_vars=(
        "APOLLO_ROUTER_LOG"
        "RUST_LOG"
    )
    
    for var in "${log_vars[@]}"; do
        local log_level="${!var:-}"
        if [[ -n "$log_level" ]]; then
            if [[ ! " ${valid_log_levels[*]} " =~ " ${log_level} " ]]; then
                log_error "$var has invalid log level: $log_level (valid: ${valid_log_levels[*]})"
            else
                log_success "$var has valid log level: $log_level"
            fi
        fi
    done
}

validate_environment_specific() {
    log_info "Validating environment-specific configuration for: $ENVIRONMENT"
    
    case "$ENVIRONMENT" in
        "development")
            log_info "Development environment - using relaxed validation"
            ;;
        "staging")
            log_info "Staging environment - checking for secure configurations"
            validate_secure_passwords
            validate_external_urls
            ;;
        "production")
            log_info "Production environment - enforcing strict security"
            validate_secure_passwords
            validate_external_urls
            validate_production_settings
            ;;
        *)
            log_warning "Unknown environment: $ENVIRONMENT (expected: development, staging, production)"
            ;;
    esac
}

validate_secure_passwords() {
    local password="${POSTGRES_PASSWORD:-}"
    
    if [[ "$password" == "platform_password" ]] || [[ "$password" == "password" ]]; then
        log_error "Using default password in $ENVIRONMENT environment (security risk)"
    fi
}

validate_external_urls() {
    local products_url="${PRODUCTS_SERVICE_URL:-}"
    local ratings_url="${RATINGS_SERVICE_URL:-}"
    
    if [[ "$products_url" == *"localhost"* ]] || [[ "$products_url" == *"127.0.0.1"* ]]; then
        log_warning "Products service URL uses localhost in $ENVIRONMENT environment"
    fi
    
    if [[ "$ratings_url" == *"localhost"* ]] || [[ "$ratings_url" == *"127.0.0.1"* ]]; then
        log_warning "Ratings service URL uses localhost in $ENVIRONMENT environment"
    fi
}

validate_production_settings() {
    # Check for production-ready replication factors
    local replication_factor="${KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR:-1}"
    if [[ "$replication_factor" -lt 3 ]]; then
        log_error "Kafka replication factor must be 3+ for production (current: $replication_factor)"
    fi
    
    # Check for appropriate log levels
    local apollo_log="${APOLLO_ROUTER_LOG:-info}"
    local rust_log="${RUST_LOG:-info}"
    
    if [[ "$apollo_log" == "debug" ]] || [[ "$apollo_log" == "trace" ]]; then
        log_warning "Apollo Router log level is $apollo_log (consider 'warn' or 'error' for production)"
    fi
    
    if [[ "$rust_log" == "debug" ]] || [[ "$rust_log" == "trace" ]]; then
        log_warning "Rust log level is $rust_log (consider 'warn' or 'error' for production)"
    fi
}

check_docker_compose() {
    log_info "Checking Docker Compose configuration..."
    
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        log_error "Docker or Docker Compose not found. Please install Docker."
        return 1
    fi
    
    if [[ -f "$PROJECT_ROOT/docker-compose.yml" ]]; then
        log_success "docker-compose.yml found"
        
        # Validate Docker Compose file syntax
        if command -v docker-compose &> /dev/null; then
            if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" config &> /dev/null; then
                log_success "docker-compose.yml syntax is valid"
            else
                log_error "docker-compose.yml has syntax errors"
            fi
        elif command -v docker &> /dev/null; then
            if docker compose -f "$PROJECT_ROOT/docker-compose.yml" config &> /dev/null; then
                log_success "docker-compose.yml syntax is valid"
            else
                log_error "docker-compose.yml has syntax errors"
            fi
        fi
    else
        log_error "docker-compose.yml not found at $PROJECT_ROOT"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "============================================================================="
    echo "Platform Infrastructure Configuration Validation"
    echo "============================================================================="
    echo "Environment: $ENVIRONMENT"
    echo "Project Root: $PROJECT_ROOT"
    echo ""
    
    # Run all validations
    check_env_file || exit 1
    load_env_file
    validate_required_vars
    validate_port_numbers
    validate_service_urls
    validate_database_config
    validate_kafka_config
    validate_logging_config
    validate_environment_specific
    check_docker_compose
    
    echo ""
    echo "============================================================================="
    echo "Validation Summary"
    echo "============================================================================="
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "All validations passed! ✅"
        if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
            log_warning "$VALIDATION_WARNINGS warning(s) found - review recommendations above"
        fi
        echo ""
        log_info "You can now start the infrastructure with:"
        log_info "  ./scripts/start-infrastructure.sh"
        exit 0
    else
        log_error "$VALIDATION_ERRORS error(s) found - fix issues before proceeding"
        if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
            log_warning "$VALIDATION_WARNINGS warning(s) found - review recommendations above"
        fi
        echo ""
        log_info "Fix the errors above and run validation again:"
        log_info "  ./scripts/validate-config.sh $ENVIRONMENT"
        exit 1
    fi
}

# Run main function
main "$@"