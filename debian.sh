#!/bin/bash

# Debian Tweaks Installation Script
# Corrected, Optimized, and Modified Version
# Based on: https://github.com/tonybeyond/debiantweaks/blob/main/debian-install-2025.sh
# Changes:
# - Replaced Netbird with Tailscale
# - Removed Snap usage (no snapd, Postman)
# - Installs Obsidian via latest .deb from GitHub releases
# - Installs latest stable Neovim via pre-built binary from GitHub releases
# - Adds Flatpak support and Flathub remote
# - Adds Brave Browser installation
# - Adds Oh My Zsh and selected plugins installation (user configuration required)
# - Adds Debian Backports repository
# - Adds Liquorix Kernel repository and installs the kernel
# - Improved error handling, package management, and security practices

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipeline's exit status is the last command to exit with non-zero status.
set -euo pipefail

# --- Configuration ---
readonly KEYRINGS_DIR="/etc/apt/keyrings"
readonly SOURCES_DIR="/etc/apt/sources.list.d"
readonly NVIM_INSTALL_DIR="/opt/nvim-linux64"
readonly NVIM_SYMLINK="/usr/local/bin/nvim"
# Define Oh My Zsh custom dir for clarity (use $HOME expansion at runtime)
readonly ZSH_CUSTOM_DIR_VARNAME="\$HOME/.oh-my-zsh/custom"

# --- Helper Functions ---
log() {
    echo ">>> [INFO] $1"
}

warning() {
    echo ">>> [WARN] $1"
}

error() {
    echo ">>> [ERROR] $1" >&2
    exit 1
}

# Function to install packages if they are not already installed
install_packages() {
    # Check if any arguments were passed
    if [ $# -eq 0 ]; then
        log "No packages specified for installation."
        return 0
    fi
    log "Installing packages: $*"
    sudo apt install -y "$@" || error "Failed to install packages: $*"
}

# Function to add a PPA repository
add_ppa() {
    log "Adding PPA: $1"
    sudo add-apt-repository -y "$1" || error "Failed to add PPA: $1"
}

# Function to add GPG key and repository using the modern method (/etc/apt/keyrings)
add_key_repo() {
    local name="$1"
    local key_url="$2"
    local repo_string="$3"
    local arch="${4:-amd64}" # Default architecture to amd64 if not provided

    log "Adding GPG key for $name from $key_url"
    local keyring_path="$KEYRINGS_DIR/${name}-keyring.gpg"
    # Download and dearmor the key
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path" || error "Failed to download or dearmor GPG key for $name from $key_url"
    sudo chmod a+r "$keyring_path"

    log "Adding repository for $name: $repo_string"
    local repo_list_file="$SOURCES_DIR/${name}.list"
    echo "deb [arch=$arch signed-by=$keyring_path] $repo_string" | sudo tee "$repo_list_file" > /dev/null || error "Failed to add repository for $name"
}

# Function to get latest GitHub release asset URL
# $1: GitHub repo (e.g., obsidianmd/obsidian-releases)
# $2: Asset name pattern (e.g., _amd64.deb$)
get_latest_github_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    log "Fetching latest release info from $api_url for pattern $pattern"
    local download_url
    # Increased robustness for rate limiting / errors from curl/jq
    if ! download_url=$(curl -fsSL "$api_url" | jq -r --arg PATTERN "$pattern" '.assets[] | select(.name | test($PATTERN)) | .browser_download_url' | head -n 1); then
         error "Failed to fetch or parse release info from $api_url. Check connection or API rate limits."
    fi

    if [[ -z "$download_url" ]]; then
        error "Could not find asset matching '$pattern' for latest release of $repo."
    fi
    echo "$download_url"
}

# Function to check/install prerequisite commands
check_install_command() {
    local cmd="$1"
    local pkg="${2:-$1}" # Package name defaults to command name
    if ! command -v "$cmd" &> /dev/null; then
        log "$cmd not found. Installing $pkg..."
        # Ensure apt update has run at least once before trying to install
        if ! sudo apt-get update &>/dev/null; then
             log "Running initial apt update to install prerequisites..."
             sudo apt-get update || error "Initial apt update failed."
        fi
        sudo apt-get install -y "$pkg" || error "Failed to install $pkg"
    fi
}

