#!/bin/bash
# Automated Debian USB Installer Creator
# Non-interactive version for creating bootable USB

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
TARGET_USB="/dev/sda"  # Your USB drive
DEBIAN_VERSION="12.11.0"
DEBIAN_ARCH="amd64"
DEBIAN_ISO="debian-${DEBIAN_VERSION}-${DEBIAN_ARCH}-netinst.iso"
DEBIAN_URL="https://cdimage.debian.org/debian-cd/current/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO}"
DEBIAN_SHA256_URL="${DEBIAN_URL}.SHA256SUMS"

verify_usb() {
    log "Verifying USB device..."
    
    if [ ! -e "$TARGET_USB" ]; then
        error "USB device $TARGET_USB not found"
    fi
    
    # Verify it's the USB device
    if ! lsblk -d -o TRAN "$TARGET_USB" 2>/dev/null | grep -q usb; then
        error "$TARGET_USB is not a USB device"
    fi
    
    # Show device info
    log "Target USB device:"
    lsblk -o NAME,SIZE,TYPE,MODEL,LABEL,MOUNTPOINT "$TARGET_USB"
    echo ""
    
    # Size check
    usb_size=$(lsblk -b -d -o SIZE "$TARGET_USB" | tail -1)
    usb_size_gb=$((usb_size / 1000000000))
    
    log "USB size: ${usb_size_gb}GB"
    
    if [ "$usb_size_gb" -lt 1 ]; then
        error "USB drive too small (need at least 1GB)"
    fi
}

unmount_usb() {
    log "Unmounting USB partitions..."
    
    # Unmount all partitions
    for part in $(lsblk -n -o NAME,MOUNTPOINT "$TARGET_USB" | awk '$2!="" {print "/dev/"$1}'); do
        log "Unmounting $part..."
        sudo umount "$part" 2>/dev/null || true
    done
    
    # Also try to unmount by device name
    sudo umount "$TARGET_USB"* 2>/dev/null || true
}

download_debian() {
    log "Downloading Debian $DEBIAN_VERSION..."
    
    cd /tmp
    
    # Check if already downloaded
    if [ -f "$DEBIAN_ISO" ]; then
        log "ISO already exists, checking integrity..."
    else
        log "Downloading from: $DEBIAN_URL"
        log "This will take a few minutes..."
        wget -c "$DEBIAN_URL" -O "$DEBIAN_ISO" || error "Download failed"
    fi
    
    # Download and verify checksum
    log "Verifying ISO integrity..."
    wget -q "$DEBIAN_SHA256_URL" -O debian-sha256sums || warning "Cannot download checksums"
    
    if [ -f debian-sha256sums ]; then
        expected_sha=$(grep "$DEBIAN_ISO" debian-sha256sums | awk '{print $1}')
        actual_sha=$(sha256sum "$DEBIAN_ISO" | awk '{print $1}')
        
        if [ -n "$expected_sha" ] && [ "$expected_sha" = "$actual_sha" ]; then
            log "ISO verification passed ✓"
        else
            warning "ISO verification failed or unavailable, continuing anyway..."
        fi
    fi
    
    log "ISO ready: /tmp/$DEBIAN_ISO"
}

create_bootable_usb() {
    log "Creating bootable USB..."
    
    warning "This will ERASE all data on $TARGET_USB"
    log "Writing Debian installer to USB..."
    
    # Use dd to write the ISO
    sudo dd if="/tmp/$DEBIAN_ISO" of="$TARGET_USB" bs=4M status=progress conv=fsync
    
    # Ensure all data is written
    sync
    
    log "Bootable USB created successfully! ✓"
}

main() {
    clear
    echo "============================================="
    echo "   Automated Debian USB Installer Creator"
    echo "============================================="
    echo ""
    
    verify_usb
    
    echo ""
    warning "This will ERASE all data on the USB drive!"
    echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    
    unmount_usb
    download_debian
    create_bootable_usb
    
    echo ""
    echo "============================================="
    echo "   Success! USB installer ready 🎉"
    echo "============================================="
    echo ""
    echo "Your USB drive now contains Debian $DEBIAN_VERSION installer"
    echo ""
    echo "Next steps:"
    echo "1. Safely remove USB: sudo eject $TARGET_USB"
    echo "2. Install NVMe in Framework laptop"
    echo "3. Boot from USB (F12 for boot menu)"
    echo "4. Install Debian to the NVMe"
    echo ""
    log "Done!"
}

# Run main
main "$@"