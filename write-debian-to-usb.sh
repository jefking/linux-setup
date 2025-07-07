#!/bin/bash
# Write Debian ISO to USB drive
# Simple script to write already downloaded ISO to USB

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
TARGET_USB="/dev/sda"
ISO_PATH="/tmp/debian-12.11.0-amd64-netinst.iso"

# Check if ISO exists
if [ ! -f "$ISO_PATH" ]; then
    error "ISO not found at $ISO_PATH"
fi

# Get ISO size
iso_size=$(ls -lh "$ISO_PATH" | awk '{print $5}')
log "Found ISO: $ISO_PATH ($iso_size)"

# Verify USB device
if [ ! -e "$TARGET_USB" ]; then
    error "USB device $TARGET_USB not found"
fi

# Show USB info
log "Target USB device:"
lsblk -o NAME,SIZE,TYPE,MODEL,LABEL,MOUNTPOINT "$TARGET_USB"
echo ""

warning "This will ERASE all data on $TARGET_USB"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    error "Aborted by user"
fi

# Unmount USB partitions
log "Unmounting USB partitions..."
for part in $(lsblk -n -o NAME,MOUNTPOINT "$TARGET_USB" | awk '$2!="" {print "/dev/"$1}'); do
    log "Unmounting $part..."
    sudo umount "$part" 2>/dev/null || true
done

# Write ISO to USB
log "Writing Debian installer to USB..."
log "This will take 5-10 minutes..."

sudo dd if="$ISO_PATH" of="$TARGET_USB" bs=4M status=progress conv=fsync

# Sync to ensure all data is written
sync

log "Success! Bootable USB created ✓"

echo ""
echo "Next steps:"
echo "1. Safely remove USB: sudo eject $TARGET_USB"
echo "2. Boot from this USB on your Framework laptop"
echo "3. Install Debian to your NVMe drive"