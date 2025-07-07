#!/bin/bash
# System Performance Optimization for Debian 12 on Framework Laptop
# Intel i7-1280P | 32GB RAM | 2TB NVMe SSD
# Optimizes CPU, NVMe, memory, and kernel parameters

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
    fi
}

install_performance_tools() {
    log "Installing performance tools for Debian 12..."
    
    # Update package list
    sudo apt-get update
    
    # Install performance monitoring and tuning tools
    sudo apt-get install -y \
        linux-cpupower \
        htop iotop iftop nethogs \
        sysstat dstat \
        powertop tlp tlp-rdw \
        cpufrequtils \
        nvme-cli smartmontools \
        preload \
        earlyoom \
        irqbalance \
        tuned tuned-utils \
        intel-microcode \
        firmware-misc-nonfree
    
    log "Performance tools installed"
}

optimize_cpu_performance() {
    log "Optimizing CPU performance..."
    
    # Set CPU governor to performance during AC power
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g performance
    fi
    
    # Create TLP configuration optimized for Framework Laptop
    sudo tee /etc/tlp.conf > /dev/null << 'EOF'
# Framework Laptop TLP Configuration for Debian 12
# Intel i7-1280P Optimization

# CPU Performance
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# Intel CPU (i7-1280P specific)
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_MIN_PERF_ON_AC=50
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=20
CPU_MAX_PERF_ON_BAT=80

# Platform Profile
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=balanced

# Turbo Boost
CPU_HWP_DYN_BOOST_ON_AC=1
CPU_HWP_DYN_BOOST_ON_BAT=0

# PCIe Active State Power Management
PCIE_ASPM_ON_AC=performance
PCIE_ASPM_ON_BAT=powersupersave

# Runtime Power Management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# USB Autosuspend
USB_AUTOSUSPEND=0

# WiFi Power Saving
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# Restore settings on startup
RESTORE_DEVICE_STATE_ON_STARTUP=1
EOF
    
    # Enable TLP
    sudo systemctl enable tlp
    sudo systemctl start tlp
}

optimize_ssd_performance() {
    log "Optimizing SSD performance..."
    
    # Get SSD device (assuming NVMe)
    SSD_DEVICE=$(lsblk -d -o NAME,TYPE | grep -E "nvme[0-9]n[0-9]" | head -1 | awk '{print $1}')
    
    if [ -n "$SSD_DEVICE" ]; then
        log "Found NVMe SSD: $SSD_DEVICE"
        
        # Set optimal I/O scheduler for NVMe
        echo "none" | sudo tee /sys/block/$SSD_DEVICE/queue/scheduler
        
        # Increase nr_requests for better throughput
        echo "1024" | sudo tee /sys/block/$SSD_DEVICE/queue/nr_requests
        
        # Set read-ahead value
        echo "256" | sudo tee /sys/block/$SSD_DEVICE/queue/read_ahead_kb
        
        # Make changes persistent
        sudo tee /etc/udev/rules.d/60-ssd-optimization.rules > /dev/null << EOF
# SSD Optimization Rules
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="256"
EOF
    fi
    
    # Enable TRIM for SSDs
    sudo systemctl enable fstrim.timer
    sudo systemctl start fstrim.timer
}

optimize_memory_management() {
    log "Optimizing memory management..."
    
    # Calculate optimal values based on 32GB RAM
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
    
    # Create sysctl configuration
    sudo tee /etc/sysctl.d/99-performance.conf > /dev/null << EOF
# Memory Performance Optimizations for 32GB RAM

# Reduce swappiness (use swap less aggressively)
vm.swappiness=10

# Increase cache pressure (free up cache more aggressively when needed)
vm.vfs_cache_pressure=50

# Dirty pages settings (optimize for SSD)
vm.dirty_background_ratio=5
vm.dirty_ratio=10
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# Increase inotify limits for development tools
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512

# Increase file handle limits
fs.file-max=2097152
fs.nr_open=1048576

# Network optimizations
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=5000
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq

# Enable BBR TCP congestion control
net.ipv4.tcp_congestion_control=bbr

# Disable transparent huge pages for databases
kernel.transparent_hugepage=madvise

# Increase kernel PID limit
kernel.pid_max=4194304

# Better memory overcommit handling
vm.overcommit_memory=0
vm.overcommit_ratio=50

# Min free memory (1% of total RAM)
vm.min_free_kbytes=$((TOTAL_MEM_KB * 1 / 100))

# Disable zone reclaim (better for NUMA systems)
vm.zone_reclaim_mode=0

# Increase maximum map count for applications like Elasticsearch
vm.max_map_count=262144
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-performance.conf
}

