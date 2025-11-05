#!/bin/bash

# =============================================================================
# Platform Infrastructure Startup Script
# =============================================================================
# This script starts the complete platform infrastructure including:
# - PostgreSQL database with multiple databases
# - Apache Kafka with Zookeeper
# - GraphQL Gateway (Apollo Router)
#
# Usage:
#   ./scripts/start-infrastructure.sh [options]
#
# Options:
#   --validate-only    Only validate configuration, don't start services
#   --no-validation    Skip configuration validation
#   --detach          Run services in detached mode (default)
#   --foreground      Run services in foreground mode
#   --build           Force rebuild of custom images
#   --pull            Pull latest images before starting
#   --environment ENV Set environment type (development, staging, production)
#   --help            Show this help message
#
# Exit codes:
#   0: Success
#   1: Configuration validation failed
#   2: Docker Compose failed
#   3: Service health check failed
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

# Default options
VALIDATE_CONFIG=true
RUN_DETACHED=true
FORCE_BUILD=false
PULL_IMAGES=false
ENVIRONMENT="development"
VALIDATE_ONLY=false

# Service health check configuration
HEALTH_CHECK_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_INTERVAL=5   # 5 seconds

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

show_help() {
    cat << EOF
Platform Infrastructure Startup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --validate-only     Only validate configuration, don't start services
    --no-validation     Skip configuration validation
    --detach           Run services in detached mode (default)
    --foreground       Run services in foreground mode
    --build            Force rebuild of custom images
    --pull             Pull latest images before starting
    --environment ENV  Set environment type (development, staging, production)
    --help             Show this help message

EXAMPLES:
    # Start infrastructure with validation (default)
    $0

    # Start in foreground mode for debugging
    $0 --foreground

    # Force rebuild and start
    $0 --build

    # Validate configuration only
    $0 --validate-only

    # Start for production environment
    $0 --environment production

SERVICES:
    - PostgreSQL (port 5432)
    - Zookeeper (port 2181)
    - Kafka (port 9092)
    - GraphQL Gateway (port 4000)

EOF
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker Compose (either standalone or plugin)
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

validate_configuration() {
    log_step "Validating configuration..."
    
    if [[ -x "$SCRIPT_DIR/validate-config.sh" ]]; then
        if "$SCRIPT_DIR/validate-config.sh" "$ENVIRONMENT"; then
            log_success "Configuration validation passed"
        else
            log_error "Configuration validation failed"
            exit 1
        fi
    else
        log_warning "Configuration validation script not found or not executable"
        log_warning "Skipping configuration validation"
    fi
}

# =============================================================================
# Docker Compose Functions
# =============================================================================

get_compose_command() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

pull_images() {
    if [[ "$PULL_IMAGES" == true ]]; then
        log_step "Pulling latest images..."
        local compose_cmd
        compose_cmd=$(get_compose_command)
        
        if $compose_cmd -f "$COMPOSE_FILE" pull; then
            log_success "Images pulled successfully"
        else
            log_warning "Failed to pull some images, continuing with existing images"
        fi
    fi
}

build_images() {
    if [[ "$FORCE_BUILD" == true ]]; then
        log_step "Building custom images..."
        local compose_cmd
        compose_cmd=$(get_compose_command)
        
        if $compose_cmd -f "$COMPOSE_FILE" build; then
            log_success "Images built successfully"
        else
            log_error "Failed to build images"
            exit 2
        fi
    fi
}

start_services() {
    log_step "Starting platform infrastructure services..."
    
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    local compose_args=()
    compose_args+=("-f" "$COMPOSE_FILE")
    
    if [[ "$RUN_DETACHED" == true ]]; then
        compose_args+=("up" "-d")
    else
        compose_args+=("up")
    fi
    
    if [[ "$FORCE_BUILD" == true ]]; then
        compose_args+=("--build")
    fi
    
    log_info "Running: $compose_cmd ${compose_args[*]}"
    
    if $compose_cmd "${compose_args[@]}"; then
        log_success "Services started successfully"
    else
        log_error "Failed to start services"
        exit 2
    fi
}

# =============================================================================
# Health Check Functions
# =============================================================================

wait_for_service() {
    local service_name="$1"
    local health_check_cmd="$2"
    local timeout="$3"
    
    log_info "Waiting for $service_name to be healthy..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$health_check_cmd" &> /dev/null; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log_info "Still waiting for $service_name... (${elapsed}s elapsed)"
        fi
    done
    
    log_error "$service_name failed to become healthy within ${timeout}s"
    return 1
}

check_service_health() {
    if [[ "$RUN_DETACHED" == true ]]; then
        log_step "Checking service health..."
        
        local compose_cmd
        compose_cmd=$(get_compose_command)
        
        # Wait for PostgreSQL
        wait_for_service "PostgreSQL" \
            "$compose_cmd -f $COMPOSE_FILE exec -T postgres pg_isready -U \${POSTGRES_USER:-platform_user}" \
            60
        
        # Wait for Zookeeper
        wait_for_service "Zookeeper" \
            "$compose_cmd -f $COMPOSE_FILE exec -T zookeeper nc -z localhost 2181" \
            60
        
        # Wait for Kafka
        wait_for_service "Kafka" \
            "$compose_cmd -f $COMPOSE_FILE exec -T kafka kafka-broker-api-versions --bootstrap-server localhost:9092" \
            120
        
        # Wait for GraphQL Gateway
        wait_for_service "GraphQL Gateway" \
            "curl -f http://localhost:\${GRAPHQL_GATEWAY_PORT:-4000}/health" \
            120
        
        log_success "All services are healthy"
    fi
}

# =============================================================================
# Service Information Functions
# =============================================================================

show_service_status() {
    log_step "Service status:"
    
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    $compose_cmd -f "$COMPOSE_FILE" ps
}

show_service_urls() {
    log_step "Service endpoints:"
    
    # Load environment variables to get ports
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
    fi
    
    echo ""
    echo "🗄️  PostgreSQL Database:"
    echo "   Host: localhost"
    echo "   Port: ${POSTGRES_PORT:-5432}"
    echo "   User: ${POSTGRES_USER:-platform_user}"
    echo "   Databases: ${POSTGRES_MULTIPLE_DATABASES:-products_db,ratings_db,platform_db}"
    echo ""
    echo "📨 Kafka Message Bus:"
    echo "   Bootstrap Servers: localhost:9092"
    echo "   Zookeeper: localhost:2181"
    echo "   Topics: products_events, ratings_events"
    echo ""
    echo "🚀 GraphQL Gateway:"
    echo "   Endpoint: http://localhost:${GRAPHQL_GATEWAY_PORT:-4000}"
    echo "   Health Check: http://localhost:${GRAPHQL_GATEWAY_PORT:-4000}/health"
    echo "   GraphQL Playground: http://localhost:${GRAPHQL_GATEWAY_PORT:-4000}"
    echo ""
}

show_logs_info() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    echo "📋 View logs:"
    echo "   All services: $compose_cmd -f $COMPOSE_FILE logs -f"
    echo "   PostgreSQL:   $compose_cmd -f $COMPOSE_FILE logs -f postgres"
    echo "   Kafka:        $compose_cmd -f $COMPOSE_FILE logs -f kafka"
    echo "   Gateway:      $compose_cmd -f $COMPOSE_FILE logs -f graphql-gateway"
    echo ""
    echo "🛑 Stop services:"
    echo "   $SCRIPT_DIR/stop-infrastructure.sh"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --no-validation)
                VALIDATE_CONFIG=false
                shift
                ;;
            --detach)
                RUN_DETACHED=true
                shift
                ;;
            --foreground)
                RUN_DETACHED=false
                shift
                ;;
            --build)
                FORCE_BUILD=true
                shift
                ;;
            --pull)
                PULL_IMAGES=true
                shift
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    echo "============================================================================="
    echo "🚀 Platform Infrastructure Startup"
    echo "============================================================================="
    echo "Environment: $ENVIRONMENT"
    echo "Project Root: $PROJECT_ROOT"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    
    # Validate configuration if requested
    if [[ "$VALIDATE_CONFIG" == true ]]; then
        validate_configuration
    fi
    
    # Exit if only validation was requested
    if [[ "$VALIDATE_ONLY" == true ]]; then
        log_success "Configuration validation completed successfully"
        exit 0
    fi
    
    # Pull images if requested
    pull_images
    
    # Build images if requested
    build_images
    
    # Start services
    start_services
    
    # Check service health
    check_service_health
    
    # Show service information
    echo ""
    echo "============================================================================="
    echo "🎉 Platform Infrastructure Started Successfully"
    echo "============================================================================="
    
    show_service_status
    show_service_urls
    show_logs_info
    
    if [[ "$RUN_DETACHED" == false ]]; then
        log_info "Services are running in foreground mode. Press Ctrl+C to stop."
    else
        log_success "All services are running in the background"
    fi
}

# Parse command line arguments and run main function
parse_arguments "$@"
main