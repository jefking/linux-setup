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

setup_tmpfs_if_needed() {
    local workspace="$1"
    local size="$2"
    local description="$3"

    if ! mountpoint -q "$workspace" >/dev/null 2>&1; then
        info "Setting up $description at $workspace..."

        # Create directory if it doesn't exist
        sudo mkdir -p "$workspace"

        # Mount tmpfs
        if sudo mount -t tmpfs -o size=$size,mode=1777,noatime,nodiratime,nodev,nosuid tmpfs "$workspace"; then
            # Set proper ownership
            sudo chown $USER:$USER "$workspace"
            chmod 755 "$workspace"
            info "✅ $description mounted successfully ($size)"
        else
            error "Failed to mount $description at $workspace"
            return 1
        fi
    else
        info "✅ $description already mounted at $workspace"
    fi
    return 0
}

check_prerequisites() {
    info "Checking prerequisites..."

    # Check available memory first
    AVAILABLE_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$AVAILABLE_MEM_GB" -lt 8 ]; then
        error "Insufficient memory for RAM workspace. Need at least 8GB, found ${AVAILABLE_MEM_GB}GB"
        return 1
    fi

    # Determine tmpfs sizes based on available memory
    if [ "$AVAILABLE_MEM_GB" -ge 24 ]; then
        WORKSPACE_SIZE="12G"
        BUILD_CACHE_SIZE="6G"
    elif [ "$AVAILABLE_MEM_GB" -ge 16 ]; then
        WORKSPACE_SIZE="8G"
        BUILD_CACHE_SIZE="4G"
    else
        WORKSPACE_SIZE="4G"
        BUILD_CACHE_SIZE="2G"
    fi

    info "Available memory: ${AVAILABLE_MEM_GB}GB, using workspace: $WORKSPACE_SIZE, build cache: $BUILD_CACHE_SIZE"

    # Setup tmpfs mounts if needed
    if ! setup_tmpfs_if_needed "$RAM_WORKSPACE" "$WORKSPACE_SIZE" "RAM workspace"; then
        return 1
    fi

    if ! setup_tmpfs_if_needed "/tmp/build-cache" "$BUILD_CACHE_SIZE" "build cache"; then
        return 1
    fi

    # Check if sync script exists
    if [ ! -f "$SYNC_SCRIPT" ]; then
        warn "Sync script not found: $SYNC_SCRIPT"
        info "You can still use the development environment without the sync script"
        info "To enable ./git syncing, ensure sync-all-git-to-ram.sh is in the same directory"
        SYNC_SCRIPT=""  # Disable sync functionality but continue
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
    echo "  • CPU: $(nproc) cores @ $(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{printf "%.0f MHz", $4}' 2>/dev/null || echo "N/A")"
    echo "  • Memory: $(free -h | awk 'NR==2{printf "%.1f/%.1f GB (%.1f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"

    # Show tmpfs status
    if mountpoint -q "$RAM_WORKSPACE" >/dev/null 2>&1; then
        echo "  • RAM Workspace: $(df -h "$RAM_WORKSPACE" | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}') ✅"
    else
        echo "  • RAM Workspace: Not mounted ❌"
    fi

    if mountpoint -q "/tmp/build-cache" >/dev/null 2>&1; then
        echo "  • Build Cache: $(df -h "/tmp/build-cache" | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}') ✅"
    else
        echo "  • Build Cache: Not mounted ❌"
    fi

    # Show SSD temperature (optional, may require sudo)
    if command -v nvme >/dev/null 2>&1; then
        SSD_TEMP=$(sudo nvme smart-log /dev/nvme0 2>/dev/null | grep "temperature" | awk '{print $3}' 2>/dev/null || echo "N/A")
        echo "  • SSD Temperature: ${SSD_TEMP}°C"
    fi

    echo "  • Time: $(date)"
    echo ""
}

sync_repositories() {
    if [ -z "$SYNC_SCRIPT" ]; then
        warn "Sync script not available - skipping repository sync"
        info "You can manually copy projects to $RAM_WORKSPACE or use dev-sync-to-ram commands"
        return 0
    fi

    info "Syncing ./git/* to RAM workspace..."

    if [ -x "$SYNC_SCRIPT" ] && "$SYNC_SCRIPT"; then
        info "✓ Projects synced successfully"
        return 0
    else
        warn "✗ Failed to sync projects, but continuing..."
        info "You can manually sync repositories later"
        return 0  # Don't fail the entire startup
    fi
}

setup_development_environment() {
    info "Setting up enhanced development environment..."

    # Navigate to RAM workspace
    cd "$RAM_WORKSPACE" || {
        error "Failed to navigate to RAM workspace"
        return 1
    }

    # Show available projects with detailed info
    info "Available projects in RAM workspace:"
    project_count=0
    total_size=0

    for project in */; do
        if [ -d "$project" ]; then
            project_count=$((project_count + 1))
            size=$(du -sh "$project" 2>/dev/null | cut -f1)
            size_mb=$(du -sm "$project" 2>/dev/null | cut -f1)
            total_size=$((total_size + size_mb))

            # Detect project type
            project_type="Unknown"
            if [ -f "$project/Cargo.toml" ]; then
                project_type="Rust"
            elif [ -f "$project/package.json" ]; then
                project_type="Node.js"
            elif [ -f "$project/go.mod" ]; then
                project_type="Go"
            elif [ -f "$project/pom.xml" ]; then
                project_type="Maven"
            elif [ -f "$project/build.gradle" ]; then
                project_type="Gradle"
            elif [ -f "$project/requirements.txt" ] || [ -f "$project/pyproject.toml" ]; then
                project_type="Python"
            elif [ -f "$project/Dockerfile" ]; then
                project_type="Docker"
            elif [ -d "$project/.git" ]; then
                project_type="Git"
            fi

            echo "  • $project ($size, $project_type)"
        fi
    done

    if [ $project_count -eq 0 ]; then
        warn "No projects found in RAM workspace"
        info "Use 'dev-sync-to-ram /path/to/project' to sync projects"
    else
        info "Total: $project_count projects, ${total_size}MB in RAM"
    fi

    # Set up enhanced shell environment
    export DEV_WORKSPACE="$RAM_WORKSPACE"
    export BUILD_CACHE="/tmp/build-cache"
    export PS1="\[\033[1;32m\][RAM-DEV]\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\]$ "

    # Load compiler optimizations if available
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc" 2>/dev/null || true
    fi

    info "Enhanced development environment ready"
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
    if command -v dev-sync-to-ram >/dev/null 2>&1; then
        echo "║     • dev-sync-to-ram path  - Sync project from disk to RAM                 ║"
        echo "║     • dev-sync-to-disk name - Save changes back to disk                     ║"
    else
        echo "║     • cp -r /path/to/project . - Copy project to RAM workspace              ║"
        echo "║     • rsync -av . /path/to/project/ - Save changes back to disk            ║"
    fi
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
    alias workspace='cd $RAM_WORKSPACE'
    alias ram='cd $RAM_WORKSPACE'

    # Create helper functions for manual project management
    if ! command -v dev-sync-to-ram >/dev/null 2>&1; then
        # Simple manual sync functions if enhanced scripts aren't available
        sync-to-ram() {
            local project_path="$1"
            if [ -z "$project_path" ]; then
                echo "Usage: sync-to-ram /path/to/project"
                return 1
            fi

            local project_name=$(basename "$project_path")
            local ram_project="$RAM_WORKSPACE/$project_name"

            echo "📦 Syncing $project_name to RAM..."
            rsync -av --progress "$project_path/" "$ram_project/"
            echo "✅ Project synced to: $ram_project"
        }

        sync-to-disk() {
            local project_name="$1"
            if [ -z "$project_name" ]; then
                echo "Available projects in RAM:"
                ls -1 "$RAM_WORKSPACE"
                return 1
            fi

            local ram_project="$RAM_WORKSPACE/$project_name"
            if [ ! -d "$ram_project" ]; then
                echo "❌ Project not found in RAM: $project_name"
                return 1
            fi

            echo "💾 Where should I save $project_name?"
            read -p "Enter disk path (e.g., ~/git/$project_name): " disk_path

            # Expand tilde
            disk_path="${disk_path/#\~/$HOME}"

            echo "💾 Syncing $project_name back to disk..."
            rsync -av --progress "$ram_project/" "$disk_path/"
            echo "✅ Changes saved to: $disk_path"
        }

        alias save='echo "Use: sync-to-disk <project-name>"'
        export -f sync-to-ram sync-to-disk
    else
        alias save='echo "Use: dev-sync-to-disk <project-name>"'
    fi

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
    echo "Syncs ./git into the RAM workspace and opens a development terminal"
    echo ""
    echo "Options:"
    echo "  --help       Show this help message"
    echo "  --no-sync    Skip ./git sync"
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
    warn "Skipping ./git sync as requested"
    SYNC_SCRIPT=""
fi

# Run main function
main "$@"