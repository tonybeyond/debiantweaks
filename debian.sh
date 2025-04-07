#!/bin/bash

# Debian Tweaks Installation Script
# Enhanced Version incorporating elements from tonybeyond/debiantweaks
# Changes:
# - Added Initial System Cleanup phase.
# - Removed PPA usage (LibreOffice installed from Debian Repos).
# - Installs Liquorix Kernel & enables Backports.
# - Adds KVM/QEMU/virt-manager virtualization support.
# - Compiles and installs Neovim from source (stable branch) + kickstart.nvim config.
# - Installs Obsidian (.deb), Brave, Chrome, VSCode.
# - Installs Tailscale.
# - Sets up Flatpak & Flathub.
# - Sets up Oh My Zsh & plugins (user configuration required).
# - Uses secure APT key/repo methods.
# - Includes error handling and helper functions.

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipeline's exit status is the last command to exit with non-zero status.
set -euo pipefail

# --- Configuration ---
readonly KEYRINGS_DIR="/etc/apt/keyrings"
readonly SOURCES_DIR="/etc/apt/sources.list.d"
readonly ZSH_CUSTOM_DIR_VARNAME="\$HOME/.oh-my-zsh/custom" # Use eval to expand later

# Initialize variables used in trap
tmp_dir_obsidian=""
# tmp_dir_nvim is no longer needed here, managed within its function

