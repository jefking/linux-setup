#!/bin/bash
# Docker Installation Script with Performance Optimizations

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        error "Cannot detect Linux distribution"
    fi
}

remove_old_docker() {
    log "Removing old Docker installations if any..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    elif command -v dnf &> /dev/null; then
        sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    elif command -v pacman &> /dev/null; then
        sudo pacman -Rns --noconfirm docker 2>/dev/null || true
    fi
}

install_docker_debian() {
    log "Installing Docker on Debian/Ubuntu..."
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add the repository to Apt sources
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_fedora() {
    log "Installing Docker on Fedora..."
    
    # Add Docker repository
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    
    # Install Docker
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_arch() {
    log "Installing Docker on Arch Linux..."
    
    # Install Docker
    sudo pacman -S --noconfirm docker docker-compose docker-buildx
}

configure_docker() {
    log "Configuring Docker for optimal performance..."
    
    # Create Docker config directory
    sudo mkdir -p /etc/docker
    
    # Create optimized daemon.json
    sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
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
    "features": {
        "buildkit": true
    },
    "metrics-addr": "127.0.0.1:9323",
    "experimental": false,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log "Docker configured successfully"
}

setup_docker_compose_alias() {
    log "Setting up Docker Compose v2 alias..."
    
    # Add alias for docker-compose (v2 uses 'docker compose')
    if ! grep -q "alias docker-compose='docker compose'" ~/.bashrc; then
        echo "alias docker-compose='docker compose'" >> ~/.bashrc
    fi
}

install_docker_tools() {
    log "Installing additional Docker tools..."
    
    # Install lazydocker (TUI for Docker)
    if command -v go &> /dev/null; then
        go install github.com/jesseduffield/lazydocker@latest
    else
        log "Go not installed, skipping lazydocker installation"
    fi
    
    # Install dive (Docker image explorer)
    if command -v wget &> /dev/null; then
        DIVE_VERSION=$(curl -s "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
        wget -q "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.tar.gz" -O /tmp/dive.tar.gz
        tar -xzf /tmp/dive.tar.gz -C /tmp
        sudo mv /tmp/dive /usr/local/bin/
        rm /tmp/dive.tar.gz
        log "Installed dive v${DIVE_VERSION}"
    fi
}

verify_installation() {
    log "Verifying Docker installation..."
    
    if docker --version &> /dev/null; then
        log "Docker installed: $(docker --version)"
    else
        error "Docker installation failed"
    fi
    
    if docker compose version &> /dev/null; then
        log "Docker Compose installed: $(docker compose version)"
    else
        error "Docker Compose installation failed"
    fi
    
    # Test Docker with hello-world
    log "Testing Docker installation..."
    if sudo docker run --rm hello-world &> /dev/null; then
        log "Docker is working correctly!"
    else
        error "Docker test failed"
    fi
}

main() {
    log "Starting Docker installation..."
    
    detect_distro
    remove_old_docker
    
    case $DISTRO in
        ubuntu|debian)
            install_docker_debian
            ;;
        fedora)
            install_docker_fedora
            ;;
        arch|manjaro)
            install_docker_arch
            ;;
        *)
            error "Unsupported distribution: $DISTRO"
            ;;
    esac
    
    configure_docker
    setup_docker_compose_alias
    install_docker_tools
    verify_installation
    
    echo ""
    log "Docker installation complete!"
    echo ""
    echo "IMPORTANT: You need to log out and back in for group changes to take effect"
    echo "Or run: newgrp docker"
    echo ""
    echo "Useful Docker commands:"
    echo "  docker ps                    # List running containers"
    echo "  docker images               # List images"
    echo "  docker compose up -d        # Start services in background"
    echo "  docker system prune -a      # Clean up unused resources"
    echo ""
}

main "$@"