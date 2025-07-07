#!/bin/bash

# dev-startup.sh
# Startup script to sync all git repos to RAM and open development terminal

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-all-git-to-ram.sh"
RAM_WORKSPACE="/tmp/dev-workspace"
STARTUP_LOG="$HOME/dev-startup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$STARTUP_LOG"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$STARTUP_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$STARTUP_LOG"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$STARTUP_LOG"
}

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                          Development Environment Startup                    ║"
    echo "║                         Framework Laptop Performance Setup                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if tmpfs is mounted
    if ! mountpoint -q "$RAM_WORKSPACE" >/dev/null 2>&1; then
        error "RAM workspace not mounted at $RAM_WORKSPACE"
        info "Please ensure tmpfs is configured in /etc/fstab and mounted"
        return 1
    fi
    
    # Check if sync script exists
    if [ ! -f "$SYNC_SCRIPT" ]; then
        error "Sync script not found: $SYNC_SCRIPT"
        return 1
    fi
    
    # Check if sync script is executable
    if [ ! -x "$SYNC_SCRIPT" ]; then
        warn "Making sync script executable..."
        chmod +x "$SYNC_SCRIPT"
    fi
    
    info "Prerequisites check passed"
    return 0
}

show_system_info() {
    info "System Information:"
    echo "  • CPU: $(nproc) cores"
    echo "  • Memory: $(free -h | awk 'NR==2{printf "%.1f/%.1f GB (%.1f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
    echo "  • RAM Workspace: $(df -h "$RAM_WORKSPACE" | awk 'NR==2{printf "%s available", $4}')"
    echo "  • Time: $(date)"
    echo ""
}

sync_repositories() {
    info "Syncing git repositories to RAM workspace..."
    
    if "$SYNC_SCRIPT"; then
        info "✓ Git repositories synced successfully"
        return 0
    else
        error "✗ Failed to sync git repositories"
        return 1
    fi
}

setup_development_environment() {
    info "Setting up development environment..."
    
    # Navigate to RAM workspace
    cd "$RAM_WORKSPACE" || {
        error "Failed to navigate to RAM workspace"
        return 1
    }
    
    # Show available projects
    info "Available projects in RAM workspace:"
    for project in */; do
        if [ -d "$project" ]; then
            echo "  • $project"
        fi
    done
    
    # Set up shell environment
    export DEV_WORKSPACE="$RAM_WORKSPACE"
    export PS1="\[\033[1;32m\][RAM-DEV]\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\]$ "
    
    info "Development environment ready"
    return 0
}

show_welcome_message() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        🚀 Development Environment Ready!                    ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                              ║"
    echo "║  You are now in the RAM workspace for blazing-fast development:             ║"
    echo "║  📁 Location: $RAM_WORKSPACE"
    echo "║                                                                              ║"
    echo "║  🔧 Available Commands:                                                      ║"
    echo "║     • ls                    - List your projects                             ║"
    echo "║     • cd project-name       - Enter a project directory                     ║"
    echo "║     • dev-sync-to-disk name - Save changes back to disk                     ║"
    echo "║     • dev-ram               - Return to RAM workspace                       ║"
    echo "║                                                                              ║"
    echo "║  ⚠️  Important Reminders:                                                   ║"
    echo "║     • RAM data is lost on reboot - sync changes frequently!                 ║"
    echo "║     • Use git commits often when working in RAM                             ║"
    echo "║     • Run dev-sync-to-disk before shutting down                             ║"
    echo "║                                                                              ║"
    echo "║  📊 Performance Benefits:                                                    ║"
    echo "║     • Git operations: 10x faster                                            ║"
    echo "║     • Builds: 2-3x faster                                                   ║"
    echo "║     • File I/O: Near-instantaneous                                          ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

create_ram_aliases() {
    # Create temporary aliases for this session
    alias ll='ls -la'
    alias la='ls -la'
    alias projects='ls -la'
    alias save='echo "Use: dev-sync-to-disk <project-name>"'
    alias workspace='cd $RAM_WORKSPACE'
    alias ram='cd $RAM_WORKSPACE'
    
    # Add to current session
    export -f log warn error info
}

main() {
    # Clear screen and show banner
    clear
    banner
    
    log "Starting development environment setup..."
    
    # Check prerequisites
    if ! check_prerequisites; then
        error "Prerequisites check failed. Exiting."
        exit 1
    fi
    
    # Show system information
    show_system_info
    
    # Sync repositories
    if ! sync_repositories; then
        error "Repository sync failed. Continuing anyway..."
    fi
    
    # Setup development environment
    if ! setup_development_environment; then
        error "Development environment setup failed. Exiting."
        exit 1
    fi
    
    # Create helpful aliases
    create_ram_aliases
    
    # Show welcome message
    show_welcome_message
    
    log "Development environment startup completed successfully"
    
    # Start interactive bash session in RAM workspace
    info "Starting interactive development session..."
    echo ""
    
    # Launch bash with custom environment
    exec bash --rcfile <(cat ~/.bashrc; echo "cd '$RAM_WORKSPACE'"; echo "export PS1='\[\033[1;32m\][RAM-DEV]\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\]$ '")
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}Startup interrupted by user${NC}"; exit 1' INT TERM

# Show usage if help requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Development environment startup script"
    echo "Syncs all git repositories to RAM workspace and opens development terminal"
    echo ""
    echo "Options:"
    echo "  --help       Show this help message"
    echo "  --no-sync    Skip git repository sync"
    echo "  --info       Show system info only"
    echo ""
    echo "Log file: $STARTUP_LOG"
    exit 0
fi

# Handle special options
if [ "$1" = "--info" ]; then
    show_system_info
    exit 0
fi

if [ "$1" = "--no-sync" ]; then
    warn "Skipping git repository sync as requested"
    SYNC_SCRIPT=""
fi

# Run main function
main "$@"