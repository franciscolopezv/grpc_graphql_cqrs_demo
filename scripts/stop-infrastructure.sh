#!/bin/bash

# =============================================================================
# Platform Infrastructure Shutdown Script
# =============================================================================
# This script gracefully stops the platform infrastructure services and
# optionally cleans up resources.
#
# Usage:
#   ./scripts/stop-infrastructure.sh [options]
#
# Options:
#   --remove-volumes    Remove persistent volumes (WARNING: deletes all data)
#   --remove-images     Remove custom built images
#   --remove-networks   Remove custom networks
#   --force            Force stop containers (kill instead of graceful stop)
#   --timeout SECONDS  Timeout for graceful shutdown (default: 30)
#   --help             Show this help message
#
# Exit codes:
#   0: Success
#   1: Docker Compose failed
#   2: Cleanup failed
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
REMOVE_VOLUMES=false
REMOVE_IMAGES=false
REMOVE_NETWORKS=false
FORCE_STOP=false
STOP_TIMEOUT=30

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
Platform Infrastructure Shutdown Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --remove-volumes    Remove persistent volumes (WARNING: deletes all data)
    --remove-images     Remove custom built images
    --remove-networks   Remove custom networks
    --force            Force stop containers (kill instead of graceful stop)
    --timeout SECONDS  Timeout for graceful shutdown (default: 30)
    --help             Show this help message

EXAMPLES:
    # Graceful shutdown (default)
    $0

    # Force stop all containers
    $0 --force

    # Stop and remove all data (DESTRUCTIVE)
    $0 --remove-volumes

    # Complete cleanup (DESTRUCTIVE)
    $0 --remove-volumes --remove-images --remove-networks

SERVICES AFFECTED:
    - GraphQL Gateway
    - Kafka
    - Zookeeper
    - PostgreSQL

WARNING:
    Using --remove-volumes will permanently delete all database data,
    Kafka messages, and other persistent data. This action cannot be undone.

EOF
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

check_services_running() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    if $compose_cmd -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -q .; then
        return 0  # Services are running
    else
        return 1  # No services running
    fi
}

stop_services() {
    log_step "Stopping platform infrastructure services..."
    
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    if ! check_services_running; then
        log_info "No services are currently running"
        return 0
    fi
    
    local stop_args=()
    stop_args+=("-f" "$COMPOSE_FILE")
    
    if [[ "$FORCE_STOP" == true ]]; then
        stop_args+=("kill")
        log_warning "Force stopping containers (may cause data loss)"
    else
        stop_args+=("stop")
        stop_args+=("--timeout" "$STOP_TIMEOUT")
        log_info "Gracefully stopping containers (timeout: ${STOP_TIMEOUT}s)"
    fi
    
    if $compose_cmd "${stop_args[@]}"; then
        log_success "Services stopped successfully"
    else
        log_error "Failed to stop some services"
        return 1
    fi
}

remove_containers() {
    log_step "Removing stopped containers..."
    
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    if $compose_cmd -f "$COMPOSE_FILE" rm -f; then
        log_success "Containers removed successfully"
    else
        log_warning "Failed to remove some containers"
    fi
}

# =============================================================================
# Cleanup Functions
# =============================================================================

remove_volumes() {
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        log_step "Removing persistent volumes..."
        log_warning "This will permanently delete all data!"
        
        # Give user a chance to cancel
        echo -n "Are you sure you want to delete all data? Type 'yes' to confirm: "
        read -r confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Volume removal cancelled"
            return 0
        fi
        
        local compose_cmd
        compose_cmd=$(get_compose_command)
        
        # Remove volumes defined in docker-compose.yml
        if $compose_cmd -f "$COMPOSE_FILE" down --volumes; then
            log_success "Volumes removed successfully"
        else
            log_error "Failed to remove volumes"
            return 2
        fi
        
        # Also remove any orphaned volumes
        local volume_names=(
            "platform-infrastructure_postgres-data"
            "platform-infrastructure_kafka-data"
            "platform-infrastructure_zookeeper-data"
            "platform-infrastructure_zookeeper-logs"
        )
        
        for volume in "${volume_names[@]}"; do
            if docker volume ls -q | grep -q "^${volume}$"; then
                if docker volume rm "$volume" 2>/dev/null; then
                    log_success "Removed volume: $volume"
                else
                    log_warning "Failed to remove volume: $volume (may not exist)"
                fi
            fi
        done
    fi
}

