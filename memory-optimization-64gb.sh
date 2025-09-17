#!/bin/bash
# Memory Optimization for 64GB RAM Systems
# Debian 13 | AMD Ryzen AI 9 HX 370 | 64GB RAM
# Optimizes memory management for high-memory systems

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_memory() {
    log "Checking system memory..."
    
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
    
    if [ $TOTAL_MEM_GB -lt 32 ]; then
        error "This script is designed for systems with 32GB+ RAM. Found: ${TOTAL_MEM_GB}GB"
    fi
    
    log "Detected ${TOTAL_MEM_GB}GB RAM - optimizing for high-memory system"
}

optimize_memory_settings() {
    log "Optimizing memory settings for 64GB RAM..."
    
    # Create memory optimization configuration
    sudo tee /etc/sysctl.d/99-memory-64gb.conf > /dev/null << EOF
# Memory Optimizations for 64GB RAM Systems

# Minimal swapping with abundant RAM
vm.swappiness=1

# Cache pressure - be more aggressive about freeing cache when needed
vm.vfs_cache_pressure=50

# Dirty page settings optimized for NVMe SSD with 64GB RAM
vm.dirty_background_ratio=1
vm.dirty_ratio=3
vm.dirty_expire_centisecs=1000
vm.dirty_writeback_centisecs=100

# Memory overcommit settings for high-memory systems
vm.overcommit_memory=0
vm.overcommit_ratio=80

# Minimum free memory (0.5% of total RAM)
vm.min_free_kbytes=$((TOTAL_MEM_KB * 5 / 1000))

# Zone reclaim disabled for better performance
vm.zone_reclaim_mode=0

# Increase maximum map count for memory-intensive applications
vm.max_map_count=1048576

# Transparent hugepage settings
vm.transparent_hugepage=madvise

# Memory compaction settings
vm.compact_memory=1
vm.compaction_proactiveness=20

# NUMA balancing for multi-core AMD systems
kernel.numa_balancing=1

# Page allocation settings
vm.percpu_pagelist_fraction=0

# Memory allocation settings for high-memory systems
vm.lowmem_reserve_ratio=256 256 32 0 0

# OOM killer settings
vm.oom_kill_allocating_task=0
vm.oom_dump_tasks=1
vm.panic_on_oom=0

# Kernel memory settings
kernel.shmmax=$((TOTAL_MEM_KB * 1024 / 2))
kernel.shmall=$((TOTAL_MEM_KB / 4))
EOF

    # Apply settings
    sudo sysctl -p /etc/sysctl.d/99-memory-64gb.conf
}

setup_enhanced_zram() {
    log "Setting up enhanced ZRAM for 64GB system..."
    
    # Install zram tools if not present
    sudo apt-get install -y zram-tools systemd-zram-generator
    
    # Configure ZRAM for 64GB system (4GB compressed swap)
    sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
zram-size = min(ram / 16, 4096)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

    # Enable and start zram
    sudo systemctl daemon-reload
    sudo systemctl enable systemd-zram-setup@zram0.service
    sudo systemctl start systemd-zram-setup@zram0.service
}

create_ram_workspace() {
    log "Creating enhanced RAM workspace for development..."
    
    # Create large RAM workspace (16GB for development)
    sudo mkdir -p /tmp/dev-workspace-64gb
    sudo mkdir -p /tmp/build-cache-64gb
    
    # Mount tmpfs with optimized settings for 64GB system
    if ! grep -q "/tmp/dev-workspace-64gb" /etc/fstab; then
        echo "tmpfs /tmp/dev-workspace-64gb tmpfs defaults,noatime,size=16G,mode=1777 0 0" | sudo tee -a /etc/fstab
    fi
    
    if ! grep -q "/tmp/build-cache-64gb" /etc/fstab; then
        echo "tmpfs /tmp/build-cache-64gb tmpfs defaults,noatime,size=8G,mode=1777 0 0" | sudo tee -a /etc/fstab
    fi
    
    # Mount the tmpfs
    sudo mount -a
    
    # Create directory structure
    mkdir -p /tmp/dev-workspace-64gb/{projects,git,temp}
    mkdir -p /tmp/build-cache-64gb/{npm,cargo,go,maven,gradle,docker,ccache}
    
    # Set permissions
    sudo chown -R $USER:$USER /tmp/dev-workspace-64gb /tmp/build-cache-64gb
}

optimize_memory_allocator() {
    log "Optimizing memory allocator settings..."
    
    # Create memory allocator optimizations
    sudo tee /etc/environment > /dev/null << 'EOF'
# Memory allocator optimizations for 64GB systems

# jemalloc optimizations
MALLOC_CONF="background_thread:true,metadata_thp:auto,dirty_decay_ms:5000,muzzy_decay_ms:10000"

# glibc malloc optimizations
MALLOC_ARENA_MAX=8
MALLOC_MMAP_THRESHOLD_=131072
MALLOC_TRIM_THRESHOLD_=131072
MALLOC_TOP_PAD_=131072
MALLOC_MMAP_MAX_=65536
EOF
}

