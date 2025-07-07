#!/bin/bash
# Framework Laptop Development Performance Optimization Script
# For Intel i7-1280P with 32GB RAM

set -e

echo "🚀 Setting up development performance optimizations..."

# Create development tmpfs directories
TMPFS_SIZE="8G"  # Adjust based on your needs
DEV_TMPFS="/tmp/dev-workspace"
BUILD_TMPFS="/tmp/build-cache"

# 1. Create smart tmpfs mounts for development
create_dev_tmpfs() {
    echo "📁 Creating development tmpfs directories..."
    
    # Development workspace (for active projects)
    sudo mkdir -p "$DEV_TMPFS"
    sudo mkdir -p "$BUILD_TMPFS"
    
    # Mount tmpfs with optimal settings for development
    if ! mountpoint -q "$DEV_TMPFS"; then
        sudo mount -t tmpfs -o size=$TMPFS_SIZE,mode=1777,noatime,nodiratime tmpfs "$DEV_TMPFS"
        echo "✅ Mounted dev workspace tmpfs ($TMPFS_SIZE)"
    fi
    
    if ! mountpoint -q "$BUILD_TMPFS"; then
        sudo mount -t tmpfs -o size=4G,mode=1777,noatime,nodiratime tmpfs "$BUILD_TMPFS"
        echo "✅ Mounted build cache tmpfs (4G)"
    fi
    
    # Set ownership
    sudo chown $USER:$USER "$DEV_TMPFS" "$BUILD_TMPFS"
}

# 2. Create project sync scripts
create_sync_scripts() {
    echo "🔄 Creating project sync scripts..."
    
    cat > "$HOME/bin/dev-sync-to-ram" << 'EOF'
#!/bin/bash
# Sync project to RAM for fast development

PROJECT_PATH="$1"
if [ -z "$PROJECT_PATH" ]; then
    echo "Usage: dev-sync-to-ram /path/to/project"
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")
RAM_PROJECT="/tmp/dev-workspace/$PROJECT_NAME"
SYNC_FILE="$HOME/.dev-ram-sync"

# Create sync record
echo "$PROJECT_PATH|$RAM_PROJECT" >> "$SYNC_FILE"

# Sync to RAM
echo "📦 Syncing $PROJECT_NAME to RAM..."
rsync -av --delete "$PROJECT_PATH/" "$RAM_PROJECT/"

echo "✅ Project synced to: $RAM_PROJECT"
echo "💡 Use 'dev-sync-to-disk' to save changes back"
echo "💡 Use 'cd $RAM_PROJECT' to work in RAM"
EOF

    cat > "$HOME/bin/dev-sync-to-disk" << 'EOF'
#!/bin/bash
# Sync RAM project back to disk

PROJECT_NAME="$1"
SYNC_FILE="$HOME/.dev-ram-sync"

if [ -z "$PROJECT_NAME" ]; then
    echo "Available RAM projects:"
    if [ -f "$SYNC_FILE" ]; then
        cat "$SYNC_FILE" | cut -d'|' -f1 | xargs -I {} basename {}
    fi
    exit 1
fi

# Find project paths
DISK_PATH=$(grep "/$PROJECT_NAME$" "$SYNC_FILE" | head -1 | cut -d'|' -f1)
RAM_PATH=$(grep "/$PROJECT_NAME$" "$SYNC_FILE" | head -1 | cut -d'|' -f2)

if [ -z "$DISK_PATH" ] || [ -z "$RAM_PATH" ]; then
    echo "❌ Project $PROJECT_NAME not found in sync records"
    exit 1
fi

echo "💾 Syncing $PROJECT_NAME back to disk..."
rsync -av --delete "$RAM_PATH/" "$DISK_PATH/"
echo "✅ Changes saved to: $DISK_PATH"
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