#!/bin/bash
# Create Debian Installer USB Stick
# This creates a bootable USB installer for installing Debian on your NVMe

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

# Debian stable (Bookworm) URLs
DEBIAN_VERSION="12.8.0"
DEBIAN_ARCH="amd64"
# Using DVD-1 for offline installation capability
DEBIAN_ISO="debian-${DEBIAN_VERSION}-${DEBIAN_ARCH}-DVD-1.iso"
DEBIAN_NETINST="debian-${DEBIAN_VERSION}-${DEBIAN_ARCH}-netinst.iso"

print_menu() {
    echo ""
    echo "Choose Debian installer type:"
    echo "1) Network installer (650MB) - Recommended for fast internet"
    echo "2) DVD installer (4.4GB) - Contains more packages offline"
    echo ""
    read -p "Enter choice [1-2]: " choice
    
    case $choice in
        1)
            DEBIAN_ISO="$DEBIAN_NETINST"
            DEBIAN_URL="https://cdimage.debian.org/debian-cd/current/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO}"
            ;;
        2)
            DEBIAN_URL="https://cdimage.debian.org/debian-cd/current/${DEBIAN_ARCH}/iso-dvd/${DEBIAN_ISO}"
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
    
    DEBIAN_SHA256_URL="${DEBIAN_URL}.SHA256SUMS"
}

detect_usb() {
    log "Detecting USB drives..."
    
    echo ""
    echo "Available USB drives:"
    echo "===================="
    
    # List only USB drives
    lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep -E "disk.*usb" || {
        error "No USB drives detected. Please insert a USB stick."
    }
    
    echo ""
    warning "Make sure you've selected the correct USB drive!"
    echo ""
    
    # Count USB drives
    usb_count=$(lsblk -d -o TRAN | grep -c usb || true)
    
    if [ "$usb_count" -eq 1 ]; then
        # Auto-detect single USB
        USB_DEVICE=$(lsblk -d -o NAME,TRAN | grep usb | awk '{print $1}')
        warning "Detected USB drive: /dev/$USB_DEVICE"
        
        # Show details
        echo ""
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "/dev/$USB_DEVICE"
        echo ""
        
        read -p "Use this USB drive? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            TARGET_USB="/dev/$USB_DEVICE"
            return
        fi
    fi
    
    # Manual selection
    read -p "Enter USB device name (e.g., sdb, sdc): " device
    TARGET_USB="/dev/$device"
    
    if [ ! -e "$TARGET_USB" ]; then
        error "Device $TARGET_USB not found"
    fi
    
    # Verify it's USB
    if ! lsblk -d -o TRAN "$TARGET_USB" | grep -q usb; then
        error "$TARGET_USB is not a USB device"
    fi
    
    # Final confirmation
    echo ""
    warning "This will ERASE all data on $TARGET_USB"
    lsblk -o NAME,SIZE,LABEL,MOUNTPOINT "$TARGET_USB"
    echo ""
    read -p "Type 'yes' to continue: " confirm
    
    if [ "$confirm" != "yes" ]; then
        error "Aborted"
    fi
}

download_debian() {
    log "Downloading Debian $DEBIAN_VERSION..."
    
    cd /tmp
    
    # Check if already downloaded
    if [ -f "$DEBIAN_ISO" ]; then
        log "ISO already downloaded, verifying..."
    else
        # Download with progress
        wget -c "$DEBIAN_URL" -O "$DEBIAN_ISO" || error "Download failed"
    fi
    
    # Verify checksum
    log "Verifying ISO integrity..."
    wget -q "$DEBIAN_SHA256_URL" -O debian-sha256sums || error "Cannot download checksums"
    
    # Extract and verify
    expected_sha=$(grep "$DEBIAN_ISO" debian-sha256sums | awk '{print $1}')
    actual_sha=$(sha256sum "$DEBIAN_ISO" | awk '{print $1}')
    
    if [ -z "$expected_sha" ]; then
        warning "Cannot find checksum for $DEBIAN_ISO, skipping verification"
    elif [ "$expected_sha" != "$actual_sha" ]; then
        error "ISO checksum verification failed!"
    else
        log "ISO verification passed ✓"
    fi
}

create_usb() {
    log "Creating bootable USB..."
    
    # Unmount any mounted partitions
    for part in $(lsblk -n -o NAME,MOUNTPOINT "$TARGET_USB" | grep -v "^${TARGET_USB##*/} " | awk '$2!="" {print "/dev/"$1}'); do
        log "Unmounting $part..."
        sudo umount "$part" 2>/dev/null || true
    done
    
    # Write ISO to USB
    log "Writing Debian installer to USB..."
    log "This will take 5-10 minutes..."
    
    sudo dd if="/tmp/$DEBIAN_ISO" of="$TARGET_USB" bs=4M status=progress conv=fsync
    
    # Ensure all data is written
    sync
    
    log "Bootable USB created successfully! ✓"
}

print_instructions() {
    echo ""
    echo "============================================="
    echo "   Debian USB Installer Created! 🎉"
    echo "============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Remove the USB stick safely:"
    echo "   sudo eject $TARGET_USB"
    echo ""
    echo "2. Install your NVMe drive in the Framework laptop"
    echo ""
    echo "3. Insert the USB installer and boot:"
    echo "   - Power on and press F12 for boot menu"
    echo "   - Select the USB drive"
    echo ""
    echo "4. During Debian installation:"
    echo ""
    echo "   Recommended partition scheme for 2TB NVMe:"
    echo "   ┌─────────────────────────────────────┐"
    echo "   │ • EFI System:     512MB  (FAT32)    │"
    echo "   │ • /boot:          2GB    (ext4)     │"
    echo "   │ • /:              100GB  (ext4)     │"
    echo "   │ • swap:           8GB               │"
    echo "   │ • /home:          remaining (ext4)  │"
    echo "   └─────────────────────────────────────┘"
    echo ""
    echo "   Software selection:"
    echo "   • Debian desktop environment"
    echo "   • GNOME (or your preferred DE)"
    echo "   • Standard system utilities"
    echo ""
    echo "5. After installation:"
    echo "   - Boot into new system"
    echo "   - Install git: sudo apt install git"
    echo "   - Clone this repo:"
    echo "     git clone [your-repo] ~/git/linux-setup"
    echo "   - Run setup:"
    echo "     cd ~/git/linux-setup"
    echo "     ./setup-everything.sh"
    echo ""
    echo "Tip: For Framework laptop, you may need to add"
    echo "     'nomodeset' kernel parameter if graphics issues occur"
}

cleanup() {
    # Optionally remove ISO
    if [ -f "/tmp/$DEBIAN_ISO" ]; then
        read -p "Delete downloaded ISO? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "/tmp/$DEBIAN_ISO" "/tmp/debian-sha256sums"
            log "Cleaned up temporary files"
        fi
    fi
}

main() {
    clear
    echo "============================================="
    echo "   Debian USB Installer Creator"
    echo "============================================="
    echo ""
    echo "This will create a bootable Debian installer USB"
    echo ""
    warning "Please insert your USB stick now"
    echo ""
    read -p "Press Enter when ready..."
    
    print_menu
    detect_usb
    download_debian
    create_usb
    print_instructions
    cleanup
    
    log "All done!"
}

# Run main
main "$@"