# Function to install Oh My Zsh non-interactively
install_oh_my_zsh() {
     if [ -d "$HOME/.oh-my-zsh" ]; then
        log "Oh My Zsh already installed in $HOME/.oh-my-zsh. Skipping installation."
        return 0 # Indicate success/already installed
    fi

    if ! command -v zsh &> /dev/null; then
        warning "Zsh command not found. Cannot install Oh My Zsh."
        return 1
    fi
    if ! command -v git &> /dev/null; then
        warning "git command not found. Cannot install Oh My Zsh."
        return 1
    fi

    log "Installing Oh My Zsh (non-interactive)..."
    # Run the installer script non-interactively (won't change shell or run zsh)
    # Pass "" --unattended to the sh -c script
    if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
        log "Oh My Zsh installation script finished."
        # Verify installation directory
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
             warning "Oh My Zsh install script ran, but $HOME/.oh-my-zsh directory not found!"
             return 1
        fi
        # Check if .zshrc was created (it should be by the unattended install)
        if [ ! -f "$HOME/.zshrc" ]; then
            warning "Oh My Zsh installed, but ~/.zshrc was not created. You may need to configure it manually."
            # Consider copying template: cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
        fi
        return 0
    else
        warning "Oh My Zsh installation failed."
        return 1
    fi
}

# Function to install a Zsh plugin
# $1: Plugin name (directory name)
# $2: Git repository URL
# $3: Optional clone arguments (e.g., --depth 1)
install_zsh_plugin() {
    local name="$1"
    local url="$2"
    local clone_args="${3:-}"
    # Expand $HOME when the function is called
    local custom_plugins_dir
    custom_plugins_dir=$(eval echo "$ZSH_CUSTOM_DIR_VARNAME/plugins") # Use eval to expand ~ or $HOME correctly
    local target_dir="$custom_plugins_dir/$name"

    # Ensure OMZ custom directory structure exists
    mkdir -p "$custom_plugins_dir" || error "Failed to create Zsh custom plugins directory: $custom_plugins_dir"

    if [ -d "$target_dir" ]; then
        log "Zsh plugin '$name' already exists in $target_dir. Skipping clone."
    else
        log "Installing zsh plugin '$name' from $url..."
        if git clone $clone_args "$url" "$target_dir"; then
             log "Plugin '$name' installed successfully."
        else
             warning "Failed to clone zsh plugin '$name'."
        fi
    fi
}


# --- Sanity Checks ---
if [[ "$EUID" -eq 0 ]]; then
   error "This script should not be run as root. Run as a regular user with sudo privileges."
fi

if ! command -v sudo &> /dev/null; then
    error "sudo command not found. Please install sudo and configure it for your user."
fi

# Check essential commands early, install if missing
check_install_command "curl"
check_install_command "gpg"
check_install_command "jq"
check_install_command "wget"
check_install_command "git" # Needed for Zsh plugins
check_install_command "lsb-release" # Needed for backports codename

# --- Main Script ---
log "Starting Debian Tweaks installation script..."

# Create directories for keys and sources if they don't exist
log "Ensuring APT configuration directories exist..."
sudo install -m 0755 -d "$KEYRINGS_DIR"
sudo install -m 0755 -d "$SOURCES_DIR"
# Also ensure /usr/share/keyrings exists for Brave
sudo install -d -m 0755 /usr/share/keyrings

# --- Configure APT Repositories ---
log "Configuring APT repositories..."

# Enable Debian Backports
debian_codename=$(lsb_release -cs)
log "Detected Debian Codename: $debian_codename"
log "Enabling Debian Backports repository..."
echo "deb http://deb.debian.org/debian ${debian_codename}-backports main contrib non-free non-free-firmware" | sudo tee "/etc/apt/sources.list.d/backports.list" > /dev/null || error "Failed to add Backports repository"
log "Backports enabled. Install packages using: sudo apt install -t ${debian_codename}-backports <package>"

# Add PPA for LibreOffice
add_ppa "ppa:libreoffice/ppa"

# Add repository for Google Chrome
add_key_repo "google-chrome" \
    "https://dl.google.com/linux/linux_signing_key.pub" \
    "http://dl.google.com/linux/chrome/deb/ stable main"

