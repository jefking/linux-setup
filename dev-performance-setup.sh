#!/bin/bash
# Framework Laptop Development Performance Optimization Script
# For Intel i7-1280P with 32GB RAM

set -e

echo "🚀 Setting up development performance optimizations..."

# Create development tmpfs directories with enhanced configuration
AVAILABLE_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
TMPFS_SIZE="12G"  # Increased for better development experience
BUILD_CACHE_SIZE="6G"  # Increased for larger build caches
DEV_TMPFS="/tmp/dev-workspace"
BUILD_TMPFS="/tmp/build-cache"
FSTAB_BACKUP="/etc/fstab.backup.$(date +%Y%m%d)"

# 1. Create smart tmpfs mounts for development with persistent configuration
create_dev_tmpfs() {
    echo "📁 Creating enhanced development tmpfs directories..."

    # Check available memory and adjust sizes if needed
    if [ "$AVAILABLE_MEM_GB" -lt 20 ]; then
        TMPFS_SIZE="8G"
        BUILD_CACHE_SIZE="4G"
        echo "⚠️  Adjusted tmpfs sizes for available memory (${AVAILABLE_MEM_GB}GB)"
    fi

    # Development workspace (for active projects)
    sudo mkdir -p "$DEV_TMPFS"
    sudo mkdir -p "$BUILD_TMPFS"

    # Mount tmpfs with optimal settings for development
    if ! mountpoint -q "$DEV_TMPFS"; then
        sudo mount -t tmpfs -o size=$TMPFS_SIZE,mode=1777,noatime,nodiratime,nodev,nosuid tmpfs "$DEV_TMPFS"
        echo "✅ Mounted dev workspace tmpfs ($TMPFS_SIZE)"
    fi

    if ! mountpoint -q "$BUILD_TMPFS"; then
        sudo mount -t tmpfs -o size=$BUILD_CACHE_SIZE,mode=1777,noatime,nodiratime,nodev,nosuid tmpfs "$BUILD_TMPFS"
        echo "✅ Mounted build cache tmpfs ($BUILD_CACHE_SIZE)"
    fi

    # Set ownership and permissions
    sudo chown $USER:$USER "$DEV_TMPFS" "$BUILD_TMPFS"
    chmod 755 "$DEV_TMPFS" "$BUILD_TMPFS"

    # Make mounts persistent across reboots
    create_persistent_mounts
}

# Create persistent tmpfs mounts in /etc/fstab
create_persistent_mounts() {
    echo "🔧 Making tmpfs mounts persistent..."

    # Backup fstab
    if [ ! -f "$FSTAB_BACKUP" ]; then
        sudo cp /etc/fstab "$FSTAB_BACKUP"
        echo "📋 Backed up /etc/fstab to $FSTAB_BACKUP"
    fi

    # Check if entries already exist
    if ! grep -q "$DEV_TMPFS" /etc/fstab; then
        echo "tmpfs $DEV_TMPFS tmpfs size=$TMPFS_SIZE,mode=1777,noatime,nodiratime,nodev,nosuid,uid=$(id -u),gid=$(id -g) 0 0" | sudo tee -a /etc/fstab
        echo "✅ Added dev workspace to /etc/fstab"
    fi

    if ! grep -q "$BUILD_TMPFS" /etc/fstab; then
        echo "tmpfs $BUILD_TMPFS tmpfs size=$BUILD_CACHE_SIZE,mode=1777,noatime,nodiratime,nodev,nosuid,uid=$(id -u),gid=$(id -g) 0 0" | sudo tee -a /etc/fstab
        echo "✅ Added build cache to /etc/fstab"
    fi
}

