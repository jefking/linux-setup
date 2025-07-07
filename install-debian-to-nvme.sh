#!/bin/bash
# Direct Debian Installation to External NVMe
# This installs a complete bootable Debian system on the NVMe

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

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [ "$EUID" -eq 0 ]; then
        error "Don't run as root. Will ask for sudo when needed."
    fi
    
    # Check for required tools
    local tools=(debootstrap parted mkfs.ext4 mkfs.vfat arch-chroot)
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing+=($tool)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log "Installing missing tools..."
        sudo apt-get update
        sudo apt-get install -y debootstrap arch-install-scripts parted dosfstools
    fi
}

detect_nvme() {
    log "Detecting external NVMe drive..."
    
    # List all drives
    echo ""
    echo "Available drives:"
    echo "================="
    lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep -E "disk|nvme"
    echo ""
    
    # Get USB-attached drives
    local usb_drives=$(lsblk -d -o NAME,TRAN,SIZE,MODEL | grep usb | awk '{print $1}')
    
    if [ -n "$usb_drives" ]; then
        warning "Found USB-attached drive(s):"
        lsblk -d -o NAME,SIZE,MODEL,TRAN | grep usb
        echo ""
        
        # If only one USB drive, suggest it
        if [ $(echo "$usb_drives" | wc -l) -eq 1 ]; then
            TARGET_DRIVE="/dev/$usb_drives"
            warning "Detected USB drive: $TARGET_DRIVE"
            
            # Show details
            echo "Drive details:"
            lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$TARGET_DRIVE"
            echo ""
            
            read -p "Use this drive? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                return
            fi
        fi
    fi
    
    # Manual selection
    read -p "Enter device name (e.g., sdb, nvme1n1): " device
    TARGET_DRIVE="/dev/$device"
    
    if [ ! -e "$TARGET_DRIVE" ]; then
        error "Device $TARGET_DRIVE not found"
    fi
    
    # Confirm
    warning "This will ERASE all data on $TARGET_DRIVE"
    lsblk -o NAME,SIZE,MODEL "$TARGET_DRIVE"
    read -p "Type 'yes' to continue: " confirm
    
    if [ "$confirm" != "yes" ]; then
        error "Aborted"
    fi
}

partition_drive() {
    log "Partitioning drive..."
    
    # Unmount any mounted partitions
    for part in $(lsblk -n -o NAME "$TARGET_DRIVE" | tail -n +2); do
        sudo umount "/dev/$part" 2>/dev/null || true
    done
    
    # Clear the drive
    sudo wipefs -a "$TARGET_DRIVE"
    
    # Create GPT partition table
    sudo parted -s "$TARGET_DRIVE" mklabel gpt
    
    # Create partitions
    # 1. EFI System Partition (512MB)
    sudo parted -s "$TARGET_DRIVE" mkpart ESP fat32 1MiB 513MiB
    sudo parted -s "$TARGET_DRIVE" set 1 esp on
    
    # 2. Boot partition (1GB) 
    sudo parted -s "$TARGET_DRIVE" mkpart boot ext4 513MiB 1537MiB
    
    # 3. Root partition (100GB)
    sudo parted -s "$TARGET_DRIVE" mkpart root ext4 1537MiB 102400MiB
    
    # 4. Swap partition (8GB)
    sudo parted -s "$TARGET_DRIVE" mkpart swap linux-swap 102400MiB 110592MiB
    
    # 5. Home partition (remaining space)
    sudo parted -s "$TARGET_DRIVE" mkpart home ext4 110592MiB 100%
    
    # Wait for kernel to recognize partitions
    sleep 2
    sudo partprobe "$TARGET_DRIVE"
    
    # Get partition names (handles both sdX and nvmeXnY naming)
    if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
        EFI_PART="${TARGET_DRIVE}p1"
        BOOT_PART="${TARGET_DRIVE}p2"
        ROOT_PART="${TARGET_DRIVE}p3"
        SWAP_PART="${TARGET_DRIVE}p4"
        HOME_PART="${TARGET_DRIVE}p5"
    else
        EFI_PART="${TARGET_DRIVE}1"
        BOOT_PART="${TARGET_DRIVE}2"
        ROOT_PART="${TARGET_DRIVE}3"
        SWAP_PART="${TARGET_DRIVE}4"
        HOME_PART="${TARGET_DRIVE}5"
    fi
}

format_partitions() {
    log "Formatting partitions..."
    
    # Format EFI
    sudo mkfs.vfat -F32 -n EFI "$EFI_PART"
    
    # Format boot
    sudo mkfs.ext4 -L boot "$BOOT_PART"
    
    # Format root
    sudo mkfs.ext4 -L root "$ROOT_PART"
    
    # Format swap
    sudo mkswap -L swap "$SWAP_PART"
    
    # Format home
    sudo mkfs.ext4 -L home "$HOME_PART"
    
    log "Partitions formatted successfully"
}

mount_partitions() {
    log "Mounting partitions..."
    
    # Create mount point
    MOUNT_POINT="/mnt/debian-install"
    sudo mkdir -p "$MOUNT_POINT"
    
    # Mount root
    sudo mount "$ROOT_PART" "$MOUNT_POINT"
    
    # Create and mount other directories
    sudo mkdir -p "$MOUNT_POINT"/{boot,boot/efi,home}
    sudo mount "$BOOT_PART" "$MOUNT_POINT/boot"
    sudo mount "$EFI_PART" "$MOUNT_POINT/boot/efi"
    sudo mount "$HOME_PART" "$MOUNT_POINT/home"
}

