#!/bin/bash
# Create Debian Stable Bootable NVMe Drive
# This script downloads Debian and writes it to an external NVMe

set -e

# Colors
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
DEBIAN_ISO="debian-${DEBIAN_VERSION}-${DEBIAN_ARCH}-netinst.iso"
DEBIAN_URL="https://cdimage.debian.org/debian-cd/current/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO}"
DEBIAN_SHA256_URL="${DEBIAN_URL}.SHA256SUMS"

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
    fi
    
    # Check required tools
    local missing_tools=()
    
    for tool in wget dd lsblk fdisk mkfs.vfat mkfs.ext4 parted curl sha256sum; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        warning "Missing tools: ${missing_tools[*]}"
        log "Installing missing tools..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y wget coreutils util-linux fdisk dosfstools e2fsprogs parted curl
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y wget coreutils util-linux fdisk dosfstools e2fsprogs parted curl
        else
            error "Cannot install required tools automatically"
        fi
    fi
    
    log "Prerequisites check passed"
}

list_drives() {
    echo ""
    echo "Available drives:"
    echo "================="
    lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep -E "disk|nvme"
    echo ""
}

detect_nvme() {
    log "Detecting external NVMe drive..."
    
    # List all drives
    list_drives
    
    # Try to auto-detect USB-attached NVMe
    local usb_nvme=$(lsblk -d -o NAME,TRAN,TYPE | grep -E "usb.*disk|usb.*nvme" | awk '{print $1}')
    
    if [ -n "$usb_nvme" ]; then
        warning "Detected possible USB-attached drive: /dev/$usb_nvme"
        echo ""
        lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT /dev/$usb_nvme
        echo ""
        read -p "Is this your target NVMe drive? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            TARGET_DRIVE="/dev/$usb_nvme"
            return
        fi
    fi
    
    # Manual selection
    echo ""
    echo "Please identify your external NVMe drive."
    echo "WARNING: All data on the selected drive will be ERASED!"
    echo ""
    read -p "Enter the device name (e.g., sdb, sdc, nvme1n1): " device_name
    
    if [ -z "$device_name" ]; then
        error "No device specified"
    fi
    
    TARGET_DRIVE="/dev/$device_name"
    
    # Verify drive exists
    if [ ! -e "$TARGET_DRIVE" ]; then
        error "Device $TARGET_DRIVE does not exist"
    fi
    
    # Show drive info for confirmation
    echo ""
    echo "Selected drive information:"
    lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT "$TARGET_DRIVE"
    echo ""
    
    # Get drive size
    local drive_size=$(lsblk -b -d -o SIZE "$TARGET_DRIVE" | tail -1)
    local drive_size_gb=$((drive_size / 1000000000))
    
    warning "This will COMPLETELY ERASE the ${drive_size_gb}GB drive at $TARGET_DRIVE"
    read -p "Are you ABSOLUTELY SURE? Type 'yes' to continue: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        error "Aborted by user"
    fi
}

download_debian() {
    log "Downloading Debian $DEBIAN_VERSION..."
    
    cd /tmp
    
    # Download if not already present
    if [ ! -f "$DEBIAN_ISO" ]; then
        wget -c "$DEBIAN_URL" -O "$DEBIAN_ISO"
    else
        log "ISO already downloaded, verifying..."
    fi
    
    # Download and verify checksum
    log "Verifying ISO integrity..."
    wget -q "$DEBIAN_SHA256_URL" -O debian-sha256sums
    
    # Extract checksum for our ISO
    local expected_sha=$(grep "$DEBIAN_ISO" debian-sha256sums | awk '{print $1}')
    local actual_sha=$(sha256sum "$DEBIAN_ISO" | awk '{print $1}')
    
    if [ "$expected_sha" != "$actual_sha" ]; then
        error "ISO checksum verification failed!"
    fi
    
    log "ISO verification passed"
}

create_bootable_drive() {
    log "Creating bootable drive..."
    
    # Unmount any mounted partitions
    log "Unmounting any mounted partitions..."
    for partition in $(lsblk -o NAME,MOUNTPOINT "$TARGET_DRIVE" | grep -E "├|└" | awk '{print $1}' | sed 's/[├└─]//g'); do
        if mountpoint -q "/dev/$partition" 2>/dev/null; then
            sudo umount "/dev/$partition" || true
        fi
    done
    
    # Write ISO directly to drive (simple method)
    log "Writing Debian installer to $TARGET_DRIVE..."
    log "This will take several minutes..."
    
    sudo dd if="/tmp/$DEBIAN_ISO" of="$TARGET_DRIVE" bs=4M status=progress conv=fsync
    
    log "Bootable drive created successfully!"
}

create_persistent_partition() {
    log "Creating additional partition for persistence (optional)..."
    
    # Wait for device to settle
    sleep 2
    sync
    
    # Get device size and ISO size
    local device_size=$(lsblk -b -d -o SIZE "$TARGET_DRIVE" | tail -1)
    local iso_size=$(stat -c%s "/tmp/$DEBIAN_ISO")
    local remaining_size=$((device_size - iso_size - 1048576000)) # Leave 1GB buffer
    
    if [ $remaining_size -gt 5368709120 ]; then # If more than 5GB remaining
        log "Creating persistence partition with remaining space..."
        
        # This is complex with hybrid ISO, skipping for simplicity
        log "Note: For persistence, consider installing to the NVMe after booting"
    fi
}

print_instructions() {
    echo ""
    echo "============================================="
    echo "   Debian Bootable Drive Created! 🎉"
    echo "============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Safely remove the NVMe drive:"
    echo "   sudo sync"
    echo "   sudo eject $TARGET_DRIVE"
    echo ""
    echo "2. Install the NVMe in your Framework laptop"
    echo ""
    echo "3. Boot from the NVMe:"
    echo "   - Power on and press F12 (or F2 for BIOS)"
    echo "   - Select the NVMe drive as boot device"
    echo ""
    echo "4. Install Debian:"
    echo "   - Choose 'Graphical Install' or 'Install'"
    echo "   - When partitioning, you can use the entire disk"
    echo "   - Recommended partition scheme:"
    echo "     • EFI: 512MB"
    echo "     • /boot: 1GB"
    echo "     • /: 100GB (ext4)"
    echo "     • /home: Remaining space (ext4)"
    echo "     • swap: 4-8GB (or use swap file later)"
    echo ""
    echo "5. After installation completes:"
    echo "   - Boot into new system"
    echo "   - Install git: sudo apt install git"
    echo "   - Clone this repo: git clone [repo] ~/git/linux-setup"
    echo "   - Run: ~/git/linux-setup/setup-everything.sh"
    echo ""
    echo "Performance tip: During installation, avoid enabling disk encryption"
    echo "for maximum NVMe performance (unless security requires it)."
}

main() {
    clear
    echo "============================================="
    echo "   Debian Stable Bootable NVMe Creator"
    echo "============================================="
    echo ""
    echo "This script will:"
    echo "1. Download Debian $DEBIAN_VERSION (stable)"
    echo "2. Write it to your external NVMe drive"
    echo "3. Make it bootable for installation"
    echo ""
    warning "This will ERASE all data on the target drive!"
    echo ""
    
    check_prerequisites
    detect_nvme
    download_debian
    create_bootable_drive
    print_instructions
    
    log "Process complete!"
}

# Run main
main "$@"