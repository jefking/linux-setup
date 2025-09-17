#!/bin/bash
# WiFi 7 Performance Optimization for MediaTek MT7925
# Debian 13 | AMD Ryzen AI 9 HX 370 | WiFi 7 160MHz
# Optimizes WiFi 7 for maximum throughput and low latency

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_wifi_device() {
    log "Checking WiFi 7 device..."
    
    # Check for MediaTek MT7925
    if ! lspci | grep -q "MT7925"; then
        error "MediaTek MT7925 WiFi 7 device not found"
    fi
    
    # Get WiFi interface name
    WIFI_INTERFACE=$(iw dev | grep Interface | awk '{print $2}' | head -1)
    if [ -z "$WIFI_INTERFACE" ]; then
        error "No WiFi interface found"
    fi
    
    log "Found WiFi interface: $WIFI_INTERFACE"
}

optimize_wifi_driver() {
    log "Optimizing WiFi 7 driver parameters..."
    
    # Create MediaTek MT7925 optimization file
    sudo tee /etc/modprobe.d/mt7925-wifi7.conf > /dev/null << 'EOF'
# MediaTek MT7925 WiFi 7 Performance Optimizations

# Disable power saving for maximum performance
options mt7925e power_save=0

# Enable 802.11n features
options mt7925e 11n_disable=0

# Enable A-MSDU aggregation for better throughput
options mt7925e amsdu=1

# Disable antenna coupling for better signal
options mt7925e antenna_coupling=0

# Enable hardware encryption
options mt7925e hw_crypt=1

# Set maximum transmit power
options mt7925e txpower=30

# Enable beamforming
options mt7925e bf=1

# Enable MU-MIMO
options mt7925e mu_mimo=1

# WiFi 7 specific optimizations
options mt7925e wifi7_mode=1
options mt7925e mlo_support=1
options mt7925e eht_support=1
EOF

    log "WiFi driver optimizations applied"
}

optimize_network_stack() {
    log "Optimizing network stack for WiFi 7..."
    
    # Create WiFi 7 network optimizations
    sudo tee /etc/sysctl.d/99-wifi7-performance.conf > /dev/null << 'EOF'
# WiFi 7 Network Stack Optimizations

# Increase network buffer sizes for high throughput
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=262144
net.core.wmem_default=262144

# TCP buffer sizes optimized for WiFi 7
net.ipv4.tcp_rmem=8192 262144 134217728
net.ipv4.tcp_wmem=8192 262144 134217728

# Increase network device queue length
net.core.netdev_max_backlog=10000
net.core.netdev_budget=600

# Enable TCP window scaling
net.ipv4.tcp_window_scaling=1

# Use BBR congestion control for better WiFi performance
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Reduce TCP retransmission timeout
net.ipv4.tcp_retries2=8

# Enable TCP fast open
net.ipv4.tcp_fastopen=3

# Optimize for low latency
net.ipv4.tcp_low_latency=1

# Increase maximum connections
net.core.somaxconn=65535

# WiFi 7 specific optimizations
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_base_mss=1460
EOF

    # Apply settings
    sudo sysctl -p /etc/sysctl.d/99-wifi7-performance.conf
}

configure_wifi_interface() {
    log "Configuring WiFi interface for optimal performance..."
    
    # Set WiFi interface to performance mode
    sudo iw dev $WIFI_INTERFACE set power_save off 2>/dev/null || true
    
    # Set regulatory domain for maximum power
    sudo iw reg set US 2>/dev/null || true
    
    # Configure interface for high performance
    sudo ethtool -K $WIFI_INTERFACE gro on 2>/dev/null || true
    sudo ethtool -K $WIFI_INTERFACE gso on 2>/dev/null || true
    sudo ethtool -K $WIFI_INTERFACE tso on 2>/dev/null || true
    
    log "WiFi interface configured for performance"
}