remove_images() {
    if [[ "$REMOVE_IMAGES" == true ]]; then
        log_step "Removing custom built images..."
        
        # Remove images built by docker-compose
        local compose_cmd
        compose_cmd=$(get_compose_command)
        
        if $compose_cmd -f "$COMPOSE_FILE" down --rmi local; then
            log_success "Custom images removed successfully"
        else
            log_warning "Failed to remove some custom images"
        fi
        
        # Remove specific images if they exist
        local image_names=(
            "grpc_graphql_cqrs_demo-graphql-gateway"
            "grpc_graphql_cqrs_demo_graphql-gateway"
        )
        
        for image in "${image_names[@]}"; do
            if docker images -q "$image" | grep -q .; then
                if docker rmi "$image" 2>/dev/null; then
                    log_success "Removed image: $image"
                else
                    log_warning "Failed to remove image: $image"
                fi
            fi
        done
    fi
}

remove_networks() {
    if [[ "$REMOVE_NETWORKS" == true ]]; then
        log_step "Removing custom networks..."
        
        local network_names=(
            "platform-infrastructure"
            "grpc_graphql_cqrs_demo_default"
        )
        
        for network in "${network_names[@]}"; do
            if docker network ls -q --filter name="^${network}$" | grep -q .; then
                if docker network rm "$network" 2>/dev/null; then
                    log_success "Removed network: $network"
                else
                    log_warning "Failed to remove network: $network (may be in use)"
                fi
            fi
        done
    fi
}

# =============================================================================
# Status and Information Functions
# =============================================================================

show_cleanup_summary() {
    log_step "Cleanup summary:"
    
    echo ""
    echo "✅ Services stopped and containers removed"
    
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        echo "🗑️  Persistent volumes removed (data deleted)"
    else
        echo "💾 Persistent volumes preserved (data retained)"
    fi
    
    if [[ "$REMOVE_IMAGES" == true ]]; then
        echo "🖼️  Custom images removed"
    else
        echo "🖼️  Custom images preserved"
    fi
    
    if [[ "$REMOVE_NETWORKS" == true ]]; then
        echo "🌐 Custom networks removed"
    else
        echo "🌐 Custom networks preserved"
    fi
    
    echo ""
}

show_restart_info() {
    echo "🔄 To restart the infrastructure:"
    echo "   $SCRIPT_DIR/start-infrastructure.sh"
    echo ""
    
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        echo "⚠️  Note: All data was deleted. Services will start with fresh databases."
    else
        echo "💡 Note: Data is preserved. Services will restart with existing data."
    fi
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove-volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            --remove-images)
                REMOVE_IMAGES=true
                shift
                ;;
            --remove-networks)
                REMOVE_NETWORKS=true
                shift
                ;;
            --force)
                FORCE_STOP=true
                shift
                ;;
            --timeout)
                STOP_TIMEOUT="$2"
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

validate_prerequisites() {
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker Compose
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
}

main() {
    echo "============================================================================="
    echo "🛑 Platform Infrastructure Shutdown"
    echo "============================================================================="
    echo "Project Root: $PROJECT_ROOT"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    
    # Show warning for destructive operations
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        echo "⚠️  WARNING: This will permanently delete all data!"
        echo ""
    fi
    
    # Stop services
    stop_services
    
    # Remove containers
    remove_containers
    
    # Cleanup resources if requested
    remove_volumes
    remove_images
    remove_networks
    
    echo ""
    echo "============================================================================="
    echo "✅ Platform Infrastructure Shutdown Complete"
    echo "============================================================================="
    
    show_cleanup_summary
    show_restart_info
    
    log_success "Infrastructure shutdown completed successfully"
}

# Parse command line arguments and run main function
parse_arguments "$@"
main