# 2. Create project sync scripts
create_sync_scripts() {
    echo "🔄 Creating project sync scripts..."
    
    cat > "$HOME/bin/dev-sync-to-ram" << 'EOF'
#!/bin/bash
# Enhanced sync project to RAM for fast development with conflict detection

set -e

PROJECT_PATH="$1"
FORCE_SYNC="$2"

if [ -z "$PROJECT_PATH" ]; then
    echo "Usage: dev-sync-to-ram /path/to/project [--force]"
    echo "       dev-sync-to-ram --list    # List synced projects"
    exit 1
fi

# Handle list command
if [ "$PROJECT_PATH" = "--list" ]; then
    SYNC_FILE="$HOME/.dev-ram-sync"
    if [ -f "$SYNC_FILE" ]; then
        echo "📋 Currently synced projects:"
        while IFS='|' read -r disk_path ram_path; do
            project_name=$(basename "$disk_path")
            if [ -d "$ram_path" ]; then
                size=$(du -sh "$ram_path" 2>/dev/null | cut -f1)
                echo "  ✅ $project_name ($size) -> $ram_path"
            else
                echo "  ❌ $project_name (missing) -> $ram_path"
            fi
        done < "$SYNC_FILE"
    else
        echo "No projects currently synced to RAM"
    fi
    exit 0
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")
RAM_PROJECT="/tmp/dev-workspace/$PROJECT_NAME"
SYNC_FILE="$HOME/.dev-ram-sync"
BACKUP_DIR="$HOME/.dev-ram-backups"

# Validate project path
if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ Error: Project path does not exist: $PROJECT_PATH"
    exit 1
fi

# Check if project is already synced
if [ -d "$RAM_PROJECT" ] && [ "$FORCE_SYNC" != "--force" ]; then
    echo "⚠️  Project $PROJECT_NAME already exists in RAM"
    echo "   RAM: $RAM_PROJECT"
    echo "   Use --force to overwrite or 'dev-sync-to-disk $PROJECT_NAME' first"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup if RAM project exists
if [ -d "$RAM_PROJECT" ]; then
    BACKUP_NAME="${PROJECT_NAME}_$(date +%Y%m%d_%H%M%S)"
    echo "💾 Creating backup: $BACKUP_NAME"
    cp -r "$RAM_PROJECT" "$BACKUP_DIR/$BACKUP_NAME"
fi

# Remove existing sync record for this project
if [ -f "$SYNC_FILE" ]; then
    grep -v "|$RAM_PROJECT$" "$SYNC_FILE" > "$SYNC_FILE.tmp" || true
    mv "$SYNC_FILE.tmp" "$SYNC_FILE"
fi

# Create new sync record
echo "$PROJECT_PATH|$RAM_PROJECT|$(date +%s)" >> "$SYNC_FILE"

# Sync to RAM with progress and exclusions
echo "📦 Syncing $PROJECT_NAME to RAM..."
rsync -av --progress --delete \
    --exclude='.git/objects/pack/*.pack' \
    --exclude='node_modules/' \
    --exclude='target/debug/' \
    --exclude='target/release/' \
    --exclude='build/' \
    --exclude='dist/' \
    --exclude='*.log' \
    "$PROJECT_PATH/" "$RAM_PROJECT/"

# Set proper permissions
chmod -R u+w "$RAM_PROJECT"

echo "✅ Project synced to: $RAM_PROJECT"
echo "💡 Use 'dev-sync-to-disk $PROJECT_NAME' to save changes back"
echo "💡 Use 'cd $RAM_PROJECT' to work in RAM"
echo "📊 RAM usage: $(df -h /tmp/dev-workspace | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
EOF

    cat > "$HOME/bin/dev-sync-to-disk" << 'EOF'
#!/bin/bash
# Enhanced sync RAM project back to disk with conflict detection

set -e

PROJECT_NAME="$1"
SYNC_FILE="$HOME/.dev-ram-sync"
BACKUP_DIR="$HOME/.dev-ram-backups"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: dev-sync-to-disk <project-name> [--dry-run]"
    echo ""
    echo "Available RAM projects:"
    if [ -f "$SYNC_FILE" ]; then
        while IFS='|' read -r disk_path ram_path sync_time; do
            project=$(basename "$disk_path")
            if [ -d "$ram_path" ]; then
                last_modified=$(stat -c %Y "$ram_path" 2>/dev/null || echo "0")
                if [ "$last_modified" -gt "$sync_time" ]; then
                    echo "  📝 $project (modified)"
                else
                    echo "  ✅ $project (unchanged)"
                fi
            else
                echo "  ❌ $project (missing from RAM)"
            fi
        done < "$SYNC_FILE"
    else
        echo "  No projects synced to RAM"
    fi
    exit 1
fi

# Find project paths
PROJECT_LINE=$(grep "/$PROJECT_NAME$" "$SYNC_FILE" | head -1)
if [ -z "$PROJECT_LINE" ]; then
    echo "❌ Project $PROJECT_NAME not found in sync records"
    echo "Available projects:"
    grep -o '[^|]*$' "$SYNC_FILE" 2>/dev/null | xargs -I {} basename {} || echo "  None"
    exit 1
fi

DISK_PATH=$(echo "$PROJECT_LINE" | cut -d'|' -f1)
RAM_PATH=$(echo "$PROJECT_LINE" | cut -d'|' -f2)
SYNC_TIME=$(echo "$PROJECT_LINE" | cut -d'|' -f3)

# Validate paths
if [ ! -d "$RAM_PATH" ]; then
    echo "❌ RAM project not found: $RAM_PATH"
    exit 1
fi

if [ ! -d "$DISK_PATH" ]; then
    echo "❌ Disk project not found: $DISK_PATH"
    echo "Creating directory: $DISK_PATH"
    mkdir -p "$DISK_PATH"
fi

# Check for conflicts (disk changes since sync)
DISK_MODIFIED=$(find "$DISK_PATH" -newer "$DISK_PATH" -type f 2>/dev/null | wc -l)
if [ "$DISK_MODIFIED" -gt 0 ] && [ -n "$SYNC_TIME" ]; then
    DISK_NEWEST=$(find "$DISK_PATH" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
    if [ "$DISK_NEWEST" -gt "$SYNC_TIME" ]; then
        echo "⚠️  WARNING: Disk version has been modified since sync!"
        echo "   This sync will overwrite disk changes."
        echo "   Disk path: $DISK_PATH"
        echo "   RAM path: $RAM_PATH"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Sync cancelled"
            exit 1
        fi

        # Create backup of disk version
        BACKUP_NAME="${PROJECT_NAME}_disk_$(date +%Y%m%d_%H%M%S)"
        echo "💾 Creating backup of disk version: $BACKUP_NAME"
        mkdir -p "$BACKUP_DIR"
        cp -r "$DISK_PATH" "$BACKUP_DIR/$BACKUP_NAME"
    fi
fi

# Dry run option
if [ "$2" = "--dry-run" ]; then
    echo "🔍 Dry run - changes that would be made:"
    rsync -av --dry-run --delete "$RAM_PATH/" "$DISK_PATH/"
    exit 0
fi

echo "💾 Syncing $PROJECT_NAME back to disk..."
rsync -av --progress --delete "$RAM_PATH/" "$DISK_PATH/"

# Update sync timestamp
sed -i "s|$PROJECT_LINE|$DISK_PATH|$RAM_PATH|$(date +%s)|" "$SYNC_FILE"

echo "✅ Changes saved to: $DISK_PATH"
echo "📊 Disk usage: $(du -sh "$DISK_PATH" | cut -f1)"
EOF

    chmod +x "$HOME/bin/dev-sync-to-ram"
    chmod +x "$HOME/bin/dev-sync-to-disk"
}

# 3. Optimize Docker for development
optimize_docker() {
    echo "🐳 Optimizing Docker settings..."
    
    # Create Docker daemon config for performance
    DOCKER_CONFIG="/etc/docker/daemon.json"
    
    if [ -f "$DOCKER_CONFIG" ]; then
        sudo cp "$DOCKER_CONFIG" "$DOCKER_CONFIG.backup"
    fi
    
    sudo tee "$DOCKER_CONFIG" > /dev/null << EOF
{
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-runtime": "runc",
    "runtimes": {
        "runc": {
            "path": "runc"
        }
    },
    "data-root": "/tmp/build-cache/docker",
    "tmp-root": "/tmp/build-cache/docker-tmp"
}
EOF
    
    echo "✅ Docker optimized for tmpfs storage"
    echo "⚠️  Note: Docker data will be lost on reboot - backup important images!"
}

# 4. Setup build cache optimizations
setup_build_cache() {
    echo "🔧 Setting up build cache optimizations..."
    
    # Create cache directories
    mkdir -p "$BUILD_TMPFS"/{npm,cargo,go,maven,gradle,ccache}
    
    # Add environment variables for build caches
    cat >> "$HOME/.bashrc" << 'EOF'

# Development Performance Optimizations
export NPM_CONFIG_CACHE="/tmp/build-cache/npm"
export CARGO_HOME="/tmp/build-cache/cargo"
export GOCACHE="/tmp/build-cache/go"
export MAVEN_CACHE="/tmp/build-cache/maven"
export GRADLE_USER_HOME="/tmp/build-cache/gradle"
export CCACHE_DIR="/tmp/build-cache/ccache"

# Aliases for development
alias dev-ram='cd /tmp/dev-workspace'
alias dev-build='cd /tmp/build-cache'
EOF
    
    echo "✅ Build caches configured for RAM storage"
}

# 5. Memory and swap optimizations
optimize_memory() {
    echo "🧠 Optimizing memory settings..."
    
    # Optimize swappiness for development (even lower)
    echo 'vm.swappiness=1' | sudo tee -a /etc/sysctl.conf
    
    # Optimize dirty page handling for SSDs
    echo 'vm.dirty_ratio=15' | sudo tee -a /etc/sysctl.conf
    echo 'vm.dirty_background_ratio=5' | sudo tee -a /etc/sysctl.conf
    echo 'vm.dirty_expire_centisecs=12000' | sudo tee -a /etc/sysctl.conf
    echo 'vm.dirty_writeback_centisecs=1500' | sudo tee -a /etc/sysctl.conf
    
    # Apply immediately
    sudo sysctl -p
    
    echo "✅ Memory settings optimized"
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo "❌ Don't run this script as root"
        exit 1
    fi
    
    # Check available memory
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
    if [ "$AVAILABLE_MEM" -lt 15 ]; then
        echo "⚠️  Warning: Low available memory ($AVAILABLE_MEM GB). Consider closing applications."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Create bin directory if it doesn't exist
    mkdir -p "$HOME/bin"
    
    # Add bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    
    create_dev_tmpfs
    create_sync_scripts
    optimize_docker
    setup_build_cache
    optimize_memory
    
    echo ""
    echo "🎉 Development performance optimization complete!"
    echo ""
    echo "📋 Usage:"
    echo "  dev-sync-to-ram /path/to/project  # Copy project to RAM"
    echo "  dev-sync-to-disk project-name     # Save changes back"
    echo "  dev-ram                          # Go to RAM workspace"
    echo "  dev-build                        # Go to build cache"
    echo ""
    echo "⚠️  Remember:"
    echo "  - RAM data is lost on reboot"
    echo "  - Always sync back important changes"
    echo "  - Reboot or source ~/.bashrc for env vars"
}

main "$@"