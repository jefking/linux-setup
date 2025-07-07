#!/bin/bash
# Development Tools Installation Script

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Check current git repositories
check_current_repos() {
    log "Checking for existing git repositories to clone..."
    
    REPO_LIST_FILE="/tmp/git-repos-to-clone.txt"
    
    # Check if Documents/git exists
    if [ -d "$HOME/Documents/git" ]; then
        log "Found existing git folder at $HOME/Documents/git"
        
        # List all git repositories
        find "$HOME/Documents/git" -type d -name ".git" | while read -r gitdir; do
            repo_path=$(dirname "$gitdir")
            repo_name=$(basename "$repo_path")
            
            # Try to get origin URL
            if cd "$repo_path" && git remote get-url origin 2>/dev/null; then
                origin_url=$(git remote get-url origin)
                echo "$repo_name|$origin_url" >> "$REPO_LIST_FILE"
                log "Found repo: $repo_name -> $origin_url"
            fi
        done
        
        if [ -f "$REPO_LIST_FILE" ]; then
            log "Saved $(wc -l < "$REPO_LIST_FILE") repositories to clone list"
        fi
    else
        log "No existing git folder found at $HOME/Documents/git"
    fi
}

# Install GitHub CLI
install_github_cli() {
    log "Installing GitHub CLI..."
    
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        sudo dnf install -y gh
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -S --noconfirm github-cli
    else
        error "Unsupported package manager for GitHub CLI installation"
    fi
    
    log "GitHub CLI installed successfully"
}

# Install Atlassian Go CLI
install_atlassian_cli() {
    log "Installing Atlassian Go CLI..."
    
    # Get the latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/ankitpokhrel/jira-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [ -z "$LATEST_VERSION" ]; then
        error "Could not determine latest Atlassian CLI version"
    fi
    
    log "Installing Atlassian CLI version $LATEST_VERSION..."
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH_SUFFIX="linux_x86_64"
            ;;
        aarch64)
            ARCH_SUFFIX="linux_arm64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
    
    # Download and install
    DOWNLOAD_URL="https://github.com/ankitpokhrel/jira-cli/releases/download/v${LATEST_VERSION}/jira_${LATEST_VERSION}_${ARCH_SUFFIX}.tar.gz"
    
    wget -q "$DOWNLOAD_URL" -O /tmp/jira-cli.tar.gz
    tar -xzf /tmp/jira-cli.tar.gz -C /tmp
    sudo mv /tmp/bin/jira /usr/local/bin/
    sudo chmod +x /usr/local/bin/jira
    rm -rf /tmp/jira-cli.tar.gz /tmp/bin
    
    log "Atlassian CLI (jira) installed successfully"
}

# Setup git folder structure
setup_git_folder() {
    log "Setting up git folder structure..."
    
    # Create main git folder
    mkdir -p "$HOME/git"
    
    # Create category folders
    mkdir -p "$HOME/git"/{personal,work,forks,experiments}
    
    log "Created git folder structure at $HOME/git"
}

# Clone repositories
clone_repositories() {
    log "Cloning repositories..."
    
    REPO_LIST_FILE="/tmp/git-repos-to-clone.txt"
    
    if [ ! -f "$REPO_LIST_FILE" ]; then
        log "No repository list found. Skipping cloning."
        return
    fi
    
    # Ask user if they want to clone repos
    echo ""
    echo "Found $(wc -l < "$REPO_LIST_FILE") repositories to clone."
    read -p "Would you like to clone them to ~/git? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping repository cloning"
        return
    fi
    
    # Clone each repository
    while IFS='|' read -r repo_name repo_url; do
        if [ -n "$repo_url" ]; then
            # Determine target folder based on URL
            if [[ "$repo_url" == *"github.com"* ]]; then
                if [[ "$repo_url" == *"$USER"* ]]; then
                    target_dir="$HOME/git/personal/$repo_name"
                else
                    target_dir="$HOME/git/forks/$repo_name"
                fi
            else
                target_dir="$HOME/git/work/$repo_name"
            fi
            
            if [ ! -d "$target_dir" ]; then
                log "Cloning $repo_name to $target_dir..."
                git clone "$repo_url" "$target_dir"
            else
                log "Repository $repo_name already exists at $target_dir"
            fi
        fi
    done < "$REPO_LIST_FILE"
    
    rm -f "$REPO_LIST_FILE"
}

# Install other development tools
install_other_tools() {
    log "Installing additional development tools..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y \
            tmux \
            jq \
            httpie \
            tree \
            ncdu \
            fzf \
            ripgrep \
            fd-find \
            bat \
            delta
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y \
            tmux \
            jq \
            httpie \
            tree \
            ncdu \
            fzf \
            ripgrep \
            fd-find \
            bat \
            git-delta
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm \
            tmux \
            jq \
            httpie \
            tree \
            ncdu \
            fzf \
            ripgrep \
            fd \
            bat \
            git-delta
    fi
}

# Setup git configuration
setup_git_config() {
    log "Setting up git configuration..."
    
    # Only set if not already configured
    if [ -z "$(git config --global user.name)" ]; then
        echo "Enter your git user name:"
        read -r git_name
        git config --global user.name "$git_name"
    fi
    
    if [ -z "$(git config --global user.email)" ]; then
        echo "Enter your git email:"
        read -r git_email
        git config --global user.email "$git_email"
    fi
    
    # Set useful git aliases
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.lg "log --oneline --graph --all"
    
    # Set default branch to main
    git config --global init.defaultBranch main
    
    # Enable git rerere
    git config --global rerere.enabled true
    
    log "Git configuration complete"
}

main() {
    log "Starting development tools installation..."
    
    # Check for existing repos first
    check_current_repos
    
    # Install tools
    install_github_cli
    install_atlassian_cli
    install_other_tools
    
    # Setup git
    setup_git_folder
    setup_git_config
    clone_repositories
    
    echo ""
    log "Development tools installation complete!"
    echo ""
    echo "Tools installed:"
    echo "✓ GitHub CLI (gh)"
    echo "✓ Atlassian CLI (jira)"
    echo "✓ tmux, jq, httpie, tree, ncdu"
    echo "✓ fzf, ripgrep, fd, bat, delta"
    echo ""
    echo "Git setup:"
    echo "✓ Git folder created at ~/git"
    echo "✓ Git aliases configured"
    echo "✓ Repositories cloned (if any)"
    echo ""
    echo "Next steps:"
    echo "1. Run 'gh auth login' to authenticate with GitHub"
    echo "2. Run 'jira init' to configure Atlassian CLI"
    echo ""
}

main "$@"