# Add repository for VS Code
add_key_repo "vscode" \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "https://packages.microsoft.com/repos/code stable main"

# Add repository for Brave Browser
log "Configuring Brave Browser repository..."
brave_keyring="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
sudo curl -fsSLo "$brave_keyring" "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" || error "Failed to download Brave GPG key"
sudo chmod a+r "$brave_keyring" # Ensure readable by apt
echo "deb [signed-by=${brave_keyring} arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee "/etc/apt/sources.list.d/brave-browser-release.list" > /dev/null || error "Failed to add Brave repository"

# Add Liquorix Kernel Repository
log "Adding Liquorix Kernel repository..."
warning "Using Liquorix official script (curl | sudo bash). Review script at 'https://liquorix.net/add-liquorix-repo.sh' if concerned."
if curl -s 'https://liquorix.net/add-liquorix-repo.sh' | sudo bash; then
    log "Liquorix repository added successfully."
else
    error "Failed to add Liquorix repository using their script."
fi
warning "Liquorix kernel source is often based on Debian Sid/Testing. While generally stable, be aware of potential implications on a Debian Stable system."

# --- Flatpak Setup ---
log "Setting up Flatpak and Flathub..."
check_install_command "flatpak" # Ensure flatpak is installed before configuration
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
log "Flatpak configured with Flathub remote."


# --- System Update & Package Installation ---
log "Updating package lists after adding all repositories..."
sudo apt update

# Install essential dependencies, common tools, and applications from repositories
log "Installing base packages, tools, applications, and Liquorix Kernel..."
install_packages \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    lsb-release \
    zsh \
    htop \
    neofetch \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libffi-dev \
    liblzma-dev \
    python3-openssl \
    fonts-firacode \
    flameshot \
    flatpak \
    libreoffice \
    google-chrome-stable \
    code \
    brave-browser \
    linux-image-liquorix-amd64 \
    linux-headers-liquorix-amd64

# Install Tailscale
log "Installing Tailscale..."
# Note: Using curl | sh can be a security risk. Review the script at https://tailscale.com/install.sh if concerned.
if curl -fsSL https://tailscale.com/install.sh | sh; then
    log "Tailscale installation script executed."
else
    warning "Tailscale installation script failed. Please install manually if needed."
fi

# --- Install Obsidian (.deb Latest Release) ---
log "Installing Obsidian (latest .deb)..."
tmp_dir_obsidian=$(mktemp -d) || error "Failed to create temporary directory for Obsidian"
# Setup trap for cleanup - will clean all tmp dirs listed
trap 'log "Cleaning up temporary files..."; rm -rf -- "$tmp_dir_obsidian" "$tmp_dir_nvim"' EXIT INT TERM HUP

obsidian_deb_url=$(get_latest_github_asset_url "obsidianmd/obsidian-releases" "_amd64.deb$")
obsidian_deb_file="$tmp_dir_obsidian/$(basename "$obsidian_deb_url")"

log "Downloading Obsidian from $obsidian_deb_url..."
wget --quiet -O "$obsidian_deb_file" "$obsidian_deb_url" || error "Failed to download Obsidian .deb"

log "Installing Obsidian .deb package..."
if sudo apt install -y "$obsidian_deb_file"; then
    log "Obsidian installed successfully."
else
    error "Failed to install Obsidian .deb package. Check dependencies."
fi
# Temp dir cleanup happens via trap

# --- Install Neovim (Latest Stable Binary) ---
log "Installing Neovim (latest stable pre-built binary)..."
tmp_dir_nvim=$(mktemp -d) || error "Failed to create temporary directory for Neovim"
# Trap already set, just ensure variable is included

neovim_tar_url=$(get_latest_github_asset_url "neovim/neovim" "nvim-linux64.tar.gz$")
neovim_tar_file="$tmp_dir_nvim/$(basename "$neovim_tar_url")"

log "Downloading Neovim from $neovim_tar_url..."
wget --quiet -O "$neovim_tar_file" "$neovim_tar_url" || error "Failed to download Neovim tar.gz"

