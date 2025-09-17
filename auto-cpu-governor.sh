#!/bin/bash

# Auto CPU Governor Switcher for AMD Ryzen AI 9 HX 370
# Switches between performance (AC) and powersave (battery) governors
# Based on AC adapter status

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get AC adapter status
get_ac_status() {
    local ac_online
    ac_online=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1 || echo "0")
    echo "$ac_online"
}

# Get current CPU governor
get_current_governor() {
    cpupower frequency-info | grep "The governor" | awk '{print $2}' | tr -d '"'
}

# Set CPU governor for all cores
set_cpu_governor() {
    local governor="$1"
    log "Setting CPU governor to: $governor"
    
    if cpupower frequency-set -g "$governor" >/dev/null 2>&1; then
        log "Successfully set CPU governor to $governor"
        return 0
    else
        error "Failed to set CPU governor to $governor"
        return 1
    fi
}

# Set CPU performance preferences for AMD P-State EPP
set_amd_epp_preference() {
    local preference="$1"
    log "Setting AMD EPP preference to: $preference"
    
    # Set EPP preference for all CPUs
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        if [[ -w "$cpu" ]]; then
            echo "$preference" > "$cpu" 2>/dev/null || true
        fi
    done
}

# Apply performance settings when on AC power
apply_ac_settings() {
    log "AC adapter detected - applying performance settings"
    set_cpu_governor "performance"
    set_amd_epp_preference "performance"
    
    # Optional: Set CPU frequency scaling
    log "Setting CPU frequency scaling for maximum performance"
    echo "4370000" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq 2>/dev/null || true
}

# Apply battery settings when on battery power
apply_battery_settings() {
    log "Battery power detected - applying power-saving settings"
    set_cpu_governor "powersave"
    set_amd_epp_preference "power"
    
    # Optional: Limit max frequency for battery life
    log "Setting CPU frequency scaling for battery efficiency"
    echo "3000000" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq 2>/dev/null || true
}

# Show current status
show_status() {
    local ac_status current_governor
    ac_status=$(get_ac_status)
    current_governor=$(get_current_governor)
    
    echo -e "\n${BLUE}=== Current System Status ===${NC}"
    echo "AC Adapter: $([ "$ac_status" = "1" ] && echo "Connected" || echo "Disconnected")"
    echo "CPU Governor: $current_governor"
    echo "CPU Frequency Range: $(cpupower frequency-info | grep "hardware limits" | cut -d: -f2)"
    echo "Current CPU Frequency: $(cpupower frequency-info | grep "current CPU frequency" | tail -1 | cut -d: -f2)"
    
    # Show EPP preference if available
    local epp_pref
    epp_pref=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "N/A")
    echo "Energy Performance Preference: $epp_pref"
}

# Main function
main() {
    local ac_status current_governor
    
    case "${1:-auto}" in
        "status")
            show_status
            exit 0
            ;;
        "performance")
            check_root
            log "Manually setting performance mode"
            apply_ac_settings
            show_status
            exit 0
            ;;
        "powersave")
            check_root
            log "Manually setting power-save mode"
            apply_battery_settings
            show_status
            exit 0
            ;;
        "auto")
            check_root
            ac_status=$(get_ac_status)
            current_governor=$(get_current_governor)
            
            log "Auto-detecting power source..."
            
            if [[ "$ac_status" = "1" ]]; then
                # On AC power
                if [[ "$current_governor" != "performance" ]]; then
                    apply_ac_settings
                else
                    log "Already optimized for AC power (performance mode)"
                fi
            else
                # On battery power
                if [[ "$current_governor" != "powersave" ]]; then
                    apply_battery_settings
                else
                    log "Already optimized for battery power (powersave mode)"
                fi
            fi
            
            show_status
            ;;
        "install-service")
            check_root
            install_systemd_service
            ;;
        *)
            echo "Usage: $0 [auto|performance|powersave|status|install-service]"
            echo ""
            echo "  auto           - Automatically set governor based on AC status (default)"
            echo "  performance    - Force performance mode"
            echo "  powersave      - Force power-save mode"
            echo "  status         - Show current status"
            echo "  install-service - Install systemd service for automatic switching"
            exit 1
            ;;
    esac
}

# Install systemd service for automatic switching
install_systemd_service() {
    log "Installing systemd service for automatic CPU governor switching..."
    
    # Create the service file
    cat > /etc/systemd/system/auto-cpu-governor.service << 'EOF'
[Unit]
Description=Auto CPU Governor Switcher
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/home/jef/git/linux-setup/auto-cpu-governor.sh auto
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create udev rule for AC adapter events
    cat > /etc/udev/rules.d/99-auto-cpu-governor.rules << 'EOF'
# Auto CPU Governor Switcher - AC Adapter Events
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/home/jef/git/linux-setup/auto-cpu-governor.sh auto"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/home/jef/git/linux-setup/auto-cpu-governor.sh auto"
EOF

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable auto-cpu-governor.service
    systemctl start auto-cpu-governor.service
    
    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger
    
    log "Systemd service installed and enabled!"
    log "The CPU governor will now automatically switch based on AC adapter status"
    log "You can check status with: systemctl status auto-cpu-governor.service"
}

# Run main function
main "$@"
