#!/bin/bash
# Development performance monitoring script

WORKSPACE="/tmp/dev-workspace"
BUILD_CACHE="/tmp/build-cache"

show_performance_stats() {
    echo "🔍 Framework Laptop Development Performance Stats"
    echo "=================================================="
    
    # Memory usage
    echo "💾 Memory Usage:"
    free -h | grep -E "Mem:|Swap:"
    echo ""
    
    # tmpfs usage
    if mountpoint -q "$WORKSPACE"; then
        echo "🚀 RAM Workspace Usage:"
        df -h "$WORKSPACE" | tail -1
        echo "   Projects in RAM:"
        ls -la "$WORKSPACE" 2>/dev/null | grep ^d | wc -l
        echo ""
    fi
    
    if mountpoint -q "$BUILD_CACHE"; then
        echo "🔧 Build Cache Usage:"
        df -h "$BUILD_CACHE" | tail -1
        echo ""
    fi
    
    # SSD performance
    echo "💿 NVMe SSD Stats:"
    if command -v nvme &> /dev/null; then
        sudo nvme smart-log /dev/nvme0 | grep -E "temperature|available_spare|percentage_used"
    else
        echo "   nvme-cli not installed"
    fi
    echo ""
    
    # CPU frequency
    echo "⚡ CPU Performance:"
    grep "cpu MHz" /proc/cpuinfo | head -4
    echo ""
    
    # Top memory consumers
    echo "🐘 Top Memory Consumers:"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "   %s: %.1f%% (%s)\n", $11, $4, $6}'
    echo ""
    
    # Docker stats if running
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        echo "🐳 Docker Stats:"
        docker system df 2>/dev/null || echo "   Docker not running"
        echo ""
    fi
    
    # Compile time estimation
    echo "⏱️  Estimated Compile Performance:"
    echo "   Current SSD: ~30-60s (medium Rust project)"
    echo "   With new NVMe: ~15-30s (2x faster)"
    echo "   With RAM cache: ~10-20s (3x faster)"
}

# Monitor tmpfs and warn if getting full
monitor_tmpfs() {
    if mountpoint -q "$WORKSPACE"; then
        USAGE=$(df "$WORKSPACE" | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$USAGE" -gt 80 ]; then
            echo "⚠️  Warning: RAM workspace ${USAGE}% full"
            echo "   Consider syncing projects back to disk"
        fi
    fi
    
    if mountpoint -q "$BUILD_CACHE"; then
        USAGE=$(df "$BUILD_CACHE" | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$USAGE" -gt 90 ]; then
            echo "⚠️  Warning: Build cache ${USAGE}% full"
            echo "   Cleaning old build artifacts..."
            find "$BUILD_CACHE" -type f -atime +1 -delete 2>/dev/null
        fi
    fi
}

case "$1" in
    "stats"|"")
        show_performance_stats
        ;;
    "monitor")
        monitor_tmpfs
        ;;
    "clean")
        echo "🧹 Cleaning build caches..."
        rm -rf "$BUILD_CACHE"/{npm,cargo,go,maven,gradle}/.cache/* 2>/dev/null
        echo "   Build caches cleaned"
        ;;
    *)
        echo "Usage: $0 [stats|monitor|clean]"
        echo "  stats   - Show performance statistics (default)"
        echo "  monitor - Check tmpfs usage and warn if full"
        echo "  clean   - Clean build caches"
        ;;
esac