setup_zram_swap() {
    log "Setting up ZRAM compressed swap for Debian 12..."
    
    # Install zram-tools
    sudo apt-get install -y zram-tools systemd-zram-generator
    
    # Configure ZRAM (25% of 32GB = 8GB compressed swap)
    sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
zram-size = min(ram / 4, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
    
    # Enable and start zram
    sudo systemctl daemon-reload
    sudo systemctl enable systemd-zram-setup@zram0.service
    sudo systemctl start systemd-zram-setup@zram0.service
    
    log "ZRAM swap configured"
}

optimize_kernel_modules() {
    log "Optimizing kernel modules..."
    
    # Blacklist unused modules to save memory
    sudo tee /etc/modprobe.d/blacklist-unused.conf > /dev/null << 'EOF'
# Blacklist unused modules
blacklist pcspkr
blacklist snd_pcsp
blacklist bluetooth
blacklist btusb
EOF
    
    # Intel specific optimizations
    sudo tee /etc/modprobe.d/intel-graphics.conf > /dev/null << 'EOF'
# Intel Graphics Optimizations
options i915 enable_guc=3
options i915 enable_fbc=1
options i915 enable_psr=1
options i915 fastboot=1
EOF
}

setup_earlyoom() {
    log "Setting up earlyOOM killer..."
    
    # Configure earlyOOM to prevent system freezes
    sudo tee /etc/default/earlyoom > /dev/null << 'EOF'
# EarlyOOM configuration
EARLYOOM_ARGS="-r 3600 -m 5 -s 10 --avoid '(^|/)(init|systemd|Xorg|sshd)$' --prefer '(^|/)(firefox|chromium|chrome)$'"
EOF
    
    sudo systemctl enable earlyoom
    sudo systemctl start earlyoom
}

optimize_systemd_boot() {
    log "Optimizing systemd boot time..."
    
    # Disable unnecessary services
    SERVICES_TO_DISABLE=(
        "ModemManager.service"
        "bluetooth.service"
        "cups.service"
        "cups-browsed.service"
        "avahi-daemon.service"
    )
    
    for service in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl is-enabled "$service" &> /dev/null; then
            sudo systemctl disable "$service"
            log "Disabled $service"
        fi
    done
    
    # Mask services we definitely don't need
    sudo systemctl mask systemd-binfmt.service
}

create_performance_profile() {
    log "Creating performance tuned profile..."
    
    if command -v tuned-adm &> /dev/null; then
        # Create custom tuned profile for Framework Laptop
        sudo mkdir -p /etc/tuned/framework-performance
        sudo tee /etc/tuned/framework-performance/tuned.conf > /dev/null << 'EOF'
[main]
summary=Framework Laptop Debian 12 Performance Profile
include=throughput-performance

[cpu]
force_latency=1
governor=performance
energy_perf_bias=performance
min_perf_pct=50

[sysctl]
vm.swappiness=10
vm.dirty_ratio=10
vm.dirty_background_ratio=5

[disk]
devices=nvme*
readahead=256
scheduler=none
EOF
        
        # Enable the profile
        sudo tuned-adm profile framework-performance
    fi
}

setup_monitoring_cron() {
    log "Setting up performance monitoring cron jobs..."
    
    # Create cron job for memory monitoring
    (crontab -l 2>/dev/null || true; echo "*/30 * * * * $HOME/memory-monitor.sh") | crontab -
}

main() {
    log "Starting system performance optimization..."
    
    check_root
    install_performance_tools
    optimize_cpu_performance
    optimize_ssd_performance
    optimize_memory_management
    setup_zram_swap
    optimize_kernel_modules
    setup_earlyoom
    optimize_systemd_boot
    create_performance_profile
    setup_monitoring_cron
    
    echo ""
    log "System performance optimization complete!"
    echo ""
    echo "Optimizations applied:"
    echo "✓ CPU governor set to performance mode"
    echo "✓ TLP power management configured"
    echo "✓ SSD I/O scheduler optimized"
    echo "✓ Memory management tuned for 32GB RAM"
    echo "✓ ZRAM compressed swap enabled"
    echo "✓ Kernel parameters optimized"
    echo "✓ EarlyOOM configured for stability"
    echo "✓ Boot time optimized"
    echo ""
    echo "Performance tools installed:"
    echo "- htop: Advanced process viewer"
    echo "- iotop: I/O usage monitor"
    echo "- powertop: Power consumption analyzer"
    echo "- nvme-cli: NVMe SSD management"
    echo "- tlp: Advanced power management"
    echo "- tuned: System tuning daemon"
    echo ""
    log "Please reboot to apply all optimizations"
}

main "$@"