install_base_system() {
    log "Installing Debian base system..."
    log "This will take 10-20 minutes..."
    
    # Install base system
    sudo debootstrap --arch=amd64 --include=linux-image-amd64,grub-efi-amd64,sudo,network-manager,firmware-linux,firmware-linux-nonfree bookworm "$MOUNT_POINT" http://deb.debian.org/debian/
    
    # Mount necessary filesystems
    sudo mount --bind /dev "$MOUNT_POINT/dev"
    sudo mount --bind /dev/pts "$MOUNT_POINT/dev/pts"
    sudo mount --bind /proc "$MOUNT_POINT/proc"
    sudo mount --bind /sys "$MOUNT_POINT/sys"
}

configure_system() {
    log "Configuring system..."
    
    # Create fstab
    cat << EOF | sudo tee "$MOUNT_POINT/etc/fstab"
# /etc/fstab: static file system information
UUID=$(sudo blkid -o value -s UUID "$ROOT_PART") /         ext4 errors=remount-ro 0 1
UUID=$(sudo blkid -o value -s UUID "$BOOT_PART") /boot     ext4 defaults          0 2
UUID=$(sudo blkid -o value -s UUID "$EFI_PART")  /boot/efi vfat umask=0077        0 1
UUID=$(sudo blkid -o value -s UUID "$HOME_PART") /home     ext4 defaults          0 2
UUID=$(sudo blkid -o value -s UUID "$SWAP_PART") none      swap sw                0 0
EOF
    
    # Set hostname
    echo "framework-laptop" | sudo tee "$MOUNT_POINT/etc/hostname"
    
    # Configure networking
    cat << EOF | sudo tee "$MOUNT_POINT/etc/hosts"
127.0.0.1       localhost
127.0.1.1       framework-laptop
EOF
    
    # Configure apt sources
    cat << EOF | sudo tee "$MOUNT_POINT/etc/apt/sources.list"
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF
}

install_packages() {
    log "Installing essential packages..."
    
    # Create script to run in chroot
    cat << 'EOF' | sudo tee "$MOUNT_POINT/tmp/setup.sh"
#!/bin/bash
# Update package list
apt-get update

# Install essential packages
apt-get install -y \
    bash-completion \
    build-essential \
    curl \
    git \
    htop \
    nano \
    vim \
    wget \
    net-tools \
    openssh-server \
    firefox-esr \
    gnome-core \
    gdm3

# Set up timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# Set up locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
EOF
    
    sudo chmod +x "$MOUNT_POINT/tmp/setup.sh"
    sudo chroot "$MOUNT_POINT" /tmp/setup.sh
}

setup_bootloader() {
    log "Installing bootloader..."
    
    # Install GRUB
    sudo chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian
    sudo chroot "$MOUNT_POINT" update-grub
}

create_user() {
    log "Creating user account..."
    
    echo "Enter username for the new system:"
    read -r username
    
    # Create user
    sudo chroot "$MOUNT_POINT" useradd -m -G sudo,audio,video,plugdev,netdev -s /bin/bash "$username"
    
    echo "Set password for $username:"
    sudo chroot "$MOUNT_POINT" passwd "$username"
    
    # Set root password
    echo "Set root password:"
    sudo chroot "$MOUNT_POINT" passwd root
}

cleanup() {
    log "Cleaning up..."
    
    # Unmount everything
    sudo umount -R "$MOUNT_POINT" 2>/dev/null || true
}

print_summary() {
    echo ""
    echo "============================================="
    echo "   Debian Installation Complete! 🎉"
    echo "============================================="
    echo ""
    echo "System configuration:"
    echo "- Debian 12 (Bookworm) installed"
    echo "- GNOME desktop environment"
    echo "- Partitions:"
    echo "  • EFI: 512MB"
    echo "  • /boot: 1GB (ext4)"
    echo "  • /: 100GB (ext4)"
    echo "  • swap: 8GB"
    echo "  • /home: remaining space (ext4)"
    echo ""
    echo "Next steps:"
    echo "1. Safely disconnect the NVMe:"
    echo "   sudo sync"
    echo "   sudo eject $TARGET_DRIVE"
    echo ""
    echo "2. Install NVMe in Framework laptop"
    echo ""
    echo "3. Boot and login with your created user"
    echo ""
    echo "4. Clone and run setup scripts:"
    echo "   git clone [your-repo] ~/git/linux-setup"
    echo "   cd ~/git/linux-setup"
    echo "   ./setup-everything.sh"
}

main() {
    clear
    echo "============================================="
    echo "   Direct Debian Installation to NVMe"
    echo "============================================="
    echo ""
    echo "This will install a complete Debian system on your NVMe"
    echo ""
    
    check_prerequisites
    detect_nvme
    partition_drive
    format_partitions
    mount_partitions
    
    install_base_system
    configure_system
    install_packages
    setup_bootloader
    create_user
    
    cleanup
    print_summary
}

# Set up trap to cleanup on exit
trap cleanup EXIT

# Run main
main "$@"