#!/usr/bin/env bash

# sync-all-git-to-ram.sh
# Syncs Git repositories from a source directory into a RAM workspace directory.
#
# Default behavior: preserve a "company" layout commonly used under ~/git:
#
#   ~/git/<repo>
#   ~/git/<company>/<repo>
#
# The RAM workspace mirrors this structure:
#
#   $RAM_WORKSPACE/<repo>
#   $RAM_WORKSPACE/<company>/<repo>
#
# Only one nesting level is supported for grouping (company -> repo). Repo contents
# themselves are copied recursively.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source and destination
#
# This repo's README suggests cloning under ~/git, so prefer that by default.
# You can override with:
#   GIT_DIR=/path/to/repos RAM_WORKSPACE=/tmp/dev-workspace ./sync-all-git-to-ram.sh
RAM_WORKSPACE="${RAM_WORKSPACE:-/tmp/dev-workspace}"

has_child_git_repos() {
    # Returns 0 if dir has at least one immediate child directory that is a Git root.
    local dir="$1"
    [ -d "$dir" ] || return 1

    shopt -s nullglob
    local child
    for child in "$dir"/*; do
        [ -d "$child" ] || continue
        [ "$(basename "$child")" = ".git" ] && continue
        if is_git_root "$child"; then
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

is_git_root() {
    local dir="$1"
    [ -d "$dir" ] || return 1

    # A normal worktree repo root has a .git file/dir.
    if [ -e "$dir/.git" ]; then
        return 0
    fi

    # Optional: detect bare repos (no .git) without misclassifying subdirectories.
    if command -v git >/dev/null 2>&1; then
        local is_bare
        is_bare=$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null || true)
        [ "$is_bare" = "true" ] && return 0
    fi

    return 1
}

GIT_DIR="${GIT_DIR:-}"
if [ -z "$GIT_DIR" ]; then
    if [ -d "$HOME/git" ]; then
        GIT_DIR="$HOME/git"
    else
        # Backwards-compatible fallback (older docs referenced ./git relative to this script)
        GIT_DIR="$SCRIPT_DIR/git"
    fi
fi

sync_repo_to_dest() {
    # Sync a repo directory (src) into an exact destination directory (dest).
    # dest is the final directory path (not the parent).
    local src_dir="$1"
    local dest_dir="$2"

    echo "Syncing $(basename "$dest_dir")..."

    mkdir -p "$(dirname "$dest_dir")"

    if command -v rsync >/dev/null 2>&1; then
        mkdir -p "$dest_dir"
        # Use trailing slashes to sync *contents* into the destination directory.
        rsync -a --delete "$src_dir/" "$dest_dir/"
    else
        rm -rf "$dest_dir"
        cp -a "$src_dir" "$dest_dir"
    fi

    [ -e "$dest_dir" ] || [ -L "$dest_dir" ]
}

main() {
    if [ ! -d "$GIT_DIR" ]; then
        echo "ERROR: Source directory not found: $GIT_DIR" >&2
        echo "Hint: set GIT_DIR to the directory that contains your repositories (commonly: ~/git)" >&2
        exit 1
    fi

    mkdir -p "$RAM_WORKSPACE"

    if [ "${CLEAN_WORKSPACE:-0}" = "1" ]; then
        # Safety guard: never allow cleaning an empty or root-like path.
        if [ -z "$RAM_WORKSPACE" ] || [ "$RAM_WORKSPACE" = "/" ]; then
            echo "ERROR: Refusing to clean unsafe RAM_WORKSPACE: '$RAM_WORKSPACE'" >&2
            exit 1
        fi

        echo "Cleaning RAM workspace: $RAM_WORKSPACE"
        shopt -s dotglob nullglob
        rm -rf "$RAM_WORKSPACE"/*
        shopt -u dotglob nullglob
    fi

    local success_count=0
    local total_count=0
    local skipped_count=0
    
    info() { echo "[sync] $*"; }

    info "Source (GIT_DIR): $GIT_DIR"
    info "Destination (RAM_WORKSPACE): $RAM_WORKSPACE"
    info "Layout: preserve top-level repos and one-level company folders"

    shopt -s nullglob
    local top
    for top in "$GIT_DIR"/*; do
        [ -d "$top" ] || continue
        [ "$(basename "$top")" = ".git" ] && continue

        # Treat any directory that contains child repos as a company/group folder,
        # even if it happens to have its own .git.
        if has_child_git_repos "$top"; then
            local company
            company="$(basename "$top")"
            local child
            for child in "$top"/*; do
                [ -d "$child" ] || continue
                [ "$(basename "$child")" = ".git" ] && continue
                total_count=$((total_count + 1))
                if is_git_root "$child"; then
                    if sync_repo_to_dest "$child" "$RAM_WORKSPACE/$company/$(basename "$child")"; then
                        success_count=$((success_count + 1))
                    fi
                else
                    skipped_count=$((skipped_count + 1))
                fi
            done
            continue
        fi

        # Otherwise, copy top-level repos directly.
        total_count=$((total_count + 1))
        if is_git_root "$top"; then
            if sync_repo_to_dest "$top" "$RAM_WORKSPACE/$(basename "$top")"; then
                success_count=$((success_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
        fi
    done
    shopt -u nullglob

    echo "Sync completed: $success_count repos synced, $skipped_count skipped (from $total_count dirs checked)"
    echo "RAM workspace: $RAM_WORKSPACE"
}

usage() {
    echo "Usage: $0 [--dry-run] [--clean|--no-clean]"
    echo ""
    echo "Syncs Git repositories found under GIT_DIR into the RAM workspace"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be synced without actually doing it"
    echo "  --clean      Remove existing contents of RAM_WORKSPACE before syncing"
    echo "  --no-clean   Do not remove existing contents (default)"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment overrides:"
    echo "  GIT_DIR=...        Source directory (default: ~/git if it exists; else: ./git relative to this script)"
    echo "  RAM_WORKSPACE=...  Destination directory (default: /tmp/dev-workspace)"
}

DRY_RUN=0
: "${CLEAN_WORKSPACE:=0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --clean)
            CLEAN_WORKSPACE=1
            ;;
        --no-clean)
            CLEAN_WORKSPACE=0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY RUN - showing what would be synced:"

    shopt -s nullglob
    for top in "$GIT_DIR"/*; do
        [ -d "$top" ] || continue
        [ "$(basename "$top")" = ".git" ] && continue

        if has_child_git_repos "$top"; then
            company="$(basename "$top")"
            for child in "$top"/*; do
                [ -d "$child" ] || continue
                [ "$(basename "$child")" = ".git" ] && continue
                if is_git_root "$child"; then
                    echo "  ✓ $company/$(basename "$child")  <- $child"
                fi
            done
        else
            if is_git_root "$top"; then
                echo "  ✓ $(basename "$top")  <- $top"
            fi
        fi
    done
    shopt -u nullglob
    exit 0
fi

main "$@"