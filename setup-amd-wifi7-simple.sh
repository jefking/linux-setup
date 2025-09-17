#!/bin/bash
# Simplified AMD Ryzen AI 9 HX 370 + WiFi 7 Setup
# Handles Debian 13 package availability issues

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
    fi
}

install_essential_tools() {
    log "Installing essential performance tools..."
    
    sudo apt-get update
    
    # Install only packages that are definitely available in Debian 13
    sudo apt-get install -y \
        linux-cpupower \
        htop \
        iotop \
        sysstat \
        powertop \
        nvme-cli \
        smartmontools \
        irqbalance \
        amd64-microcode \
        firmware-misc-nonfree \
        iw \
        ethtool \
        lm-sensors \
        bc \
        curl \
        wget
    
    # Try to install optional packages
    sudo apt-get install -y tuned tuned-utils || warning "tuned not available"
    sudo apt-get install -y tlp tlp-rdw || warning "TLP not available, will use alternatives"
    sudo apt-get install -y stress-ng || warning "stress-ng not available"
    
    log "Essential tools installed"
}

optimize_cpu_performance() {
    log "Optimizing CPU performance..."
    
    # Set CPU governor to performance
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g performance || {
            warning "cpupower failed, using direct sysfs method"
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                if [ -f "$cpu" ]; then
                    echo performance | sudo tee "$cpu" > /dev/null 2>&1 || true
                fi
            done
        }
    fi
    
    # Enable CPU boost
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost > /dev/null
        log "CPU boost enabled"
    fi
    
    # Create basic CPU optimization sysctl settings
    sudo tee /etc/sysctl.d/99-cpu-performance.conf > /dev/null << 'EOF'
# CPU Performance Optimizations
kernel.sched_autogroup_enabled=1
kernel.sched_migration_cost_ns=50000
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-cpu-performance.conf
    
    log "CPU performance optimized"
}

optimize_memory_64gb() {
    log "Optimizing memory for 64GB RAM..."
    
    # Calculate memory values
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    # Create memory optimization settings
    sudo tee /etc/sysctl.d/99-memory-64gb.conf > /dev/null << EOF
# Memory optimizations for 64GB RAM
vm.swappiness=1
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=2
vm.dirty_ratio=5
vm.dirty_expire_centisecs=1500
vm.dirty_writeback_centisecs=250
vm.min_free_kbytes=$((TOTAL_MEM_KB * 5 / 1000))
vm.zone_reclaim_mode=0
vm.max_map_count=1048576
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-memory-64gb.conf
    
    log "Memory optimized for 64GB RAM"
}

optimize_nvme_ssd() {
    log "Optimizing NVMe SSD performance..."
    
    # Get NVMe device
    SSD_DEVICE=$(lsblk -d -o NAME,TYPE | grep -E "nvme[0-9]n[0-9]" | head -1 | awk '{print $1}')
    
    if [ -n "$SSD_DEVICE" ]; then
        # Set I/O scheduler to none for NVMe
        echo "none" | sudo tee /sys/block/$SSD_DEVICE/queue/scheduler > /dev/null
        
        # Optimize queue settings
        echo "2048" | sudo tee /sys/block/$SSD_DEVICE/queue/nr_requests > /dev/null
        echo "512" | sudo tee /sys/block/$SSD_DEVICE/queue/read_ahead_kb > /dev/null
        
        # Make persistent
        sudo tee /etc/udev/rules.d/60-nvme-optimization.rules > /dev/null << 'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="512"
EOF
        
        log "NVMe SSD optimized: $SSD_DEVICE"
    fi
    
    # Enable TRIM
    sudo systemctl enable fstrim.timer || warning "Could not enable fstrim timer"
}

