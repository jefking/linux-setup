#!/usr/bin/env bash

# sync-all-git-to-ram.sh
# Copies the top-level entries under ./git/* into a RAM workspace directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# By default, use ./git relative to this script.
GIT_DIR="${GIT_DIR:-$SCRIPT_DIR/git}"
RAM_WORKSPACE="${RAM_WORKSPACE:-/tmp/dev-workspace}"

sync_path() {
    local src_path="$1"
    local name
    name=$(basename "$src_path")
    local dest_path="$RAM_WORKSPACE/$name"

    echo "Syncing $name..."

    # Remove existing destination (file/dir/symlink)
    rm -rf "$dest_path"

    # Copy into RAM workspace, preserving attributes/symlinks
    cp -a "$src_path" "$RAM_WORKSPACE/"

    [ -e "$dest_path" ] || [ -L "$dest_path" ]
}

main() {
    if [ ! -d "$GIT_DIR" ]; then
        echo "ERROR: Source directory not found: $GIT_DIR" >&2
        exit 1
    fi

    mkdir -p "$RAM_WORKSPACE"

    local success_count=0
    local total_count=0
    
    # Sync everything in the root of ./git (dirs *and* files)
    for path in "$GIT_DIR"/*; do
        if [ -e "$path" ]; then
            total_count=$((total_count + 1))
            if sync_path "$path"; then
                success_count=$((success_count + 1))
            fi
        fi
    done

    echo "Sync completed: $success_count/$total_count items synced"
    echo "RAM workspace: $RAM_WORKSPACE"
}

# Show usage if help requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [--dry-run]"
    echo ""
    echo "Syncs everything in the root of ./git (relative to this script) to the RAM workspace"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be synced without actually doing it"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment overrides:"
    echo "  GIT_DIR=...        Source directory (default: ./git relative to this script)"
    echo "  RAM_WORKSPACE=...  Destination directory (default: /tmp/dev-workspace)"
    exit 0
fi

# Dry run mode
if [ "${1:-}" = "--dry-run" ]; then
    echo "DRY RUN - showing what would be synced:"
    for path in "$GIT_DIR"/*; do
        if [ -e "$path" ]; then
            name=$(basename "$path")
            echo "  ✓ $name"
        fi
    done
    exit 0
fi

main "$@"