#!/bin/bash
# Complete Setup Script for Debian 12 on Framework Laptop
# Intel i7-1280P | 32GB RAM | 2TB NVMe SSD

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/setup-everything.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_banner() {
    clear
    echo "============================================="
    echo "   Framework Laptop Debian 12 Setup"
    echo "============================================="
    echo ""
    echo "Intel i7-1280P | 32GB RAM | 2TB NVMe SSD"
    echo ""
    echo "This script will:"
    echo "1. Install Docker CE with Debian optimizations"
    echo "2. Apply Framework laptop performance tuning"
    echo "3. Create organized git folder structure"
    echo "4. Clone your existing repositories"
    echo "5. Install GitHub CLI (gh)"
    echo "6. Install Atlassian Go CLI (jira)"
    echo "7. Install modern development tools"
    echo "8. Set up 8GB RAM-based development workspace"
    echo ""
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install git first."
    fi
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
    fi
    
    log "Prerequisites check passed"
}

update_system() {
    log "Updating system packages..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get upgrade -y
    elif command -v dnf &> /dev/null; then
        sudo dnf update -y
    elif command -v pacman &> /dev/null; then
        sudo pacman -Syu --noconfirm
    fi
}

main() {
    print_banner
    
    # Confirm before proceeding
    echo "This will set up your entire development environment."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
    
    log "Starting complete setup..."
    
    # Run checks
    check_prerequisites
    update_system
    
    # Step 1: Install Docker
    log "Step 1/8: Installing Docker..."
    if [ -f "$SCRIPT_DIR/install-docker.sh" ]; then
        bash "$SCRIPT_DIR/install-docker.sh"
    else
        error "install-docker.sh not found"
    fi
    
    # Step 2: System Performance Optimizations
    log "Step 2/8: Applying system performance optimizations..."
    if [ -f "$SCRIPT_DIR/system-performance-setup.sh" ]; then
        bash "$SCRIPT_DIR/system-performance-setup.sh"
    else
        error "system-performance-setup.sh not found"
    fi
    
    # Step 3-7: Development Tools and Git Setup
    log "Step 3-7/8: Installing development tools and setting up git..."
    if [ -f "$SCRIPT_DIR/install-dev-tools.sh" ]; then
        bash "$SCRIPT_DIR/install-dev-tools.sh"
    else
        error "install-dev-tools.sh not found"
    fi
    
    # Step 8: Development Performance Setup
    log "Step 8/8: Setting up RAM-based development environment..."
    if [ -f "$SCRIPT_DIR/dev-performance-setup.sh" ]; then
        bash "$SCRIPT_DIR/dev-performance-setup.sh"
    else
        error "dev-performance-setup.sh not found"
    fi
    
    # Create shortcuts script
    create_shortcuts
    
    # Final summary
    print_summary
}

create_shortcuts() {
    log "Creating useful shortcuts..."
    
    # Create a quick reference script
    cat > "$HOME/bin/dev-help" << 'EOF'
#!/bin/bash
echo "Development Environment Commands:"
echo "================================"
echo ""
echo "RAM Workspace:"
echo "  dev-sync-to-ram <project>  - Copy project to RAM"
echo "  dev-sync-to-disk <project> - Save changes back to disk"
echo "  dev-ram                    - Go to RAM workspace"
echo "  dev-build                  - Go to build cache"
echo ""
echo "Monitoring:"
echo "  dev-performance-monitor.sh - Check system performance"
echo "  memory-monitor.sh         - Monitor memory usage"
echo ""
echo "Docker:"
echo "  docker ps                 - List running containers"
echo "  docker compose up -d      - Start services"
echo "  lazydocker               - Docker TUI (if installed)"
echo ""
echo "Git:"
echo "  gh pr create             - Create pull request"
echo "  gh repo clone            - Clone repository"
echo ""
echo "Atlassian:"
echo "  jira issue list          - List issues"
echo "  jira sprint list         - List sprints"
echo ""
EOF
    chmod +x "$HOME/bin/dev-help"
}

print_summary() {
    echo ""
    echo "============================================="
    echo "   Setup Complete! 🎉"
    echo "============================================="
    echo ""
    log "All installations completed successfully!"
    echo ""
    echo "✅ Installed:"
    echo "   - Docker CE with performance optimizations"
    echo "   - GitHub CLI (gh)"
    echo "   - Atlassian Go CLI (jira)"
    echo "   - Development tools (tmux, fzf, ripgrep, etc.)"
    echo "   - System performance optimizations"
    echo "   - RAM-based development workspace"
    echo ""
    echo "📁 Created:"
    echo "   - ~/git folder structure"
    echo "   - Cloned existing repositories (if any)"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Reboot your system: sudo reboot"
    echo "   2. After reboot:"
    echo "      - Run: gh auth login"
    echo "      - Run: jira init"
    echo "      - Run: source ~/.bashrc"
    echo "   3. Type 'dev-help' for command reference"
    echo ""
    echo "📊 Monitor performance with:"
    echo "   ./dev-performance-monitor.sh"
    echo ""
    echo "📝 Full log available at: $LOG_FILE"
    echo ""
    
    read -p "Would you like to reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system..."
        sudo reboot
    else
        echo ""
        echo "Remember to reboot soon to apply all optimizations!"
        echo "Run: sudo reboot"
    fi
}

# Run main function
main "$@"