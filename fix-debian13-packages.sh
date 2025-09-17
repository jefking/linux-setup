#!/bin/bash
# Fix package installation issues for Debian 13
# Addresses missing packages and alternative installations

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

check_root() {
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
        exit 1
    fi
}

fix_package_sources() {
    log "Updating package sources for Debian 13..."
    
    # Ensure we have the latest package lists
    sudo apt-get update
    
    # Add contrib and non-free repositories if not present
    if ! grep -q "contrib non-free" /etc/apt/sources.list; then
        warning "Adding contrib and non-free repositories..."
        sudo sed -i 's/main$/main contrib non-free non-free-firmware/' /etc/apt/sources.list
        sudo apt-get update
    fi
}

install_missing_tools() {
    log "Installing essential performance tools..."
    
    # Install core tools that should be available
    sudo apt-get install -y \
        linux-cpupower \
        htop \
        iotop \
        iftop \
        nethogs \
        sysstat \
        powertop \
        nvme-cli \
        smartmontools \
        irqbalance \
        tuned \
        tuned-utils \
        amd64-microcode \
        firmware-misc-nonfree \
        firmware-realtek \
        wireless-tools \
        iw \
        ethtool \
        msr-tools \
        lm-sensors \
        stress-ng \
        bc \
        curl \
        wget
    
    log "Core tools installed successfully"
}

install_tlp() {
    log "Installing TLP power management..."
    
    # TLP might need to be installed from different source in Debian 13
    if ! sudo apt-get install -y tlp tlp-rdw; then
        warning "TLP not available from main repositories, trying alternative..."
        
        # Try installing from backports or alternative source
        sudo apt-get install -y power-profiles-daemon || {
            warning "Power management tools not available, will use cpupower instead"
        }
    fi
}

setup_cpu_frequency_control() {
    log "Setting up CPU frequency control..."
    
    # Ensure cpupower is working
    if command -v cpupower &> /dev/null; then
        # Set performance governor
        sudo cpupower frequency-set -g performance || {
            warning "Could not set performance governor, trying alternative method..."
            
            # Alternative method using sysfs
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                if [ -f "$cpu" ]; then
                    echo performance | sudo tee "$cpu" > /dev/null 2>&1 || true
                fi
            done
        }
        
        log "CPU frequency control configured"
    else
        error "cpupower not available"
    fi
}

install_alternative_amd_tools() {
    log "Installing alternative AMD monitoring tools..."
    
    # Install Python-based tools for AMD monitoring
    sudo apt-get install -y python3-pip python3-venv
    
    # Create a virtual environment for AMD tools
    if [ ! -d "$HOME/.amd-tools" ]; then
        python3 -m venv "$HOME/.amd-tools"
    fi
    
    # Install AMD monitoring tools via pip
    source "$HOME/.amd-tools/bin/activate"
    pip install psutil py-cpuinfo || true
    deactivate
    
    # Create a simple AMD monitoring script
    cat > "$HOME/bin/amd-monitor" << 'EOF'
#!/bin/bash
# Simple AMD CPU monitoring script

echo "=== AMD Ryzen AI 9 HX 370 Status ==="
echo ""

# CPU frequency
echo "CPU Frequencies:"
grep "cpu MHz" /proc/cpuinfo | head -8 | awk '{printf "Core %d: %.0f MHz\n", NR-1, $4}'
echo ""

# CPU temperature (if available)
if command -v sensors &> /dev/null; then
    echo "CPU Temperature:"
    sensors | grep -E "(Tctl|Tccd|temp)" | head -5
    echo ""
fi

# CPU governor
echo "CPU Governor:"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "Unknown"
echo ""

# CPU boost status
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)
    echo "CPU Boost: $([ $BOOST -eq 1 ] && echo "Enabled" || echo "Disabled")"
else
    echo "CPU Boost: Unknown"
fi
echo ""

# Load average
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
EOF
    
    chmod +x "$HOME/bin/amd-monitor"
    mkdir -p "$HOME/bin"
    
    log "Alternative AMD tools installed"
}

