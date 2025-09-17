#!/bin/bash
# Validation Script for AMD Ryzen AI 9 HX 370 + WiFi 7 Optimizations
# Tests system configuration without requiring sudo

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
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_cpu() {
    log "Validating CPU configuration..."
    
    # Check CPU model
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    if [[ "$CPU_MODEL" == *"AMD Ryzen AI 9 HX 370"* ]]; then
        echo "✅ CPU: $CPU_MODEL"
    else
        warning "Expected AMD Ryzen AI 9 HX 370, found: $CPU_MODEL"
    fi
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ $CPU_CORES -eq 24 ]; then
        echo "✅ CPU Cores: $CPU_CORES"
    else
        warning "Expected 24 cores, found: $CPU_CORES"
    fi
    
    # Check CPU frequency scaling
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        echo "ℹ️  CPU Governor: $GOVERNOR"
    fi
    
    # Check boost status
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)
        if [ $BOOST -eq 1 ]; then
            echo "✅ CPU Boost: Enabled"
        else
            echo "⚠️  CPU Boost: Disabled"
        fi
    fi
}

check_memory() {
    log "Validating memory configuration..."
    
    # Check total memory
    TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ $TOTAL_MEM_GB -ge 60 ]; then
        echo "✅ Total Memory: ${TOTAL_MEM_GB}GB"
    else
        warning "Expected 64GB, found: ${TOTAL_MEM_GB}GB"
    fi
    
    # Check swappiness
    if [ -f /proc/sys/vm/swappiness ]; then
        SWAPPINESS=$(cat /proc/sys/vm/swappiness)
        echo "ℹ️  Swappiness: $SWAPPINESS"
    fi
    
    # Check dirty ratio
    if [ -f /proc/sys/vm/dirty_ratio ]; then
        DIRTY_RATIO=$(cat /proc/sys/vm/dirty_ratio)
        echo "ℹ️  Dirty Ratio: $DIRTY_RATIO%"
    fi
    
    # Check for ZRAM
    if [ -f /proc/swaps ]; then
        if grep -q zram /proc/swaps; then
            echo "✅ ZRAM: Active"
            grep zram /proc/swaps
        else
            echo "⚠️  ZRAM: Not active"
        fi
    fi
}

check_storage() {
    log "Validating storage configuration..."
    
    # Check NVMe device
    if lsblk | grep -q nvme; then
        NVME_MODEL=$(lsblk -d -o NAME,MODEL | grep nvme | awk '{print $2, $3, $4}')
        if [[ "$NVME_MODEL" == *"PNY CS3140"* ]]; then
            echo "✅ NVMe SSD: $NVME_MODEL"
        else
            echo "ℹ️  NVMe SSD: $NVME_MODEL"
        fi
        
        # Check I/O scheduler
        NVME_DEVICE=$(lsblk -d -o NAME | grep nvme | head -1)
        if [ -f "/sys/block/$NVME_DEVICE/queue/scheduler" ]; then
            SCHEDULER=$(cat /sys/block/$NVME_DEVICE/queue/scheduler | grep -o '\[.*\]' | tr -d '[]')
            echo "ℹ️  I/O Scheduler: $SCHEDULER"
        fi
    else
        warning "No NVMe device found"
    fi
    
    # Check filesystem mounts
    echo "ℹ️  Filesystem mounts:"
    df -h | grep -E "(nvme|tmpfs)" | head -5
}

check_network() {
    log "Validating network configuration..."
    
    # Check WiFi device
    if lspci | grep -q "MT7925"; then
        WIFI_MODEL=$(lspci | grep "MT7925" | cut -d: -f3 | xargs)
        echo "✅ WiFi Device: $WIFI_MODEL"
    else
        warning "MediaTek MT7925 WiFi 7 device not found"
        echo "ℹ️  Available network devices:"
        lspci | grep -i network
    fi
    
    # Check WiFi interface
    WIFI_INTERFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
    if [ -n "$WIFI_INTERFACE" ]; then
        echo "✅ WiFi Interface: $WIFI_INTERFACE"
        
        # Check power save status
        POWER_SAVE=$(iw dev $WIFI_INTERFACE get power_save 2>/dev/null || echo "unknown")
        echo "ℹ️  Power Save: $POWER_SAVE"
    else
        echo "⚠️  No WiFi interface found"
    fi
    
    # Check network optimization settings
    if [ -f /proc/sys/net/core/rmem_max ]; then
        RMEM_MAX=$(cat /proc/sys/net/core/rmem_max)
        echo "ℹ️  Network RX Buffer: $RMEM_MAX bytes"
    fi
}

