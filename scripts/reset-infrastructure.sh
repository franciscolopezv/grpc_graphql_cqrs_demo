#!/bin/bash

# =============================================================================
# Platform Infrastructure Reset and Cleanup Script
# =============================================================================
# This script performs a complete reset of the platform infrastructure by:
# - Stopping all services
# - Removing all containers, volumes, images, and networks
# - Optionally rebuilding and restarting the infrastructure
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

# Default options
RESTART_AFTER_RESET=false
KEEP_IMAGES=false
FORCE_RESET=false

show_help() {
    cat << 'HELP_EOF'
Platform Infrastructure Reset and Cleanup Script

USAGE:
    ./scripts/reset-infrastructure.sh [OPTIONS]

OPTIONS:
    --restart          Restart infrastructure after reset
    --keep-images      Don't remove Docker images (faster restart)
    --force           Skip confirmation prompts
    --help            Show this help message

EXAMPLES:
    # Complete reset with confirmation
    ./scripts/reset-infrastructure.sh

    # Reset and restart automatically
    ./scripts/reset-infrastructure.sh --restart

    # Force reset without prompts
    ./scripts/reset-infrastructure.sh --force

WHAT GETS RESET:
    ✅ All running containers (stopped and removed)
    ✅ All persistent volumes (PostgreSQL, Kafka, Zookeeper data)
    ✅ All custom Docker images (unless --keep-images)
    ✅ All custom Docker networks

WARNING:
    This operation is DESTRUCTIVE and will permanently delete:
    - All database data (PostgreSQL)
    - All message history (Kafka)
    - All configuration state (Zookeeper)
    
    This action cannot be undone!

HELP_EOF
}

get_compose_command() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

reset_infrastructure() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    echo "🛑 Stopping all services..."
    $compose_cmd -f "$COMPOSE_FILE" kill 2>/dev/null || true
    
    echo "📦 Removing containers and volumes..."
    $compose_cmd -f "$COMPOSE_FILE" down --volumes 2>/dev/null || true
    
    if [[ "$KEEP_IMAGES" == false ]]; then
        echo "🖼️  Removing custom images..."
        $compose_cmd -f "$COMPOSE_FILE" down --rmi local 2>/dev/null || true
    fi
    
    # Remove custom networks
    echo "🌐 Removing custom networks..."
    docker network rm platform-infrastructure 2>/dev/null || true
    
    echo "✅ Infrastructure reset completed successfully"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --restart)
            RESTART_AFTER_RESET=true
            shift
            ;;
        --keep-images)
            KEEP_IMAGES=true
            shift
            ;;
        --force)
            FORCE_RESET=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
echo "============================================================================="
echo "🔄 Platform Infrastructure Reset and Cleanup"
echo "============================================================================="
echo "Project Root: $PROJECT_ROOT"

if [[ "$FORCE_RESET" == false ]]; then
    echo ""
    echo "⚠️ ⚠️ ⚠️  DESTRUCTIVE OPERATION WARNING  ⚠️ ⚠️ ⚠️"
    echo ""
    echo "This will permanently delete ALL platform infrastructure data:"
    echo ""
    echo "🗄️  PostgreSQL databases (products_db, ratings_db, platform_db)"
    echo "📨 Kafka message bus (all messages and consumer offsets)"
    echo "⚙️  Zookeeper coordination (all cluster metadata)"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    echo -n "Are you absolutely sure? Type 'RESET' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "RESET" ]]; then
        echo "🚫 Reset cancelled by user"
        exit 1
    fi
fi

echo ""
echo "🔄 Starting complete infrastructure reset..."
echo ""

reset_infrastructure

if [[ "$RESTART_AFTER_RESET" == true ]]; then
    echo ""
    echo "🚀 Restarting infrastructure..."
    if [[ -x "$SCRIPT_DIR/start-infrastructure.sh" ]]; then
        "$SCRIPT_DIR/start-infrastructure.sh" --build
    else
        echo "❌ Start script not found or not executable: $SCRIPT_DIR/start-infrastructure.sh"
        exit 1
    fi
fi

echo ""
echo "============================================================================="
echo "✅ Platform Infrastructure Reset Complete"
echo "============================================================================="
echo ""
echo "🔄 To start the infrastructure:"
echo "   $SCRIPT_DIR/start-infrastructure.sh"
echo ""
EOFcat > scripts/reset-infrastructure.sh << 'EOF'
#!/bin/bash

