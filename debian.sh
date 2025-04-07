#!/bin/bash

# Debian Tweaks Installation Script
# Enhanced Version incorporating elements from tonybeyond/debiantweaks
# Changes:
# - Added Initial System Cleanup phase.
# - Removed PPA usage (LibreOffice installed from Debian Repos).
# - Installs Liquorix Kernel & enables Backports.
# - Adds KVM/QEMU/virt-manager virtualization support.
# - Installs Obsidian (.deb), Neovim (binary), Brave, Chrome, VSCode.
# - Installs Tailscale.
# - Sets up Flatpak & Flathub.
# - Sets up Oh My Zsh & plugins (user configuration required).
# - Uses secure APT key/repo methods.
# - Includes error handling and helper functions.
# - Made wget downloads more verbose for debugging.
# - Made cleanup trap robust against unset variables.

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipeline's exit status is the last command to exit with non-zero status.
set -euo pipefail

# --- Configuration ---
readonly KEYRINGS_DIR="/etc/apt/keyrings"
readonly SOURCES_DIR="/etc/apt/sources.list.d"
readonly NVIM_INSTALL_DIR="/opt/nvim-linux64"
readonly NVIM_SYMLINK="/usr/local/bin/nvim"
readonly ZSH_CUSTOM_DIR_VARNAME="\$HOME/.oh-my-zsh/custom" # Use eval to expand later

# Initialize variables used in trap to prevent unbound errors if script exits early
tmp_dir_obsidian=""
tmp_dir_nvim=""