check_scripts() {
    log "Validating optimization scripts..."
    
    SCRIPTS=(
        "system-performance-setup.sh"
        "wifi7-optimization.sh"
        "memory-optimization-64gb.sh"
        "ac-performance-boost.sh"
        "setup-amd-wifi7-optimization.sh"
    )
    
    for script in "${SCRIPTS[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                echo "✅ Script: $script (executable)"
            else
                echo "⚠️  Script: $script (not executable)"
            fi
        else
            echo "❌ Script: $script (missing)"
        fi
    done
}

check_performance_tools() {
    log "Checking performance monitoring tools..."
    
    TOOLS=(
        "htop"
        "iotop"
        "nvme"
        "sensors"
        "cpupower"
        "iw"
        "ethtool"
    )
    
    for tool in "${TOOLS[@]}"; do
        if command -v $tool &> /dev/null; then
            echo "✅ Tool: $tool"
        else
            echo "⚠️  Tool: $tool (not installed)"
        fi
    done
}

run_basic_tests() {
    log "Running basic performance tests..."
    
    # CPU test
    echo "ℹ️  CPU frequency range:"
    if [ -f /proc/cpuinfo ]; then
        grep "cpu MHz" /proc/cpuinfo | head -4 | awk '{printf "  Core: %.0f MHz\n", $4}'
    fi
    
    # Memory test
    echo "ℹ️  Memory usage:"
    free -h | grep -E "Mem:|Swap:" | awk '{printf "  %s: %s used / %s total\n", $1, $3, $2}'
    
    # Disk test (read-only)
    echo "ℹ️  Disk usage:"
    df -h | grep -E "(nvme|/$)" | awk '{printf "  %s: %s used / %s total (%s)\n", $1, $3, $2, $5}'
    
    # Network interfaces
    echo "ℹ️  Network interfaces:"
    ip link show | grep -E "^[0-9]" | awk '{printf "  %s: %s\n", $2, $9}' | sed 's/:$//'
}

generate_report() {
    log "Generating optimization report..."
    
    REPORT_FILE="$HOME/optimization-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "AMD Ryzen AI 9 HX 370 + WiFi 7 Optimization Report"
        echo "Generated: $(date)"
        echo "=============================================="
        echo ""
        
        echo "System Information:"
        echo "- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
        echo "- Kernel: $(uname -r)"
        echo "- CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
        echo "- Memory: $(free -h | grep Mem | awk '{print $2}')"
        echo "- Storage: $(lsblk -d -o NAME,SIZE,MODEL | grep nvme | awk '{print $2, $3, $4}')"
        echo ""
        
        echo "Optimization Status:"
        echo "- Scripts present: $(ls -1 *.sh | wc -l)"
        echo "- CPU cores: $(nproc)"
        echo "- WiFi device: $(lspci | grep -i network | head -1 | cut -d: -f3 | xargs)"
        echo ""
        
        echo "Performance Settings:"
        echo "- Swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null || echo 'unknown')"
        echo "- CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"
        echo "- I/O Scheduler: $(cat /sys/block/nvme*/queue/scheduler 2>/dev/null | head -1 | grep -o '\[.*\]' | tr -d '[]' || echo 'unknown')"
        
    } > "$REPORT_FILE"
    
    echo "📄 Report saved to: $REPORT_FILE"
}

main() {
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   AMD Ryzen AI 9 HX 370 + WiFi 7${NC}"
    echo -e "${GREEN}        Optimization Validator${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    
    check_cpu
    echo ""
    check_memory
    echo ""
    check_storage
    echo ""
    check_network
    echo ""
    check_scripts
    echo ""
    check_performance_tools
    echo ""
    run_basic_tests
    echo ""
    generate_report
    
    echo ""
    echo -e "${GREEN}Validation complete!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Run './setup-amd-wifi7-optimization.sh' with sudo to apply optimizations"
    echo "2. Reboot to activate all kernel optimizations"
    echo "3. Run this validator again to verify applied settings"
    echo ""
}

main "$@"
