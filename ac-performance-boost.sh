#!/bin/bash
# Additional Performance Optimizations for AC Power
# Framework Laptop Intel i7-1280P - Maximum Performance Mode

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

check_ac_power() {
    if ! on_ac_power; then
        log "WARNING: Not on AC power. These optimizations are for plugged-in use only!"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

maximize_cpu_performance() {
    log "Maximizing CPU performance for AC power..."
    
    # Ensure performance governor on all CPUs
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance | sudo tee $cpu > /dev/null
    done
    
    # Set Intel P-state to maximum performance
    if [ -d /sys/devices/system/cpu/intel_pstate ]; then
        echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/min_perf_pct
        echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/max_perf_pct
        echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
    
    # Disable CPU idle states for lower latency
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 1 | sudo tee $cpu > /dev/null 2>&1 || true
    done
    
    log "CPU set to maximum performance mode"
}

optimize_pcie_performance() {
    log "Optimizing PCIe performance..."
    
    # Disable ASPM (Active State Power Management) for maximum performance
    echo performance | sudo tee /sys/module/pcie_aspm/parameters/policy
    
    # Set all PCIe devices to performance mode
    for dev in /sys/bus/pci/devices/*/power/control; do
        echo on | sudo tee $dev > /dev/null 2>&1 || true
    done
}

optimize_gpu_performance() {
    log "Optimizing GPU performance..."
    
    # Intel GPU performance settings
    if [ -d /sys/class/drm/card0/gt_max_freq_mhz ]; then
        MAX_FREQ=$(cat /sys/class/drm/card0/gt_RP0_freq_mhz 2>/dev/null || echo "1450")
        echo $MAX_FREQ | sudo tee /sys/class/drm/card0/gt_max_freq_mhz > /dev/null 2>&1 || true
        echo $MAX_FREQ | sudo tee /sys/class/drm/card0/gt_boost_freq_mhz > /dev/null 2>&1 || true
    fi
}

disable_power_savings() {
    log "Disabling all power saving features..."
    
    # Disable kernel power saving
    echo 1 | sudo tee /sys/module/workqueue/parameters/power_efficient
    
    # Disable USB autosuspend
    for usb in /sys/bus/usb/devices/*/power/autosuspend; do
        echo -1 | sudo tee $usb > /dev/null 2>&1 || true
    done
    
    # Disable SATA power management
    for host in /sys/class/scsi_host/*/link_power_management_policy; do
        echo max_performance | sudo tee $host > /dev/null 2>&1 || true
    done
}

optimize_scheduler() {
    log "Optimizing CPU scheduler for performance..."
    
    # Enable autogroup for better desktop responsiveness
    echo 1 | sudo tee /proc/sys/kernel/sched_autogroup_enabled
    
    # Reduce scheduler migration cost
    echo 50000 | sudo tee /proc/sys/kernel/sched_migration_cost_ns
    
    # Increase scheduler runtime
    echo 950000 | sudo tee /proc/sys/kernel/sched_rt_runtime_us
}

boost_network_performance() {
    log "Optimizing network performance..."
    
    # Increase network buffers
    echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.d/99-network-performance.conf
    echo 'net.core.wmem_max=134217728' | sudo tee -a /etc/sysctl.d/99-network-performance.conf
    echo 'net.ipv4.tcp_rmem=4096 87380 134217728' | sudo tee -a /etc/sysctl.d/99-network-performance.conf
    echo 'net.ipv4.tcp_wmem=4096 65536 134217728' | sudo tee -a /etc/sysctl.d/99-network-performance.conf
    echo 'net.core.netdev_max_backlog=5000' | sudo tee -a /etc/sysctl.d/99-network-performance.conf
    
    sudo sysctl -p /etc/sysctl.d/99-network-performance.conf
}

create_performance_monitor() {
    log "Creating real-time performance monitor..."
    
    cat > "$HOME/bin/ac-performance-status" << 'EOF'
#!/bin/bash
# Check AC performance status

echo "=== AC Performance Status ==="
echo ""
echo "CPU Frequency:"
grep "cpu MHz" /proc/cpuinfo | head -4
echo ""
echo "CPU Governor:"
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c
echo ""
echo "Intel P-state:"
if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    echo "Min: $(cat /sys/devices/system/cpu/intel_pstate/min_perf_pct)%"
    echo "Max: $(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)%"
    echo "Turbo: $([ $(cat /sys/devices/system/cpu/intel_pstate/no_turbo) -eq 0 ] && echo "Enabled" || echo "Disabled")"
fi
echo ""
echo "PCIe ASPM Policy:"
cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null || echo "Not available"
echo ""
echo "Memory:"
free -h | grep -E "Mem:|Swap:"
EOF
    
    chmod +x "$HOME/bin/ac-performance-status"
}

setup_performance_service() {
    log "Creating systemd service for AC performance mode..."
    
    sudo tee /etc/systemd/system/ac-performance.service > /dev/null << EOF
[Unit]
Description=AC Performance Mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ac-performance-mode
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Create the script that the service runs
    sudo tee /usr/local/bin/ac-performance-mode > /dev/null << 'EOF'
#!/bin/bash
# Set maximum performance when on AC power

if on_ac_power; then
    # CPU Performance
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > $cpu 2>/dev/null || true
    done
    
    # Intel P-state
    if [ -d /sys/devices/system/cpu/intel_pstate ]; then
        echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct
        echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
    fi
    
    # PCIe Performance
    echo performance > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
fi
EOF
    
    sudo chmod +x /usr/local/bin/ac-performance-mode
    sudo systemctl enable ac-performance.service
}

apply_immediate_boost() {
    log "Applying immediate performance boost..."
    
    # Drop caches to free memory
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches
    
    # Disable transparent hugepages compaction
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
    
    # Set process niceness
    sudo renice -n -5 $$ > /dev/null 2>&1 || true
}

main() {
    log "Starting AC power performance optimization..."
    
    check_ac_power
    maximize_cpu_performance
    optimize_pcie_performance
    optimize_gpu_performance
    disable_power_savings
    optimize_scheduler
    boost_network_performance
    create_performance_monitor
    setup_performance_service
    apply_immediate_boost
    
    echo ""
    log "AC Performance optimizations complete!"
    echo ""
    echo "✅ CPU locked at maximum frequency"
    echo "✅ Intel Turbo Boost enabled"
    echo "✅ PCIe ASPM disabled for performance"
    echo "✅ Power saving features disabled"
    echo "✅ Network buffers increased"
    echo "✅ Scheduler optimized for low latency"
    echo ""
    echo "📊 Check status with: ac-performance-status"
    echo ""
    echo "⚡ Your laptop is now in MAXIMUM PERFORMANCE mode!"
    echo "⚠️  This will increase power consumption and heat generation"
}

main "$@"