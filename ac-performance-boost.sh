#!/bin/bash
# Additional Performance Optimizations for AC Power
# Modern Laptop AMD Ryzen AI 9 HX 370 - Maximum Performance Mode
#
# NOTE ABOUT SUSPEND/RESUME (s2idle):
# Some of the "maximum performance" tweaks (disabling CPU idle, forcing PCIe runtime PM "on",
# disabling USB autosuspend, forcing PCIe ASPM policy) can make s2idle less reliable on some
# AMD laptops and can also significantly increase power draw.
#
# To reduce risk, this script defaults to a *suspend-safe* mode and requires --aggressive to
# apply the highest-risk knobs.

set -euo pipefail

AGGRESSIVE=0
INSTALL_SERVICE=0
DROP_CACHES=0
ASSUME_YES=0
SKIP_AC_CHECK=0

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

usage() {
    cat << 'EOF'
Usage: ./ac-performance-boost.sh [options]

Options:
  --aggressive       Apply highest-risk knobs (can hurt suspend/resume on some systems):
                    - disable CPU idle states
                    - force PCIe ASPM policy=performance
                    - force all PCI devices runtime PM control=on
                    - disable USB autosuspend
  --install-service  Install/enable a systemd oneshot service (persistent)
  --drop-caches      Drop page cache (usually unnecessary; can cause stalls)
  -y, --yes          Don't prompt
  --no-ac-check      Don't check AC power
  -h, --help         Show help
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --aggressive)
                AGGRESSIVE=1
                ;;
            --install-service)
                INSTALL_SERVICE=1
                ;;
            --drop-caches)
                DROP_CACHES=1
                ;;
            -y|--yes)
                ASSUME_YES=1
                ;;
            --no-ac-check)
                SKIP_AC_CHECK=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR: Unknown argument: $1"
                usage
                exit 2
                ;;
        esac
        shift
    done
}

get_ac_online() {
    # Prefer on_ac_power (powermgmt-base) when available; otherwise fall back to sysfs.
    if command -v on_ac_power >/dev/null 2>&1; then
        if on_ac_power; then
            echo 1
        else
            echo 0
        fi
        return 0
    fi

    local online
    online=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1 || true)
    if [ -z "${online:-}" ]; then
        # Unknown: be conservative and say "online".
        echo 1
    else
        echo "$online"
    fi
}

