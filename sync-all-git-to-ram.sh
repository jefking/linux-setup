#!/bin/bash

# sync-all-git-to-ram.sh
# Syncs all git repositories from ~/git to tmpfs for faster development

set -e

GIT_DIR="$HOME/git"
RAM_WORKSPACE="/tmp/dev-workspace"
SYNC_LOG="$HOME/git-sync.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$SYNC_LOG"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$SYNC_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$SYNC_LOG"
}

check_tmpfs_space() {
    local available=$(df -BG "$RAM_WORKSPACE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    local total_size=0
    
    for dir in "$GIT_DIR"/*; do
        if [ -d "$dir" ]; then
            local size=$(du -sm "$dir" 2>/dev/null | cut -f1)
            total_size=$((total_size + size))
        fi
    done
    
    local total_gb=$((total_size / 1024 + 1))
    
    if [ "$total_gb" -gt "$available" ]; then
        error "Not enough space in tmpfs. Need ${total_gb}GB, have ${available}GB available"
        return 1
    fi
    
    log "Space check passed: ${total_gb}GB needed, ${available}GB available"
    return 0
}

sync_repo() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")
    local dest_path="$RAM_WORKSPACE/$repo_name"
    
    if [ ! -d "$repo_path/.git" ]; then
        warn "Skipping $repo_name - not a git repository"
        return 0
    fi
    
    log "Syncing $repo_name to RAM..."
    
    # Remove existing if present
    if [ -d "$dest_path" ]; then
        rm -rf "$dest_path"
    fi
    
    # Copy to RAM
    cp -r "$repo_path" "$dest_path"
    
    # Check if sync was successful
    if [ -d "$dest_path/.git" ]; then
        log "✓ $repo_name synced successfully"
        return 0
    else
        error "✗ Failed to sync $repo_name"
        return 1
    fi
}

main() {
    log "Starting git repositories sync to RAM workspace"
    
    # Check if tmpfs is mounted
    if ! mountpoint -q "$RAM_WORKSPACE"; then
        error "RAM workspace not mounted at $RAM_WORKSPACE"
        exit 1
    fi
    
    # Check if git directory exists
    if [ ! -d "$GIT_DIR" ]; then
        error "Git directory not found: $GIT_DIR"
        exit 1
    fi
    
    # Check available space
    if ! check_tmpfs_space; then
        exit 1
    fi
    
    local success_count=0
    local total_count=0
    
    # Sync all directories in git folder
    for repo_path in "$GIT_DIR"/*; do
        if [ -d "$repo_path" ]; then
            total_count=$((total_count + 1))
            if sync_repo "$repo_path"; then
                success_count=$((success_count + 1))
            fi
        fi
    done
    
    log "Sync completed: $success_count/$total_count repositories synced"
    
    if [ "$success_count" -gt 0 ]; then
        log "RAM workspace ready at: $RAM_WORKSPACE"
        log "Navigate with: cd $RAM_WORKSPACE"
        log "Remember to sync changes back to disk before reboot!"
    fi
}

# Show usage if help requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--dry-run]"
    echo ""
    echo "Syncs all git repositories from ~/git to tmpfs RAM workspace"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be synced without actually doing it"
    echo "  --help       Show this help message"
    echo ""
    echo "Log file: $SYNC_LOG"
    exit 0
fi

# Dry run mode
if [ "$1" = "--dry-run" ]; then
    log "DRY RUN - showing what would be synced:"
    for repo_path in "$GIT_DIR"/*; do
        if [ -d "$repo_path" ]; then
            repo_name=$(basename "$repo_path")
            if [ -d "$repo_path/.git" ]; then
                echo "  ✓ $repo_name ($(du -sh "$repo_path" | cut -f1))"
            else
                echo "  ✗ $repo_name (not a git repo)"
            fi
        fi
    done
    exit 0
fi

main "$@"