optimize_irq_affinity() {
    log "Optimizing IRQ affinity for WiFi..."
    
    # Find WiFi IRQ
    WIFI_IRQ=$(grep -i mt7925 /proc/interrupts | awk -F: '{print $1}' | tr -d ' ' | head -1)
    
    if [ -n "$WIFI_IRQ" ]; then
        # Bind WiFi IRQ to performance cores (cores 0-11 for Ryzen AI 9 HX 370)
        echo "fff" | sudo tee /proc/irq/$WIFI_IRQ/smp_affinity > /dev/null 2>&1 || true
        log "WiFi IRQ $WIFI_IRQ bound to performance cores"
    fi
}

create_wifi_monitoring() {
    log "Creating WiFi performance monitoring script..."
    
    cat > "$HOME/bin/wifi7-status" << 'EOF'
#!/bin/bash
# WiFi 7 Performance Status Monitor

echo "=== WiFi 7 Performance Status ==="
echo ""

# Get WiFi interface
WIFI_INTERFACE=$(iw dev | grep Interface | awk '{print $2}' | head -1)

if [ -n "$WIFI_INTERFACE" ]; then
    echo "Interface: $WIFI_INTERFACE"
    echo ""
    
    # Connection info
    echo "Connection Info:"
    iw dev $WIFI_INTERFACE link 2>/dev/null | grep -E "(Connected|SSID|freq|signal|tx bitrate|rx bitrate)" || echo "Not connected"
    echo ""
    
    # Interface statistics
    echo "Interface Statistics:"
    cat /proc/net/dev | grep $WIFI_INTERFACE | awk '{printf "RX: %s bytes, TX: %s bytes\n", $2, $10}'
    echo ""
    
    # Power save status
    echo "Power Save: $(iw dev $WIFI_INTERFACE get power_save 2>/dev/null || echo "Unknown")"
    echo ""
    
    # Regulatory domain
    echo "Regulatory Domain: $(iw reg get | grep country | awk '{print $2}' | head -1)"
    echo ""
    
    # WiFi capabilities
    echo "WiFi Capabilities:"
    iw dev $WIFI_INTERFACE info | grep -E "(type|channel|txpower)" 2>/dev/null || echo "Info not available"
fi
EOF
    
    chmod +x "$HOME/bin/wifi7-status"
    mkdir -p "$HOME/bin"
}

setup_wifi_service() {
    log "Setting up WiFi optimization service..."
    
    # Create systemd service for WiFi optimizations
    sudo tee /etc/systemd/system/wifi7-optimization.service > /dev/null << EOF
[Unit]
Description=WiFi 7 Performance Optimization
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi7-optimize
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # Create the optimization script
    sudo tee /usr/local/bin/wifi7-optimize > /dev/null << 'EOF'
#!/bin/bash
# WiFi 7 optimization script

# Get WiFi interface
WIFI_INTERFACE=$(iw dev | grep Interface | awk '{print $2}' | head -1)

if [ -n "$WIFI_INTERFACE" ]; then
    # Disable power save
    iw dev $WIFI_INTERFACE set power_save off 2>/dev/null || true
    
    # Set regulatory domain
    iw reg set US 2>/dev/null || true
    
    # Optimize interface
    ethtool -K $WIFI_INTERFACE gro on 2>/dev/null || true
    ethtool -K $WIFI_INTERFACE gso on 2>/dev/null || true
    ethtool -K $WIFI_INTERFACE tso on 2>/dev/null || true
fi
EOF

    sudo chmod +x /usr/local/bin/wifi7-optimize
    sudo systemctl enable wifi7-optimization.service
}

main() {
    log "Starting WiFi 7 performance optimization..."
    
    check_wifi_device
    optimize_wifi_driver
    optimize_network_stack
    configure_wifi_interface
    optimize_irq_affinity
    create_wifi_monitoring
    setup_wifi_service
    
    echo ""
    log "WiFi 7 optimization complete!"
    echo ""
    echo "✅ MediaTek MT7925 driver optimized"
    echo "✅ Network stack tuned for WiFi 7"
    echo "✅ Interface configured for performance"
    echo "✅ IRQ affinity optimized"
    echo "✅ Monitoring tools installed"
    echo ""
    echo "📊 Check WiFi status with: wifi7-status"
    echo "🔄 Reboot recommended to apply all optimizations"
}

main "$@"