check_ac_power() {
    if [ "$SKIP_AC_CHECK" -eq 1 ]; then
        return 0
    fi

    if [ "$(get_ac_online)" != "1" ]; then
        log "WARNING: Not on AC power. These optimizations are for plugged-in use only!"
        if [ "$ASSUME_YES" -eq 0 ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

maximize_cpu_performance() {
    log "Maximizing CPU performance for AC power..."
    
    # Ensure performance governor on all CPUs
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance | sudo tee $cpu > /dev/null
    done
    
    # AMD P-State: prefer EPP (energy_performance_preference) instead of writing amd_pstate/status.
    # (amd_pstate/status typically expects: active/passive/guided/disable)
    for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        if [ -f "$epp" ]; then
            echo performance | sudo tee "$epp" > /dev/null 2>&1 || true
        fi
    done

    # Enable AMD boost
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost
    fi
    
    # Highest-risk / suspend-unfriendly knob: disabling CPU idle states.
    if [ "$AGGRESSIVE" -eq 1 ]; then
        log "AGGRESSIVE: Disabling CPU idle states (may hurt suspend/resume)"
        for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
            echo 1 | sudo tee "$cpu" > /dev/null 2>&1 || true
        done
    else
        log "Suspend-safe: Leaving CPU idle states enabled"
    fi
    
    log "CPU set to maximum performance mode"
}

optimize_pcie_performance() {
    log "Optimizing PCIe performance..."

    if [ "$AGGRESSIVE" -eq 1 ]; then
        # Disable ASPM (Active State Power Management) for maximum performance
        log "AGGRESSIVE: Setting PCIe ASPM policy=performance"
        echo performance | sudo tee /sys/module/pcie_aspm/parameters/policy > /dev/null

        # Force runtime PM "on" for all PCI devices (can increase power draw and can hurt s2idle).
        log "AGGRESSIVE: Forcing PCI runtime PM control=on for all PCI devices"
        for dev in /sys/bus/pci/devices/*/power/control; do
            echo on | sudo tee "$dev" > /dev/null 2>&1 || true
        done
    else
        log "Suspend-safe: Not changing PCIe ASPM policy or PCI runtime PM"
    fi
}

optimize_gpu_performance() {
    log "Optimizing GPU performance..."

    # AMD GPU performance settings (Radeon 890M)
    if [ -d /sys/class/drm/card0/device ]; then
        # Set performance mode for AMD GPU
        echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level > /dev/null 2>&1 || true
        echo performance | sudo tee /sys/class/drm/card0/device/power_dpm_state > /dev/null 2>&1 || true
    fi
}

disable_power_savings() {
    if [ "$AGGRESSIVE" -eq 1 ]; then
        log "AGGRESSIVE: Disabling power saving features..."

        # Prefer performance workqueues (power_efficient=0)
        echo 0 | sudo tee /sys/module/workqueue/parameters/power_efficient > /dev/null 2>&1 || true

        # Disable USB autosuspend
        for usb in /sys/bus/usb/devices/*/power/autosuspend; do
            echo -1 | sudo tee "$usb" > /dev/null 2>&1 || true
        done

        # Disable SATA power management
        for host in /sys/class/scsi_host/*/link_power_management_policy; do
            echo max_performance | sudo tee "$host" > /dev/null 2>&1 || true
        done
    else
        log "Suspend-safe: Not disabling USB autosuspend / PCI runtime PM / SATA link PM"
    fi
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

    # Increase network buffers (idempotent: overwrite file rather than append duplicates)
    sudo tee /etc/sysctl.d/99-network-performance.conf > /dev/null << 'EOF'
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=5000
EOF

    sudo sysctl -p /etc/sysctl.d/99-network-performance.conf > /dev/null
}

create_performance_monitor() {
    log "Creating real-time performance monitor..."

    mkdir -p "$HOME/bin"
    
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
echo "AMD CPU State:"
if [ -d /sys/devices/system/cpu/amd_pstate ]; then
    echo "Status: $(cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null || echo "Not available")"
fi
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    echo "Boost: $([ $(cat /sys/devices/system/cpu/cpufreq/boost) -eq 1 ] && echo "Enabled" || echo "Disabled")"
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
    if [ "$INSTALL_SERVICE" -ne 1 ]; then
        log "Not installing systemd service (use --install-service to enable)"
        return 0
    fi

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
    
    # AMD CPU performance
    if [ -d /sys/devices/system/cpu/amd_pstate ]; then
        echo performance > /sys/devices/system/cpu/amd_pstate/status 2>/dev/null || true
    fi
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    fi
    
    # PCIe Performance
    echo performance > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
fi
EOF
    
    sudo chmod +x /usr/local/bin/ac-performance-mode
    sudo systemctl daemon-reload
    sudo systemctl enable ac-performance.service
}

apply_immediate_boost() {
    log "Applying immediate performance boost..."

    if [ "$DROP_CACHES" -eq 1 ]; then
        # Drop caches to free memory
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    else
        log "Skipping drop_caches (use --drop-caches to enable)"
    fi
    
    # Disable transparent hugepages compaction
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
    
    # Set process niceness
    sudo renice -n -5 $$ > /dev/null 2>&1 || true
}

main() {
    log "Starting AC power performance optimization..."

    parse_args "$@"

    log "Mode: $([ "$AGGRESSIVE" -eq 1 ] && echo "AGGRESSIVE" || echo "SUSPEND-SAFE")"
    log "Install service: $([ "$INSTALL_SERVICE" -eq 1 ] && echo "yes" || echo "no")"

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
    echo "✅ CPU set to performance governor and EPP=performance"
    echo "✅ AMD Boost enabled"
    if [ "$AGGRESSIVE" -eq 1 ]; then
        echo "✅ PCIe ASPM policy=performance"
        echo "✅ Power saving features disabled (AGGRESSIVE)"
    else
        echo "✅ Suspend-safe mode: avoided high-risk power tweaks"
    fi
    echo "✅ Network buffers increased"
    echo "✅ Scheduler optimized for low latency"
    echo ""
    echo "📊 Check status with: ac-performance-status"
    echo ""
    echo "⚡ Your laptop is now in performance mode!"
    echo "⚠️  Aggressive mode increases power consumption/heat and may hurt suspend/resume"
}

main "$@"