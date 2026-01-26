#!/bin/bash

# sync-all-git-to-ram.sh
# Syncs everything under ~/git (top-level entries) to tmpfs for faster development

set -e

GIT_DIR="${GIT_DIR:-$HOME/git}"
RAM_WORKSPACE="${RAM_WORKSPACE:-/tmp/dev-workspace}"
SYNC_LOG="${SYNC_LOG:-$HOME/git-sync.log}"

# Optional extra directory to sync (requested: ../peons relative to GIT_DIR)
# Use dirname to avoid depending on $GIT_DIR existing at shell-parse time.
PEONS_DIR_DEFAULT="$(dirname "$GIT_DIR")/peons"
PEONS_DIR="${PEONS_DIR:-$PEONS_DIR_DEFAULT}"

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
    # Ensure workspace exists so df works even when not mounted as tmpfs
    mkdir -p "$RAM_WORKSPACE"

    local available
    available=$(df -BG "$RAM_WORKSPACE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -z "$available" ]; then
        warn "Could not determine available space for $RAM_WORKSPACE; skipping space check"
        return 0
    fi

    local total_size=0
    local path

    for path in "$GIT_DIR"/*; do
        if [ -e "$path" ]; then
            local size
            size=$(du -sm "$path" 2>/dev/null | cut -f1 || echo 0)
            total_size=$((total_size + size))
        fi
    done

    if [ -d "$PEONS_DIR" ]; then
        local peons_size
        peons_size=$(du -sm "$PEONS_DIR" 2>/dev/null | cut -f1 || echo 0)
        total_size=$((total_size + peons_size))
    fi

    local total_gb=$((total_size / 1024 + 1))

    if [ "$total_gb" -gt "$available" ]; then
        error "Not enough space. Need ~${total_gb}GB, have ${available}GB available at $RAM_WORKSPACE"
        return 1
    fi

    log "Space check passed: ~${total_gb}GB needed, ${available}GB available"
    return 0
}

sync_path() {
    local src_path="$1"
    local name
    name=$(basename "$src_path")
    local dest_path="$RAM_WORKSPACE/$name"

    log "Syncing $name to RAM..."

    # Remove existing destination (file/dir/symlink)
    if [ -e "$dest_path" ] || [ -L "$dest_path" ]; then
        rm -rf "$dest_path"
    fi

    # Copy into RAM workspace, preserving attributes/symlinks
    cp -a "$src_path" "$RAM_WORKSPACE/"

    if [ -e "$dest_path" ] || [ -L "$dest_path" ]; then
        log "✓ $name synced successfully"
        return 0
    fi

    error "✗ Failed to sync $name"
    return 1
}

main() {
    log "Starting sync to RAM workspace"

    # Check if git directory exists
    if [ ! -d "$GIT_DIR" ]; then
        error "Source directory not found: $GIT_DIR"
        exit 1
    fi

    mkdir -p "$RAM_WORKSPACE"

    # Warn (but do not fail) if the workspace is not a tmpfs mount
    if ! mountpoint -q "$RAM_WORKSPACE"; then
        warn "$RAM_WORKSPACE is not a mountpoint (tmpfs not detected). Continuing anyway."
    fi
    
    # Check available space
    if ! check_tmpfs_space; then
        exit 1
    fi
    
    local success_count=0
    local total_count=0
    
    # Sync everything in the root of the git folder (dirs *and* files)
    for path in "$GIT_DIR"/*; do
        if [ -e "$path" ]; then
            total_count=$((total_count + 1))
            if sync_path "$path"; then
                success_count=$((success_count + 1))
            fi
        fi
    done

    # Also sync ../peons if it exists (relative to $GIT_DIR)
    if [ -d "$PEONS_DIR" ]; then
        total_count=$((total_count + 1))
        if sync_path "$PEONS_DIR"; then
            success_count=$((success_count + 1))
        fi
    else
        warn "Optional extra directory not found (skipping): $PEONS_DIR"
    fi

    log "Sync completed: $success_count/$total_count items synced"
    
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
    echo "Syncs everything in the root of ~/git to the RAM workspace"
    echo "Also syncs ../peons (relative to the git dir) when it exists"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be synced without actually doing it"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment overrides:"
    echo "  GIT_DIR=...        Source directory (default: ~/git)"
    echo "  RAM_WORKSPACE=...  Destination directory (default: /tmp/dev-workspace)"
    echo "  PEONS_DIR=...      Extra directory (default: ../peons relative to GIT_DIR)"
    echo "  SYNC_LOG=...       Log file path (default: ~/git-sync.log)"
    echo ""
    echo "Log file: $SYNC_LOG"
    exit 0
fi

# Dry run mode
if [ "$1" = "--dry-run" ]; then
    log "DRY RUN - showing what would be synced:"
    for path in "$GIT_DIR"/*; do
        if [ -e "$path" ]; then
            name=$(basename "$path")
            echo "  ✓ $name ($(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown"))"
        fi
    done

    if [ -d "$PEONS_DIR" ]; then
        echo "  ✓ $(basename "$PEONS_DIR") ($(du -sh "$PEONS_DIR" 2>/dev/null | cut -f1 || echo "unknown"))"
    else
        echo "  ✗ $(basename "$PEONS_DIR") (missing: $PEONS_DIR)"
    fi
    exit 0
fi

main "$@"