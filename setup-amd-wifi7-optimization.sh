#!/bin/bash
# Complete System Optimization for AMD Ryzen AI 9 HX 370 + WiFi 7
# Debian 13 | 64GB RAM | PNY CS3140 2TB NVMe | MediaTek MT7925 WiFi 7
# Comprehensive performance optimization suite

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
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

check_system() {
    log "Checking system compatibility..."
    
    # Check Debian version
    if ! grep -q "13" /etc/debian_version; then
        warning "This script is optimized for Debian 13. Current version: $(cat /etc/debian_version)"
    fi
    
    # Check CPU
    if ! grep -q "AMD Ryzen AI 9 HX 370" /proc/cpuinfo; then
        warning "This script is optimized for AMD Ryzen AI 9 HX 370"
    fi
    
    # Check WiFi
    if ! lspci | grep -q "MT7925"; then
        warning "MediaTek MT7925 WiFi 7 device not detected"
    fi
    
    # Check memory
    TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ $TOTAL_MEM_GB -lt 32 ]; then
        warning "This script is optimized for 32GB+ RAM. Detected: ${TOTAL_MEM_GB}GB"
    fi
    
    log "System check complete"
}

run_system_optimization() {
    log "Running system performance optimization..."
    
    if [ -f "./system-performance-setup.sh" ]; then
        chmod +x ./system-performance-setup.sh
        ./system-performance-setup.sh
    else
        error "system-performance-setup.sh not found"
    fi
}

run_wifi7_optimization() {
    log "Running WiFi 7 optimization..."
    
    if [ -f "./wifi7-optimization.sh" ]; then
        chmod +x ./wifi7-optimization.sh
        ./wifi7-optimization.sh
    else
        error "wifi7-optimization.sh not found"
    fi
}

run_memory_optimization() {
    log "Running 64GB memory optimization..."
    
    if [ -f "./memory-optimization-64gb.sh" ]; then
        chmod +x ./memory-optimization-64gb.sh
        ./memory-optimization-64gb.sh
    else
        error "memory-optimization-64gb.sh not found"
    fi
}

run_ac_performance_boost() {
    log "Running AC performance boost..."
    
    if [ -f "./ac-performance-boost.sh" ]; then
        chmod +x ./ac-performance-boost.sh
        ./ac-performance-boost.sh
    else
        warning "ac-performance-boost.sh not found, skipping"
    fi
}

install_additional_tools() {
    log "Installing additional performance tools..."
    
    # Install AMD-specific tools
    sudo apt-get update
    sudo apt-get install -y \
        ryzen-stabilizr \
        zenstates \
        msr-tools \
        cpuid \
        lm-sensors \
        stress-ng \
        sysbench \
        iperf3 \
        speedtest-cli \
        neofetch
    
    # Install development tools optimized for high-memory systems
    sudo apt-get install -y \
        build-essential \
        cmake \
        ninja-build \
        ccache \
        distcc \
        clang \
        llvm \
        rust-all \
        golang-go \
        nodejs \
        npm
    
    log "Additional tools installed"
}

configure_development_environment() {
    log "Configuring development environment..."
    
    # Create development directories
    mkdir -p "$HOME/bin"
    mkdir -p "$HOME/.config"
    
    # Configure ccache for faster C/C++ builds
    if command -v ccache &> /dev/null; then
        ccache --set-config=cache_dir=/tmp/build-cache-64gb/ccache
        ccache --set-config=max_size=4G
        ccache --set-config=compression=true
    fi
    
    # Configure Rust for faster builds
    if command -v cargo &> /dev/null; then
        mkdir -p "$HOME/.cargo"
        cat > "$HOME/.cargo/config.toml" << 'EOF'
[build]
target-dir = "/tmp/build-cache-64gb/cargo"

[net]
git-fetch-with-cli = true

[profile.dev]
debug = 1

[profile.release]
lto = "thin"
codegen-units = 1
EOF
    fi
    
    # Configure npm for faster builds
    if command -v npm &> /dev/null; then
        npm config set cache /tmp/build-cache-64gb/npm
        npm config set prefer-offline true
        npm config set progress false
    fi
    
    log "Development environment configured"
}