setup_memory_monitoring() {
    log "Setting up memory monitoring for 64GB system..."
    
    # Create enhanced memory monitor
    cat > "$HOME/bin/memory-monitor-64gb" << 'EOF'
#!/bin/bash
# Enhanced Memory Monitor for 64GB Systems

echo "=== 64GB Memory System Status ==="
echo ""

# Memory overview
echo "Memory Overview:"
free -h | grep -E "Mem:|Swap:"
echo ""

# Detailed memory breakdown
echo "Detailed Memory Usage:"
awk '/^MemTotal:|^MemFree:|^MemAvailable:|^Buffers:|^Cached:|^SReclaimable:|^Shmem:/ {printf "%-15s %8s %s\n", $1, $2, $3}' /proc/meminfo
echo ""

# ZRAM status
echo "ZRAM Status:"
if [ -f /proc/swaps ]; then
    grep zram /proc/swaps 2>/dev/null || echo "ZRAM not active"
fi
echo ""

# tmpfs usage
echo "RAM Workspace Usage:"
df -h | grep -E "(dev-workspace|build-cache)" || echo "RAM workspaces not mounted"
echo ""

# Memory pressure indicators
echo "Memory Pressure:"
echo "Swappiness: $(cat /proc/sys/vm/swappiness)"
echo "Dirty ratio: $(cat /proc/sys/vm/dirty_ratio)%"
echo "Cache pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
echo ""

# Top memory consumers
echo "Top Memory Consumers:"
ps aux --sort=-%mem | head -6 | awk '{printf "%-12s %6s %6s %s\n", $1, $4"%", $6/1024"MB", $11}'
echo ""

# Memory allocation info
echo "Memory Allocation:"
echo "Committed: $(awk '/^Committed_AS:/ {print $2 " " $3}' /proc/meminfo)"
echo "CommitLimit: $(awk '/^CommitLimit:/ {print $2 " " $3}' /proc/meminfo)"
EOF

    chmod +x "$HOME/bin/memory-monitor-64gb"
    mkdir -p "$HOME/bin"
}

create_memory_aliases() {
    log "Creating memory management aliases..."
    
    # Add aliases to bashrc
    cat >> "$HOME/.bashrc" << 'EOF'

# 64GB Memory System Aliases
alias mem64='memory-monitor-64gb'
alias ram-workspace='cd /tmp/dev-workspace-64gb'
alias build-cache='cd /tmp/build-cache-64gb'
alias clear-cache='sudo sysctl vm.drop_caches=3'
alias mem-pressure='cat /proc/pressure/memory 2>/dev/null || echo "Memory pressure info not available"'

# Development workspace functions
dev-to-ram() {
    if [ -z "$1" ]; then
        echo "Usage: dev-to-ram <project-path>"
        return 1
    fi
    rsync -av "$1" /tmp/dev-workspace-64gb/
    echo "Project synced to RAM workspace"
}

dev-from-ram() {
    if [ -z "$1" ]; then
        echo "Usage: dev-from-ram <project-name>"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "Usage: dev-from-ram <project-name> <destination-path>"
        return 1
    fi
    rsync -av "/tmp/dev-workspace-64gb/$1" "$2"
    echo "Project synced from RAM workspace"
}
EOF
}

setup_memory_service() {
    log "Setting up memory optimization service..."
    
    # Create systemd service for memory optimizations
    sudo tee /etc/systemd/system/memory-64gb-optimization.service > /dev/null << 'EOF'
[Unit]
Description=64GB Memory System Optimization
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/memory-64gb-optimize
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # Create the optimization script
    sudo tee /usr/local/bin/memory-64gb-optimize > /dev/null << 'EOF'
#!/bin/bash
# Memory optimization script for 64GB systems

# Apply memory settings
sysctl -p /etc/sysctl.d/99-memory-64gb.conf

# Ensure tmpfs mounts are active
mount -a

# Set memory allocator environment
export MALLOC_CONF="background_thread:true,metadata_thp:auto"
EOF

    sudo chmod +x /usr/local/bin/memory-64gb-optimize
    sudo systemctl enable memory-64gb-optimization.service
}

main() {
    log "Starting 64GB memory optimization..."
    
    check_memory
    optimize_memory_settings
    setup_enhanced_zram
    create_ram_workspace
    optimize_memory_allocator
    setup_memory_monitoring
    create_memory_aliases
    setup_memory_service
    
    echo ""
    log "64GB memory optimization complete!"
    echo ""
    echo "✅ Memory settings optimized for 64GB RAM"
    echo "✅ Enhanced ZRAM configured (4GB compressed)"
    echo "✅ RAM workspace created (16GB + 8GB cache)"
    echo "✅ Memory allocator optimized"
    echo "✅ Monitoring tools installed"
    echo "✅ Development aliases created"
    echo ""
    echo "📊 Check memory status with: mem64"
    echo "🚀 Use RAM workspace with: ram-workspace"
    echo "🔄 Reboot recommended to apply all optimizations"
}

main "$@"
