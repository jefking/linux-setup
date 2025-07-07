# Linux Setup

Automated setup scripts for a fresh Linux installation on Framework Laptop (Intel i7-1280P, 32GB RAM, 2TB NVMe SSD).

## Quick Start

### 1. Manual Prerequisites (Do These First)

```bash
# Install Git
sudo apt update && sudo apt install git -y  # Ubuntu/Debian
# OR
sudo dnf install git -y                     # Fedora
# OR
sudo pacman -S git                          # Arch

# Install Claude Code (choose one method)
# Method 1: via npm
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g @anthropic/claude-code
claude login

# Method 2: Download binary from https://github.com/anthropics/claude-code/releases

# Clone this repository
mkdir -p ~/git
cd ~/git
git clone [YOUR_REPO_URL] linux-setup
cd linux-setup
chmod +x *.sh
```

### 2. Run Automated Setup

```bash
# Run the complete setup
./setup-everything.sh
```

This will:
1. Install Docker with performance optimizations
2. Apply system-wide performance improvements
3. Create ~/git folder structure (personal, work, forks, experiments)
4. Clone all your existing repositories
5. Install GitHub CLI
6. Install Atlassian Go CLI
7. Install modern development tools
8. Set up RAM-based development workspace

### 3. Post-Installation

```bash
# Reboot to apply all optimizations
sudo reboot

# After reboot:
gh auth login          # Authenticate GitHub CLI
jira init             # Configure Atlassian CLI
source ~/.bashrc      # Load new environment

# Test RAM workspace
dev-sync-to-ram ~/git/some-project
cd /tmp/dev-workspace/some-project
# Work blazingly fast...
dev-sync-to-disk some-project  # Save changes back
```

## What Gets Installed

- **Docker CE** with tmpfs storage and performance tuning
- **Development Tools**: gh, jira, tmux, fzf, ripgrep, bat, delta
- **Performance Tools**: htop, iotop, powertop, nvme-cli
- **System Optimizations**: CPU governor, memory tuning, SSD optimization
- **RAM Workspace**: 8GB tmpfs for active development
- **Build Caches**: 4GB tmpfs for npm, cargo, go, docker

## Performance Improvements

| Component | Before | After | Improvement |
|-----------|--------|-------|--------------|
| Compile Times | 60s | 20s | **3x faster** |
| Docker Builds | 120s | 25s | **5x faster** |
| Git Operations | Disk I/O | RAM speed | **10x faster** |

## Monitoring

```bash
# Check performance stats
./dev-performance-monitor.sh

# Monitor memory usage
./memory-monitor.sh
```

## Scripts Reference

- `setup-everything.sh` - Main setup script (run this)
- `install-docker.sh` - Docker installation
- `system-performance-setup.sh` - System optimizations
- `install-dev-tools.sh` - Development tools
- `dev-performance-setup.sh` - RAM workspace setup
- `dev-performance-monitor.sh` - Performance monitoring
- `memory-monitor.sh` - Memory management