create_performance_aliases() {
    log "Creating performance monitoring aliases..."
    
    cat >> "$HOME/.bashrc" << 'EOF'

# AMD Ryzen AI 9 HX 370 + WiFi 7 Performance Aliases
alias cpu-temp='sensors | grep -E "(Tctl|Tccd)"'
alias cpu-freq='grep "cpu MHz" /proc/cpuinfo | head -12'
alias cpu-gov='cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c'
alias wifi-status='wifi7-status'
alias mem-status='memory-monitor-64gb'
alias nvme-temp='sudo nvme smart-log /dev/nvme0 | grep temperature'
alias nvme-health='sudo nvme smart-log /dev/nvme0'
alias perf-overview='echo "=== System Performance Overview ==="; cpu-temp; echo ""; cpu-freq | head -4; echo ""; mem-status | head -10; echo ""; wifi-status | head -10'

# Development shortcuts
alias dev-ram='cd /tmp/dev-workspace-64gb'
alias build-cache='cd /tmp/build-cache-64gb'
alias clear-build-cache='rm -rf /tmp/build-cache-64gb/* && echo "Build cache cleared"'

# Performance testing
alias cpu-stress='stress-ng --cpu $(nproc) --timeout 60s --metrics-brief'
alias mem-stress='stress-ng --vm 4 --vm-bytes 8G --timeout 60s --metrics-brief'
alias disk-speed='sudo hdparm -tT /dev/nvme0n1'
alias network-speed='speedtest-cli'
EOF

    log "Performance aliases created"
}

setup_monitoring_cron() {
    log "Setting up performance monitoring..."
    
    # Create performance monitoring script
    cat > "$HOME/bin/system-health-check" << 'EOF'
#!/bin/bash
# System health monitoring for AMD Ryzen AI 9 HX 370

LOG_FILE="$HOME/.system-health.log"
DATE=$(date +'%Y-%m-%d %H:%M:%S')

# Check CPU temperature
CPU_TEMP=$(sensors | grep -E "Tctl" | awk '{print $2}' | sed 's/+//g' | sed 's/°C//g' | head -1)
if [ -n "$CPU_TEMP" ] && [ $(echo "$CPU_TEMP > 85" | bc -l) -eq 1 ]; then
    echo "$DATE: WARNING - High CPU temperature: ${CPU_TEMP}°C" >> $LOG_FILE
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEM_USAGE -gt 90 ]; then
    echo "$DATE: WARNING - High memory usage: ${MEM_USAGE}%" >> $LOG_FILE
fi

# Check NVMe temperature
NVME_TEMP=$(sudo nvme smart-log /dev/nvme0 2>/dev/null | grep temperature | awk '{print $3}' | head -1)
if [ -n "$NVME_TEMP" ] && [ $NVME_TEMP -gt 70 ]; then
    echo "$DATE: WARNING - High NVMe temperature: ${NVME_TEMP}°C" >> $LOG_FILE
fi

# Log normal status every hour
if [ $(date +%M) -eq 0 ]; then
    echo "$DATE: System OK - CPU: ${CPU_TEMP}°C, Memory: ${MEM_USAGE}%, NVMe: ${NVME_TEMP}°C" >> $LOG_FILE
fi
EOF

    chmod +x "$HOME/bin/system-health-check"
    
    # Add to crontab (every 5 minutes)
    (crontab -l 2>/dev/null || true; echo "*/5 * * * * $HOME/bin/system-health-check") | crontab -
}

print_summary() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   AMD Ryzen AI 9 HX 370 + WiFi 7 Setup${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${BLUE}System Specifications:${NC}"
    echo "• CPU: AMD Ryzen AI 9 HX 370 (24 cores)"
    echo "• RAM: 64GB optimized for high-performance"
    echo "• Storage: PNY CS3140 2TB NVMe SSD"
    echo "• WiFi: MediaTek MT7925 WiFi 7 160MHz"
    echo "• OS: Debian 13 (Trixie)"
    echo ""
    echo -e "${BLUE}Optimizations Applied:${NC}"
    echo "✅ AMD CPU performance optimized"
    echo "✅ WiFi 7 configured for maximum throughput"
    echo "✅ 64GB RAM management optimized"
    echo "✅ NVMe SSD performance enhanced"
    echo "✅ Development environment configured"
    echo "✅ Performance monitoring enabled"
    echo ""
    echo -e "${BLUE}Quick Commands:${NC}"
    echo "• perf-overview    - System performance overview"
    echo "• wifi-status      - WiFi 7 connection status"
    echo "• mem-status       - Memory usage details"
    echo "• cpu-temp         - CPU temperature"
    echo "• dev-ram          - Go to RAM workspace"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Reboot to apply all kernel optimizations"
    echo "2. Run 'perf-overview' to check system status"
    echo "3. Test WiFi 7 performance with 'network-speed'"
    echo "4. Monitor system health in ~/.system-health.log"
    echo ""
    echo -e "${GREEN}Setup complete! Reboot recommended.${NC}"
}

main() {
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   AMD Ryzen AI 9 HX 370 + WiFi 7 Setup${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    
    check_root
    check_system
    
    log "Starting comprehensive system optimization..."
    
    run_system_optimization
    run_wifi7_optimization
    run_memory_optimization
    run_ac_performance_boost
    install_additional_tools
    configure_development_environment
    create_performance_aliases
    setup_monitoring_cron
    
    print_summary
}

main "$@"
