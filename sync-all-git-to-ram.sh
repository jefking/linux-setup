#!/usr/bin/env bash

# sync-all-git-to-ram.sh
# Mirrors the full DEV_GIT_DIR tree into RAM_WORKSPACE.
# This intentionally copies everything under the git root (not just detected repos).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAM_WORKSPACE="${RAM_WORKSPACE:-/tmp/dev-workspace}"
DRY_RUN=0
: "${CLEAN_WORKSPACE:=0}"

# Prefer DEV_GIT_DIR. Keep GIT_DIR as a backward-compatible fallback input only.
DEV_GIT_DIR="${DEV_GIT_DIR:-${GIT_DIR:-}}"
if [ -z "$DEV_GIT_DIR" ]; then
    if [ -d "$HOME/git" ]; then
        DEV_GIT_DIR="$HOME/git"
    else
        # Backward-compatible fallback (older docs used ./git next to this script).
        DEV_GIT_DIR="$SCRIPT_DIR/git"
    fi
fi

# Never allow inherited git env vars to affect nested git commands.
unset GIT_DIR
unset GIT_WORK_TREE

usage() {
    echo "Usage: $0 [--dry-run] [--clean|--no-clean]"
    echo ""
    echo "Mirrors all content from DEV_GIT_DIR into RAM_WORKSPACE"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be copied without writing"
    echo "  --clean      Remove existing contents of RAM_WORKSPACE before syncing"
    echo "  --no-clean   Do not remove existing contents (default)"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment overrides:"
    echo "  DEV_GIT_DIR=...    Source directory (default: ~/git if present; else: ./git)"
    echo "  GIT_DIR=...        (Deprecated) Same as DEV_GIT_DIR input only"
    echo "  RAM_WORKSPACE=...  Destination directory (default: /tmp/dev-workspace)"
}

sync_tree() {
    local src="$1"
    local dst="$2"

    if command -v rsync >/dev/null 2>&1; then
        local -a rsync_opts
        rsync_opts=(-a)
        if [ "$DRY_RUN" = "1" ]; then
            rsync_opts+=(--dry-run --itemize-changes)
        fi
        rsync "${rsync_opts[@]}" "$src/" "$dst/"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        echo "DRY RUN: cp -a \"$src/.\" \"$dst/\""
        return 0
    fi

    cp -a "$src/." "$dst/"
}

main() {
    if [ ! -d "$DEV_GIT_DIR" ]; then
        echo "ERROR: Source directory not found: $DEV_GIT_DIR" >&2
        echo "Hint: set DEV_GIT_DIR to your git root (commonly: ~/git)" >&2
        exit 1
    fi

    mkdir -p "$RAM_WORKSPACE"

    if [ "$CLEAN_WORKSPACE" = "1" ]; then
        # Safety guard: never allow cleaning unsafe paths.
        if [ -z "$RAM_WORKSPACE" ] || [ "$RAM_WORKSPACE" = "/" ]; then
            echo "ERROR: Refusing to clean unsafe RAM_WORKSPACE: '$RAM_WORKSPACE'" >&2
            exit 1
        fi

        echo "Cleaning RAM workspace: $RAM_WORKSPACE"
        if [ "$DRY_RUN" = "0" ]; then
            shopt -s dotglob nullglob
            rm -rf "$RAM_WORKSPACE"/*
            shopt -u dotglob nullglob
        else
            echo "DRY RUN: rm -rf \"$RAM_WORKSPACE\"/*"
        fi
    fi

    echo "[sync] Source (DEV_GIT_DIR): $DEV_GIT_DIR"
    echo "[sync] Destination (RAM_WORKSPACE): $RAM_WORKSPACE"
    echo "[sync] Mode: full tree copy"

    sync_tree "$DEV_GIT_DIR" "$RAM_WORKSPACE"

    if [ "$DRY_RUN" = "1" ]; then
        echo "Dry run complete"
    else
        echo "Sync completed"
    fi
    echo "RAM workspace: $RAM_WORKSPACE"
}

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

main "$@"