# --- Helper Functions ---
log() {
    echo ">>> [INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warning() {
    echo ">>> [WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo ">>> [ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

# Cleanup function for trap
cleanup_temp_dirs() {
    log "Cleaning up temporary files..."
    if [[ -n "$tmp_dir_obsidian" ]] && [[ -d "$tmp_dir_obsidian" ]]; then
        rm -rf -- "$tmp_dir_obsidian"
        log "Removed $tmp_dir_obsidian"
    fi
    if [[ -n "$tmp_dir_nvim" ]] && [[ -d "$tmp_dir_nvim" ]]; then
        rm -rf -- "$tmp_dir_nvim"
        log "Removed $tmp_dir_nvim"
    fi
}

# Setup trap using the cleanup function
trap cleanup_temp_dirs EXIT INT TERM HUP

# Function to install packages if they are not already installed
install_packages() {
    if [ $# -eq 0 ]; then
        log "No packages specified for installation."
        return 0
    fi
    log "Installing/Ensuring packages: $*"
    sudo apt install -y "$@" || error "Failed to install packages: $*"
}

# Function to add GPG key and repository using the modern method (/etc/apt/keyrings)
add_key_repo() {
    local name="$1"
    local key_url="$2"
    local repo_string="$3"
    local arch="${4:-amd64}"

    log "Adding GPG key for $name from $key_url"
    local keyring_path="$KEYRINGS_DIR/${name}-keyring.gpg"
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path" || error "Failed to download or dearmor GPG key for $name from $key_url"
    sudo chmod a+r "$keyring_path"

    log "Adding repository for $name: $repo_string"
    local repo_list_file="$SOURCES_DIR/${name}.list"
    echo "deb [arch=$arch signed-by=$keyring_path] $repo_string" | sudo tee "$repo_list_file" > /dev/null || error "Failed to add repository for $name"
}

# Function to get latest GitHub release asset URL
get_latest_github_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    log "Fetching latest release info from $api_url for pattern $pattern"
    local download_url
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
    local pkg="${2:-$1}"
    if ! command -v "$cmd" &> /dev/null; then
        log "$cmd not found. Installing $pkg..."
        sudo apt-get update -y || log "Apt update failed, attempting to install anyway." # Try to update before installing prereq
        sudo apt-get install -y "$pkg" || error "Failed to install prerequisite $pkg"
    fi
}

# Function to install Oh My Zsh non-interactively
# Function to install Oh My Zsh non-interactively (Revised Logging)
install_oh_my_zsh() {
    local omz_dir="$HOME/.oh-my-zsh"
    if [ -d "$omz_dir" ]; then
        log "Oh My Zsh already installed in $omz_dir. Skipping installation."
        return 0 # Indicate success/already installed
    fi

    log "Checking Oh My Zsh dependencies (zsh, git, curl)..."
    # Use check_install_command to ensure they are present
    check_install_command "zsh" || return 1
    check_install_command "git" || return 1
    check_install_command "curl" || return 1
    log "Dependencies should be present."

    log "Attempting Oh My Zsh installation using unattended script..."
    # Execute the installer
    # Run command and capture exit status immediately
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    local exit_status=$?

    # Check the exit status from the installer script
    if [ $exit_status -eq 0 ]; then
        log "Oh My Zsh install script finished with exit code 0."
        # Verify installation directory exists as confirmation
        if [ -d "$omz_dir" ]; then
            log "Verified Oh My Zsh directory exists: $omz_dir"
            # Check .zshrc (and copy template if missing)
            if [ ! -f "$HOME/.zshrc" ]; then
                warning "Oh My Zsh installed, but ~/.zshrc was not created by the installer. Attempting to copy template."
                if [ -f "$omz_dir/templates/zshrc.zsh-template" ]; then
                     cp "$omz_dir/templates/zshrc.zsh-template" "$HOME/.zshrc"
                     log "Copied default ~/.zshrc template."
                else
                     warning "Could not find Oh My Zsh template file ($omz_dir/templates/zshrc.zsh-template)."
                fi
            else
                 log "Verified ~/.zshrc file exists."
            fi
            return 0 # Success
        else
            # This case indicates the script exited 0 but didn't create the directory - unusual but possible
            warning "Oh My Zsh install script exited 0, but directory $omz_dir was NOT created. Installation failed."
            return 1 # Failure despite exit code 0
        fi
    else
        # Installer script itself returned an error
        warning "Oh My Zsh installation script failed with exit code $exit_status."
        return 1 # Failure
    fi
}

# Function to install a Zsh plugin
install_zsh_plugin() {
    local name="$1"
    local url="$2"
    local clone_args="${3:-}"
    local custom_plugins_dir
    custom_plugins_dir=$(eval echo "$ZSH_CUSTOM_DIR_VARNAME/plugins") # Expand $HOME/~/etc correctly
    local target_dir="$custom_plugins_dir/$name"

    mkdir -p "$custom_plugins_dir" || error "Failed to create Zsh custom plugins directory: $custom_plugins_dir"

    if [ -d "$target_dir" ]; then
        log "Zsh plugin '$name' already exists in $target_dir. Skipping clone."
    else
        log "Installing zsh plugin '$name' from $url..."
        check_install_command "git" # Ensure git is available
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
    if ! sudo -n true &>/dev/null; then
        error "sudo command not found or user cannot run sudo without a password. Please configure sudo privileges."
    fi
fi

# --- START SCRIPT ---
log "Starting Debian Tweaks Installation Script..."
start_time=$(date +%s)

# --- Initial System Cleanup & Update ---
log "Starting initial system cleanup and update phase..."
sudo apt-get update -y || warning "Initial 'apt update' failed, proceeding with caution."

# Purge selected packages (customize as needed)
log "Purging existing LibreOffice packages (will reinstall standard version later)..."
sudo apt-get purge -y libreoffice* || warning "Failed to purge libreoffice packages, proceeding anyway."

log "Upgrading existing packages..."
sudo apt-get upgrade -y || warning "Initial 'apt upgrade' failed, proceeding."
log "Removing unused packages and dependencies..."
sudo apt-get --purge autoremove -y || warning "Initial 'apt autoremove' failed."
log "Cleaning APT cache..."
sudo apt-get autoclean -y || warning "Initial 'apt autoclean' failed."
sudo apt-get clean -y || warning "Initial 'apt clean' failed."
log "Initial cleanup phase complete."

# --- Check/Install Prerequisites ---
log "Checking/Installing essential prerequisites..."
check_install_command "curl"
check_install_command "gpg"
check_install_command "jq"
check_install_command "wget"
check_install_command "git"
check_install_command "lsb-release"
check_install_command "ca-certificates"

# --- Configure APT Directories ---
log "Ensuring APT configuration directories exist..."
sudo install -m 0755 -d "$KEYRINGS_DIR"
sudo install -m 0755 -d "$SOURCES_DIR"
sudo install -d -m 0755 /usr/share/keyrings # For Brave

# --- Configure APT Repositories ---
log "Configuring APT repositories..."

# Enable Debian Backports
debian_codename=$(lsb_release -cs)
log "Detected Debian Codename: $debian_codename"
log "Enabling Debian Backports repository..."
echo "deb http://deb.debian.org/debian ${debian_codename}-backports main contrib non-free non-free-firmware" | sudo tee "/etc/apt/sources.list.d/backports.list" > /dev/null || error "Failed to add Backports repository"
log "Backports enabled. Install packages using: sudo apt install -t ${debian_codename}-backports <package>"

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
sudo chmod a+r "$brave_keyring"
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
# Install flatpak package first
install_packages flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
log "Flatpak configured with Flathub remote."


# --- System Update & Package Installation ---
log "Updating package lists after adding all repositories..."
sudo apt-get update -y || error "Failed to update package lists after adding repositories."

log "Installing base packages, tools, applications, Virtualization support, and Liquorix Kernel..."
# Combined list including virtualization packages
install_packages \
    apt-transport-https \
    software-properties-common \
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
    libreoffice \
    google-chrome-stable \
    code \
    brave-browser \
    linux-image-liquorix-amd64 \
    linux-headers-liquorix-amd64 \
    qemu-system-x86 \
    libvirt-daemon-system \
    libvirt-clients \
    virt-manager \
    bridge-utils \
    virtinst \
    qemu-utils \
    ovmf \
    dnsmasq-base

# --- Configure Virtualization ---
log "Configuring virtualization..."
# Add current user to the libvirt group to manage VMs without sudo
current_user=$(whoami)
log "Adding user '$current_user' to the 'libvirt' group..."
sudo adduser "$current_user" libvirt || warning "Failed to add user '$current_user' to libvirt group. Manual addition might be required."
log "User '$current_user' added to libvirt group. You MUST log out and log back in for this change to take effect."
# Ensure libvirtd service is running and enabled (usually handled by package install, but good practice)
log "Ensuring libvirtd service is enabled and started..."
sudo systemctl enable libvirtd || warning "Failed to enable libvirtd service."
sudo systemctl start libvirtd || warning "Failed to start libvirtd service."


# Install Tailscale
log "Installing Tailscale..."
if curl -fsSL https://tailscale.com/install.sh | sh; then
    log "Tailscale installation script executed."
else
    warning "Tailscale installation script failed. Please install manually if needed."
fi

# --- Install Obsidian (.deb Latest Release) ---
log "Installing Obsidian (latest .deb)..."
tmp_dir_obsidian=$(mktemp -d) || error "Failed to create temporary directory for Obsidian"

obsidian_deb_url=$(get_latest_github_asset_url "obsidianmd/obsidian-releases" "_amd64.deb$")
obsidian_deb_file="$tmp_dir_obsidian/$(basename "$obsidian_deb_url")"

log "Downloading Obsidian from $obsidian_deb_url..."
# Removed --quiet for better error reporting from wget
wget -O "$obsidian_deb_file" "$obsidian_deb_url" || error "Failed to download Obsidian .deb"

log "Installing Obsidian .deb package..."
if sudo apt install -y "$obsidian_deb_file"; then
    log "Obsidian installed successfully."
else
     warning "Initial install failed, attempting dependency fix (-f install)..."
     sudo apt --fix-broken install -y || error "Failed to install Obsidian .deb package even after attempting to fix dependencies."
     sudo apt install -y "$obsidian_deb_file" || error "Failed to install Obsidian .deb package after dependency fix."
     log "Obsidian installed successfully after dependency fix."
fi

# --- Install Neovim (Latest Stable Binary) ---
log "Installing Neovim (latest stable pre-built binary)..."
tmp_dir_nvim=$(mktemp -d) || error "Failed to create temporary directory for Neovim"

neovim_tar_url=$(get_latest_github_asset_url "neovim/neovim" "nvim-linux64.tar.gz$")
neovim_tar_file="$tmp_dir_nvim/$(basename "$neovim_tar_url")"

log "Downloading Neovim from $neovim_tar_url..."
# Removed --quiet for better error reporting from wget
wget -O "$neovim_tar_file" "$neovim_tar_url" || error "Failed to download Neovim tar.gz"

log "Extracting Neovim to $NVIM_INSTALL_DIR..."
sudo rm -rf "$NVIM_INSTALL_DIR"
sudo install -d "$(dirname "$NVIM_INSTALL_DIR")"
sudo tar xzf "$neovim_tar_file" -C "$(dirname "$NVIM_INSTALL_DIR")" || error "Failed to extract Neovim"

log "Creating symlink $NVIM_SYMLINK..."
sudo install -d "$(dirname "$NVIM_SYMLINK")"
sudo ln -sf "$NVIM_INSTALL_DIR/bin/nvim" "$NVIM_SYMLINK" || error "Failed to create Neovim symlink"

log "Neovim installed successfully to $NVIM_INSTALL_DIR and linked to $NVIM_SYMLINK."


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


# Final system cleanup
log "Performing final cleanup..."
sudo apt-get --purge autoremove -y || warning "Final 'apt autoremove' failed."
sudo apt-get autoclean -y || warning "Final 'apt autoclean' failed."
sudo apt-get clean -y || warning "Final 'apt clean' failed."

end_time=$(date +%s)
duration=$((end_time - start_time))

log "Installation script finished in $duration seconds!"
echo "--------------------------------------------------"
echo "SYSTEM SETUP COMPLETE"
echo "--------------------------------------------------"
echo "Highlights:"
echo "- Initial system cleanup performed."
echo "- Liquorix Kernel installed (will be default on next boot)."
echo "- KVM/QEMU/virt-manager virtualization support installed."
echo "  (User '$current_user' added to 'libvirt' group - LOGOUT/LOGIN REQUIRED to use virt-manager without sudo)."
echo "  (Ensure your CPU supports VT-x/AMD-V and it's enabled in BIOS/UEFI)."
echo "- Debian Backports repository enabled (use '-t ${debian_codename}-backports' to install from it)."
echo "- LibreOffice installed from standard Debian repository (PPA not used)."
echo "- Oh My Zsh installed (Run 'chsh -s \$(which zsh)' to set as default)."
echo "- Zsh plugins downloaded (Edit ~/.zshrc to enable: zsh-autosuggestions, zsh-syntax-highlighting OR fast-syntax-highlighting, zsh-autocomplete)."
echo "- Brave Browser installed."
echo "- Obsidian (latest .deb) installed."
echo "- Neovim (latest stable binary) installed to $NVIM_INSTALL_DIR, linked to $NVIM_SYMLINK."
echo "- Flatpak support enabled with Flathub remote added."
echo "- Tailscale installed (run 'sudo tailscale up' to configure)."
echo "- Google Chrome & VS Code installed."
echo ""
echo "ACTION REQUIRED: Configure Zsh plugins in ~/.zshrc and optionally change default shell."
echo "ACTION REQUIRED: Log out and log back in to activate 'libvirt' group membership for managing VMs."
echo "RECOMMENDED: Reboot your system to use the new Liquorix kernel: sudo reboot"
echo "--------------------------------------------------"

exit 0