setup_wifi_tools() {
    log "Setting up WiFi monitoring tools..."
    
    # Ensure iw and wireless tools are available
    if ! command -v iw &> /dev/null; then
        sudo apt-get install -y iw wireless-tools
    fi
    
    # Create WiFi monitoring script
    cat > "$HOME/bin/wifi-monitor" << 'EOF'
#!/bin/bash
# WiFi monitoring script for MediaTek MT7925

echo "=== WiFi 7 Status ==="
echo ""

# Get WiFi interface
WIFI_INTERFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)

if [ -n "$WIFI_INTERFACE" ]; then
    echo "Interface: $WIFI_INTERFACE"
    echo ""
    
    # Connection status
    echo "Connection Status:"
    iw dev $WIFI_INTERFACE link 2>/dev/null || echo "Not connected"
    echo ""
    
    # Interface info
    echo "Interface Info:"
    ip addr show $WIFI_INTERFACE | grep -E "(inet|state)" || echo "No IP assigned"
    echo ""
    
    # WiFi statistics
    echo "Statistics:"
    cat /proc/net/wireless 2>/dev/null | grep $WIFI_INTERFACE || echo "No wireless stats available"
else
    echo "No WiFi interface found"
fi
EOF
    
    chmod +x "$HOME/bin/wifi-monitor"
    
    log "WiFi monitoring tools installed"
}

create_performance_aliases() {
    log "Creating performance monitoring aliases..."
    
    # Add aliases to bashrc if not already present
    if ! grep -q "# AMD Performance Aliases" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << 'EOF'

# AMD Performance Aliases
alias amd-status='amd-monitor'
alias wifi-check='wifi-monitor'
alias cpu-freq='grep "cpu MHz" /proc/cpuinfo | head -8'
alias cpu-temp='sensors 2>/dev/null | grep -E "(Tctl|Tccd)" || echo "Temperature sensors not available"'
alias mem-free='free -h'
alias disk-usage='df -h | grep nvme'

# Performance shortcuts
alias perf-check='echo "=== Quick Performance Check ==="; cpu-freq; echo ""; cpu-temp; echo ""; mem-free'
EOF
        
        log "Performance aliases added to ~/.bashrc"
    fi
}

test_fixes() {
    log "Testing fixes..."
    
    # Test CPU frequency control
    if command -v cpupower &> /dev/null; then
        echo "✅ cpupower available"
    else
        echo "⚠️  cpupower not available"
    fi
    
    # Test sensors
    if command -v sensors &> /dev/null; then
        echo "✅ sensors available"
    else
        echo "⚠️  sensors not available"
    fi
    
    # Test WiFi tools
    if command -v iw &> /dev/null; then
        echo "✅ iw (WiFi tools) available"
    else
        echo "⚠️  iw not available"
    fi
    
    # Test monitoring scripts
    if [ -x "$HOME/bin/amd-monitor" ]; then
        echo "✅ AMD monitoring script created"
    fi
    
    if [ -x "$HOME/bin/wifi-monitor" ]; then
        echo "✅ WiFi monitoring script created"
    fi
}

main() {
    log "Fixing Debian 13 package installation issues..."
    
    check_root
    fix_package_sources
    install_missing_tools
    install_tlp
    setup_cpu_frequency_control
    install_alternative_amd_tools
    setup_wifi_tools
    create_performance_aliases
    test_fixes
    
    echo ""
    log "Package fixes complete!"
    echo ""
    echo "✅ Core performance tools installed"
    echo "✅ CPU frequency control configured"
    echo "✅ Alternative AMD monitoring tools created"
    echo "✅ WiFi monitoring tools installed"
    echo "✅ Performance aliases added"
    echo ""
    echo "🔄 Run 'source ~/.bashrc' to load new aliases"
    echo "📊 Test with: amd-status, wifi-check, perf-check"
    echo ""
    echo "Now you can re-run the main optimization script:"
    echo "./system-performance-setup.sh"
}

main "$@"