optimize_wifi7() {
    log "Optimizing WiFi 7 performance..."
    
    # Create WiFi optimization settings
    sudo tee /etc/sysctl.d/99-wifi7-network.conf > /dev/null << 'EOF'
# WiFi 7 network optimizations
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.netdev_max_backlog=10000
net.ipv4.tcp_rmem=8192 262144 134217728
net.ipv4.tcp_wmem=8192 262144 134217728
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-wifi7-network.conf
    
    # Optimize WiFi interface if available
    WIFI_INTERFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
    if [ -n "$WIFI_INTERFACE" ]; then
        sudo iw dev $WIFI_INTERFACE set power_save off 2>/dev/null || true
        sudo iw reg set US 2>/dev/null || true
        log "WiFi interface optimized: $WIFI_INTERFACE"
    fi
    
    log "WiFi 7 network stack optimized"
}

create_monitoring_tools() {
    log "Creating monitoring tools..."
    
    mkdir -p "$HOME/bin"
    
    # Create system status script
    cat > "$HOME/bin/system-status" << 'EOF'
#!/bin/bash
echo "=== AMD Ryzen AI 9 HX 370 System Status ==="
echo ""

# CPU info
echo "CPU Frequency (first 8 cores):"
grep "cpu MHz" /proc/cpuinfo | head -8 | awk '{printf "Core %d: %.0f MHz\n", NR-1, $4}'
echo ""

# CPU governor
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'Unknown')"

# CPU boost
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)
    echo "CPU Boost: $([ $BOOST -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
fi
echo ""

# Memory
echo "Memory Usage:"
free -h | grep -E "Mem:|Swap:"
echo ""

# Temperature
if command -v sensors &> /dev/null; then
    echo "Temperature:"
    sensors 2>/dev/null | grep -E "(Tctl|Tccd|temp)" | head -3 || echo "Temperature sensors not available"
    echo ""
fi

# WiFi
WIFI_INTERFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
if [ -n "$WIFI_INTERFACE" ]; then
    echo "WiFi Status:"
    echo "Interface: $WIFI_INTERFACE"
    iw dev $WIFI_INTERFACE link 2>/dev/null | grep -E "(Connected|SSID|signal|tx bitrate)" || echo "Not connected"
fi
EOF
    
    chmod +x "$HOME/bin/system-status"
    
    # Add aliases
    if ! grep -q "# AMD System Aliases" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << 'EOF'

# AMD System Aliases
alias sys-status='system-status'
alias cpu-freq='grep "cpu MHz" /proc/cpuinfo | head -8'
alias mem-usage='free -h'
alias temp-check='sensors 2>/dev/null | grep -E "(Tctl|Tccd)" || echo "Temperature not available"'
EOF
    fi
    
    log "Monitoring tools created"
}

apply_optimizations() {
    log "Applying immediate optimizations..."
    
    # Drop caches
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    
    # Initialize sensors
    sudo sensors-detect --auto 2>/dev/null || true
    
    log "Immediate optimizations applied"
}

main() {
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   AMD Ryzen AI 9 HX 370 + WiFi 7${NC}"
    echo -e "${GREEN}      Simplified Setup Script${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    
    check_root
    
    log "Starting simplified optimization setup..."
    
    install_essential_tools
    optimize_cpu_performance
    optimize_memory_64gb
    optimize_nvme_ssd
    optimize_wifi7
    create_monitoring_tools
    apply_optimizations
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}         Setup Complete!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${BLUE}Optimizations Applied:${NC}"
    echo "✅ CPU performance optimized for AMD Ryzen AI 9 HX 370"
    echo "✅ Memory management optimized for 64GB RAM"
    echo "✅ NVMe SSD performance enhanced"
    echo "✅ WiFi 7 network stack optimized"
    echo "✅ Monitoring tools installed"
    echo ""
    echo -e "${BLUE}Quick Commands:${NC}"
    echo "• sys-status    - Complete system status"
    echo "• cpu-freq      - CPU frequencies"
    echo "• mem-usage     - Memory usage"
    echo "• temp-check    - CPU temperature"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Run 'source ~/.bashrc' to load new aliases"
    echo "2. Test with 'sys-status'"
    echo "3. Reboot to ensure all optimizations are active"
    echo ""
    echo -e "${GREEN}Your AMD Ryzen AI 9 HX 370 system is now optimized!${NC}"
}

main "$@"