# =============================================================================
# Platform Infrastructure Reset and Cleanup Script
# =============================================================================
# This script performs a complete reset of the platform infrastructure by:
# - Stopping all services
# - Removing all containers, volumes, images, and networks
# - Optionally rebuilding and restarting the infrastructure
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

# Default options
RESTART_AFTER_RESET=false
KEEP_IMAGES=false
FORCE_RESET=false

show_help() {
    cat << 'HELP_EOF'
Platform Infrastructure Reset and Cleanup Script

USAGE:
    ./scripts/reset-infrastructure.sh [OPTIONS]

OPTIONS:
    --restart          Restart infrastructure after reset
    --keep-images      Don't remove Docker images (faster restart)
    --force           Skip confirmation prompts
    --help            Show this help message

EXAMPLES:
    # Complete reset with confirmation
    ./scripts/reset-infrastructure.sh

    # Reset and restart automatically
    ./scripts/reset-infrastructure.sh --restart

    # Force reset without prompts
    ./scripts/reset-infrastructure.sh --force

WHAT GETS RESET:
    ✅ All running containers (stopped and removed)
    ✅ All persistent volumes (PostgreSQL, Kafka, Zookeeper data)
    ✅ All custom Docker images (unless --keep-images)
    ✅ All custom Docker networks

WARNING:
    This operation is DESTRUCTIVE and will permanently delete:
    - All database data (PostgreSQL)
    - All message history (Kafka)
    - All configuration state (Zookeeper)
    
    This action cannot be undone!

HELP_EOF
}

get_compose_command() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

reset_infrastructure() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    echo "🛑 Stopping all services..."
    $compose_cmd -f "$COMPOSE_FILE" kill 2>/dev/null || true
    
    echo "📦 Removing containers and volumes..."
    $compose_cmd -f "$COMPOSE_FILE" down --volumes 2>/dev/null || true
    
    if [[ "$KEEP_IMAGES" == false ]]; then
        echo "🖼️  Removing custom images..."
        $compose_cmd -f "$COMPOSE_FILE" down --rmi local 2>/dev/null || true
    fi
    
    # Remove custom networks
    echo "🌐 Removing custom networks..."
    docker network rm platform-infrastructure 2>/dev/null || true
    
    echo "✅ Infrastructure reset completed successfully"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --restart)
            RESTART_AFTER_RESET=true
            shift
            ;;
        --keep-images)
            KEEP_IMAGES=true
            shift
            ;;
        --force)
            FORCE_RESET=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
echo "============================================================================="
echo "🔄 Platform Infrastructure Reset and Cleanup"
echo "============================================================================="
echo "Project Root: $PROJECT_ROOT"

if [[ "$FORCE_RESET" == false ]]; then
    echo ""
    echo "⚠️ ⚠️ ⚠️  DESTRUCTIVE OPERATION WARNING  ⚠️ ⚠️ ⚠️"
    echo ""
    echo "This will permanently delete ALL platform infrastructure data:"
    echo ""
    echo "🗄️  PostgreSQL databases (products_db, ratings_db, platform_db)"
    echo "📨 Kafka message bus (all messages and consumer offsets)"
    echo "⚙️  Zookeeper coordination (all cluster metadata)"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    echo -n "Are you absolutely sure? Type 'RESET' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "RESET" ]]; then
        echo "🚫 Reset cancelled by user"
        exit 1
    fi
fi

echo ""
echo "🔄 Starting complete infrastructure reset..."
echo ""

reset_infrastructure

if [[ "$RESTART_AFTER_RESET" == true ]]; then
    echo ""
    echo "🚀 Restarting infrastructure..."
    if [[ -x "$SCRIPT_DIR/start-infrastructure.sh" ]]; then
        "$SCRIPT_DIR/start-infrastructure.sh" --build
    else
        echo "❌ Start script not found or not executable: $SCRIPT_DIR/start-infrastructure.sh"
        exit 1
    fi
fi

echo ""
echo "============================================================================="
echo "✅ Platform Infrastructure Reset Complete"
echo "============================================================================="
echo ""
echo "🔄 To start the infrastructure:"
echo "   $SCRIPT_DIR/start-infrastructure.sh"
echo ""