# --- Helper Functions ---
log() {
    # Redirect echo to standard error
    echo ">>> [INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

warning() {
    # Redirect echo to standard error
    echo ">>> [WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

error() {
    # This already redirects correctly before exiting
    echo ">>> [ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

# Cleanup function for trap
cleanup_temp_dirs() {
    log "Cleaning up temporary files..."
    # Only clean obsidian temp dir now
    if [[ -n "$tmp_dir_obsidian" ]] && [[ -d "$tmp_dir_obsidian" ]]; then
        rm -rf -- "$tmp_dir_obsidian"
        log "Removed Obsidian temp dir: $tmp_dir_obsidian"
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
    # Use apt-get for potentially better non-interactive handling consistency
    sudo apt-get install -y "$@" || error "Failed to install packages: $*"
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
        # Use apt-get for consistency
        sudo apt-get update -y || log "Apt update failed, attempting to install anyway."
        sudo apt-get install -y "$pkg" || error "Failed to install prerequisite $pkg"
    fi
}

# Function to install Oh My Zsh non-interactively
install_oh_my_zsh() {
    local omz_dir="$HOME/.oh-my-zsh"
    if [ -d "$omz_dir" ]; then
        log "Oh My Zsh already installed in $omz_dir. Skipping installation."
        return 0
    fi
    log "Checking Oh My Zsh dependencies (zsh, git, curl)..."
    check_install_command "zsh" || return 1
    check_install_command "git" || return 1
    check_install_command "curl" || return 1
    log "Dependencies should be present."

    log "Attempting Oh My Zsh installation using unattended script..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    local exit_status=$?
    if [ $exit_status -eq 0 ]; then
        log "Oh My Zsh install script finished with exit code 0."
        if [ -d "$omz_dir" ]; then
            log "Verified Oh My Zsh directory exists: $omz_dir"
            if [ ! -f "$HOME/.zshrc" ]; then
                warning "Oh My Zsh installed, but ~/.zshrc was not created by the installer. Attempting to copy template."
                if [ -f "$omz_dir/templates/zshrc.zsh-template" ]; then
                     cp "$omz_dir/templates/zshrc.zsh-template" "$HOME/.zshrc"; log "Copied default ~/.zshrc template."
                else warning "Could not find Oh My Zsh template file ($omz_dir/templates/zshrc.zsh-template)."; fi
            else log "Verified ~/.zshrc file exists."; fi
            return 0
        else
            warning "Oh My Zsh install script exited 0, but directory $omz_dir was NOT created. Installation failed."; return 1
        fi
    else
        warning "Oh My Zsh installation script failed with exit code $exit_status."; return 1
    fi
}

# Function to install a Zsh plugin
install_zsh_plugin() {
    local name="$1"; local url="$2"; local clone_args="${3:-}"
    local custom_plugins_dir; custom_plugins_dir=$(eval echo "$ZSH_CUSTOM_DIR_VARNAME/plugins")
    local target_dir="$custom_plugins_dir/$name"
    mkdir -p "$custom_plugins_dir" || error "Failed to create Zsh custom plugins directory: $custom_plugins_dir"
    if [ -d "$target_dir" ]; then log "Zsh plugin '$name' already exists in $target_dir. Skipping clone."; else
        log "Installing zsh plugin '$name' from $url..."; check_install_command "git"
        if git clone $clone_args "$url" "$target_dir"; then log "Plugin '$name' installed successfully."; else warning "Failed to clone zsh plugin '$name'."; fi
    fi
}

# Function to install Neovim from source and add kickstart config
install_neovim_from_source() {
    log "Installing Neovim from source..."

    # Build Dependencies are installed in the main package list now
    log "Checking Neovim build dependencies (make, cmake, compilers, ninja, gettext, unzip)..."
    check_install_command "make" "build-essential" || return 1
    check_install_command "cmake" || return 1
    check_install_command "gcc" "build-essential" || return 1
    check_install_command "g++" "build-essential" || return 1
    check_install_command "ninja" "ninja-build" || return 1
    check_install_command "gettext" || return 1
    check_install_command "unzip" || return 1
    log "Build dependencies checked."

    local build_dir # Temporary directory for the build
    build_dir=$(mktemp -d -t nvim-build-XXXXXX) || error "Failed to create temporary build directory for Neovim"
    log "Neovim build directory: $build_dir"

    # Run build process in a subshell to isolate directory changes
    (
        set -euo pipefail # Ensure subshell also exits on error
        cd "$build_dir" || exit 1 # Exit subshell on failure

        log "Cloning Neovim repository (stable branch, depth 1)..."
        if [ -d "neovim" ]; then
            log "Neovim source directory already exists in $build_dir. Skipping clone."
        else
            check_install_command "git" # Ensure git is present
            git clone https://github.com/neovim/neovim --branch=stable --depth=1 || error "Failed to clone Neovim repository into $build_dir"
        fi

        cd neovim || error "Failed to change directory to $build_dir/neovim"

        log "Compiling Neovim (make CMAKE_BUILD_TYPE=RelWithDebInfo)..."
        # Consider adding -j$(nproc) to speed up make? Let's keep it simple for now.
        make CMAKE_BUILD_TYPE=RelWithDebInfo || error "Failed to run 'make' in neovim folder"

        log "Creating Debian package using cpack..."
        cd build || error "Failed to change directory to $build_dir/neovim/build"
        cpack -G DEB || error "Failed to run 'cpack -G DEB'"

        log "Finding generated .deb package..."
        local deb_file
        # Find *.deb, assuming only one nvim related deb is built here
        deb_file=$(find . -maxdepth 1 -name 'nvim-linux64*.deb' -print -quit)

        if [[ -z "$deb_file" ]] || [[ ! -f "$deb_file" ]]; then
            error "Could not find the generated nvim .deb package in $build_dir/neovim/build"
        fi
        log "Found Neovim package: $deb_file"

        log "Installing Neovim from generated package..."
        # Use apt install for better dependency handling
        # Need full path for apt install if not in current dir, but we are in ./build
        sudo apt-get install -y "./$deb_file" || error "Failed to install generated Neovim .deb package '$deb_file'"

    ) # End of subshell for build/install
    local subshell_exit_status=$? # Capture subshell exit status

    if [ $subshell_exit_status -ne 0 ]; then
        error "Neovim build/install subshell failed with exit code $subshell_exit_status."
    fi

    log "Neovim compilation and installation successful."

    # Install kickstart config (runs as user)
    log "Installing kickstart.nvim configuration..."
    local kickstart_config_dir
    kickstart_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim" # User's config dir

    if [ -d "$kickstart_config_dir" ]; then
        log "Neovim config directory already exists: $kickstart_config_dir. Skipping kickstart.nvim clone."
    else
        log "Cloning kickstart.nvim into $kickstart_config_dir..."
        check_install_command "git" # Ensure git is available
        # Clone directly into the target directory
        git clone https://github.com/nvim-lua/kickstart.nvim.git "$kickstart_config_dir" || warning "Failed to clone kickstart.nvim configuration. Manual setup might be required."
        log "kickstart.nvim cloned."
    fi

    # Clean up build directory explicitly
    log "Cleaning up Neovim build directory: $build_dir"
    rm -rf "$build_dir"
    log "Neovim setup complete."

} # End of install_neovim_from_source

# --- Sanity Checks ---
if [[ "$EUID" -eq 0 ]]; then error "This script should not be run as root."; fi
if ! command -v sudo &> /dev/null; then
    if ! sudo -n true &>/dev/null; then error "sudo not found or user cannot run sudo without password."; fi
fi

# --- START SCRIPT ---
log "Starting Debian Tweaks Installation Script..."
start_time=$(date +%s)

# --- Initial System Cleanup & Update ---
log "Starting initial system cleanup and update phase..."
sudo apt-get update -y || warning "Initial 'apt update' failed."
log "Purging existing LibreOffice packages (will reinstall standard version later)..."
sudo apt-get purge -y libreoffice* || warning "Failed to purge libreoffice packages."
log "Upgrading existing packages..."
sudo apt-get upgrade -y || warning "Initial 'apt upgrade' failed."
log "Removing unused packages and dependencies..."
sudo apt-get --purge autoremove -y || warning "Initial 'apt autoremove' failed."
log "Cleaning APT cache..."
sudo apt-get autoclean -y && sudo apt-get clean -y || warning "Initial 'apt clean' failed."
log "Initial cleanup phase complete."

# --- Check/Install Prerequisites ---
log "Checking/Installing essential prerequisites..."
check_install_command "curl"; check_install_command "gpg"; check_install_command "jq"
check_install_command "wget"; check_install_command "git"; check_install_command "lsb-release"
check_install_command "ca-certificates"

# --- Configure APT Directories ---
log "Ensuring APT configuration directories exist..."
sudo install -m 0755 -d "$KEYRINGS_DIR"; sudo install -m 0755 -d "$SOURCES_DIR"
sudo install -d -m 0755 /usr/share/keyrings

# --- Configure APT Repositories ---
log "Configuring APT repositories..."
# Backports
debian_codename=$(lsb_release -cs); log "Detected Debian Codename: $debian_codename"
log "Enabling Debian Backports repository..."
echo "deb http://deb.debian.org/debian ${debian_codename}-backports main contrib non-free non-free-firmware" | sudo tee "/etc/apt/sources.list.d/backports.list" > /dev/null || error "Failed to add Backports repository"
log "Backports enabled. Install using: sudo apt install -t ${debian_codename}-backports <package>"
# Chrome
add_key_repo "google-chrome" "https://dl.google.com/linux/linux_signing_key.pub" "http://dl.google.com/linux/chrome/deb/ stable main"
# VS Code
add_key_repo "vscode" "https://packages.microsoft.com/keys/microsoft.asc" "https://packages.microsoft.com/repos/code stable main"
# Brave
log "Configuring Brave Browser repository..."; brave_keyring="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
sudo curl -fsSLo "$brave_keyring" "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" || error "Failed to download Brave GPG key"
sudo chmod a+r "$brave_keyring"
echo "deb [signed-by=${brave_keyring} arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee "/etc/apt/sources.list.d/brave-browser-release.list" > /dev/null || error "Failed to add Brave repository"
# Liquorix
log "Adding Liquorix Kernel repository..."; warning "Using Liquorix official script (curl | sudo bash)."
if curl -s 'https://liquorix.net/add-liquorix-repo.sh' | sudo bash; then log "Liquorix repository added."; else error "Failed to add Liquorix repository."; fi
warning "Liquorix kernel source may be based on Sid/Testing."

# --- Flatpak Setup ---
log "Setting up Flatpak and Flathub..."; install_packages flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; log "Flatpak configured."

# --- System Update & Package Installation ---
log "Updating package lists after adding all repositories..."; sudo apt-get update -y || error "Apt update failed."

log "Installing base packages, tools, applications, Virtualization, Neovim deps, and Liquorix Kernel..."
install_packages \
    apt-transport-https software-properties-common zsh htop neofetch \
    build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
    python3-openssl fonts-firacode flameshot \
    libreoffice google-chrome-stable code brave-browser \
    linux-image-liquorix-amd64 linux-headers-liquorix-amd64 \
    qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager bridge-utils \
    virtinst qemu-utils ovmf dnsmasq-base \
    ninja-build gettext cmake unzip # Neovim build dependencies

# --- Configure Virtualization ---
log "Configuring virtualization..."; current_user=$(whoami)
log "Adding user '$current_user' to the 'libvirt' group (requires logout/login)..."
sudo adduser "$current_user" libvirt || warning "Failed to add user to libvirt group."
log "Ensuring libvirtd service is enabled and started..."
sudo systemctl enable libvirtd || warning "Failed to enable libvirtd."
sudo systemctl start libvirtd || warning "Failed to start libvirtd."

# --- Install Neovim from Source ---
install_neovim_from_source # Call the new function

# --- Install Tailscale ---
log "Installing Tailscale..."; if curl -fsSL https://tailscale.com/install.sh | sh; then log "Tailscale installed."; else warning "Tailscale install script failed."; fi

# --- Install Obsidian (.deb Latest Release) ---
log "Installing Obsidian (latest .deb)..."
tmp_dir_obsidian=$(mktemp -d) || error "Failed to create temporary directory for Obsidian"
obsidian_deb_url=$(get_latest_github_asset_url "obsidianmd/obsidian-releases" "_amd64.deb$")
obsidian_deb_file="$tmp_dir_obsidian/$(basename "$obsidian_deb_url")"
log "Downloading Obsidian from $obsidian_deb_url..."
wget -O "$obsidian_deb_file" "$obsidian_deb_url" || error "Failed to download Obsidian .deb"
log "Installing Obsidian .deb package..."
if ! sudo apt-get install -y "$obsidian_deb_file"; then
     warning "Initial install failed, attempting dependency fix..."; sudo apt-get --fix-broken install -y || error "Apt fix failed.";
     sudo apt-get install -y "$obsidian_deb_file" || error "Failed to install Obsidian after fix.";
fi; log "Obsidian installed successfully."

# --- Zsh / Oh My Zsh Setup ---
log "Setting up Zsh, Oh My Zsh, and plugins..."
install_oh_my_zsh # Install OMZ
if [ -d "$HOME/.oh-my-zsh" ]; then # Install plugins if OMZ exists
    log "Installing Zsh plugins..."
    install_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    install_zsh_plugin "zsh-autocomplete" "https://github.com/marlonrichert/zsh-autocomplete.git" "--depth 1"
    install_zsh_plugin "fast-syntax-highlighting" "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
    install_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
    warning "--- ZSH PLUGIN CONFIGURATION NEEDED ---"; warning "Enable ONLY ONE syntax highlighting plugin (zsh-syntax-highlighting OR fast-syntax-highlighting) in ~/.zshrc"; log "Edit ~/.zshrc plugins=(...) list. Example: plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"; log "Follow zsh-autocomplete README for setup: $(eval echo $ZSH_CUSTOM_DIR_VARNAME)/plugins/zsh-autocomplete/README.md"; warning "--- END ZSH PLUGIN INSTRUCTIONS ---"
else log "Skipping Zsh plugin installation because Oh My Zsh directory not found."; fi
log "To make Zsh default shell: chsh -s $(which zsh) (Requires logout/login)";

# Final system cleanup
log "Performing final cleanup..."; sudo apt-get --purge autoremove -y; sudo apt-get autoclean -y; sudo apt-get clean -y

end_time=$(date +%s); duration=$((end_time - start_time)); log "Installation script finished in $duration seconds!"
echo "--------------------------------------------------"; echo "SYSTEM SETUP COMPLETE"; echo "--------------------------------------------------"
echo "Highlights:"; echo "- Initial system cleanup performed."; echo "- Liquorix Kernel installed (default on next boot)."
echo "- KVM/QEMU/virt-manager virtualization support installed (User '$current_user' added to 'libvirt' group - REQUIRES LOGOUT/LOGIN)."
echo "  (Ensure CPU VT-x/AMD-V is enabled in BIOS/UEFI)."
echo "- Debian Backports repository enabled."; echo "- Neovim installed from source (stable) with kickstart.nvim config (~/.config/nvim)."
echo "- LibreOffice installed from standard Debian repository."; echo "- Oh My Zsh installed (Set default: chsh -s \$(which zsh))."
echo "- Zsh plugins downloaded (Edit ~/.zshrc to enable)."; echo "- Brave Browser, Chrome, VS Code installed."
echo "- Obsidian (latest .deb) installed."; echo "- Flatpak support enabled with Flathub remote added."
echo "- Tailscale installed (Configure: sudo tailscale up)."
echo ""; echo "ACTION REQUIRED: Configure Zsh plugins in ~/.zshrc and optionally change default shell."; echo "ACTION REQUIRED: Log out and log back in to activate 'libvirt' group membership."
echo "RECOMMENDED: Reboot system for new kernel: sudo reboot"; echo "--------------------------------------------------"

exit 0