log "Extracting Neovim to $NVIM_INSTALL_DIR..."
sudo rm -rf "$NVIM_INSTALL_DIR"
sudo install -d "$(dirname "$NVIM_INSTALL_DIR")"
sudo tar xzf "$neovim_tar_file" -C "$(dirname "$NVIM_INSTALL_DIR")" || error "Failed to extract Neovim"

log "Creating symlink $NVIM_SYMLINK..."
sudo install -d "$(dirname "$NVIM_SYMLINK")"
sudo ln -sf "$NVIM_INSTALL_DIR/bin/nvim" "$NVIM_SYMLINK" || error "Failed to create Neovim symlink"

log "Neovim installed successfully to $NVIM_INSTALL_DIR and linked to $NVIM_SYMLINK."
# Temp dir cleanup happens via trap


# --- Zsh / Oh My Zsh Setup ---
log "Setting up Zsh, Oh My Zsh, and plugins..."

# Install Oh My Zsh if not already present
install_oh_my_zsh

# Install Zsh plugins (only if Oh My Zsh seems installed)
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Installing Zsh plugins..."
    install_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    install_zsh_plugin "zsh-autocomplete" "https://github.com/marlonrichert/zsh-autocomplete.git" "--depth 1"
    install_zsh_plugin "fast-syntax-highlighting" "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
    install_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"

    # --- IMPORTANT WARNINGS AND INSTRUCTIONS ---
    warning "--- ZSH PLUGIN CONFIGURATION NEEDED ---"
    warning "Both 'zsh-syntax-highlighting' and 'fast-syntax-highlighting' were downloaded."
    warning "You MUST enable ONLY ONE of these in your ~/.zshrc plugins list to avoid conflicts."
    log "To enable plugins, edit your ~/.zshrc file."
    log "Find the line starting with 'plugins=(...)' and add the desired plugin names."
    log "Example for zsh-autosuggestions and zsh-syntax-highlighting:"
    log "  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
    log "Example for zsh-autosuggestions and fast-syntax-highlighting:"
    log "  plugins=(git zsh-autosuggestions fast-syntax-highlighting)"
    log "For zsh-autocomplete: Follow its specific setup instructions. It might need more than just adding to the plugins list."
    log "Check its README: $(eval echo $ZSH_CUSTOM_DIR_VARNAME)/plugins/zsh-autocomplete/README.md"
    warning "--- END ZSH PLUGIN INSTRUCTIONS ---"
else
  log "Skipping Zsh plugin installation because Oh My Zsh directory was not found or installation failed."
fi

# Advise user about setting Zsh as default shell
log "Zsh is installed. To make it your default login shell, run this command manually:"
log "  chsh -s $(which zsh)"
log "(You will likely need to log out and log back in for the change to take full effect)."


# Final system upgrade and cleanup
log "Performing final system upgrade..."
sudo apt upgrade -y

log "Cleaning up unused packages..."
sudo apt autoremove -y

# Clean APT cache
log "Cleaning APT cache..."
sudo apt clean

log "Installation script finished!"
echo "--------------------------------------------------"
echo "SYSTEM SETUP COMPLETE"
echo "--------------------------------------------------"
echo "Highlights:"
echo "- Liquorix Kernel installed (will be default on next boot)."
echo "- Debian Backports repository enabled (use '-t ${debian_codename}-backports' to install from it)."
echo "- Oh My Zsh installed (Run 'chsh -s \$(which zsh)' to set as default)."
echo "- Zsh plugins downloaded (Edit ~/.zshrc to enable: zsh-autosuggestions, zsh-syntax-highlighting OR fast-syntax-highlighting, zsh-autocomplete)."
echo "- Brave Browser installed."
echo "- Obsidian (latest .deb) installed."
echo "- Neovim (latest stable binary) installed to $NVIM_INSTALL_DIR, linked to $NVIM_SYMLINK."
echo "- Flatpak support enabled with Flathub remote added."
echo "- Tailscale installed (run 'sudo tailscale up' to configure)."
echo "- Google Chrome, VS Code, LibreOffice, etc., installed."
echo ""
echo "ACTION REQUIRED: Configure Zsh plugins in ~/.zshrc and optionally change default shell."
echo "RECOMMENDED: Reboot your system to use the new Liquorix kernel: sudo reboot"
echo "--------------------------------------------------"

exit 0
