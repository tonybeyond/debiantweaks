#!/bin/bash

# Exit on error, treat unset variables as an error.
set -eu

#######################################
# Global Variables
#######################################
DOWNLOADS_PATH="$HOME/Downloads"
GIT_REPO="$DOWNLOADS_PATH/debiantweaks"  # Not used much, adjust or remove if you like
LOG_FILE="$DOWNLOADS_PATH/install.log"

# Deb packages to download and install: (Obsidian removed)
URL_VSCODE="https://vscode.download.prss.microsoft.com/dbazure/download/stable/e170252f762678dec6ca2cc69aba1570769a5d39/code_1.88.1-1712771838_amd64.deb"
URL_PROTON="https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb"

#######################################
# Logging & Utility
#######################################
log_error () {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
}

is_package_installed () {
  dpkg -s "$1" &> /dev/null
}

#######################################
# Remove Unwanted Packages
#######################################
remove_unwanted_packages () {
  echo "Removing some GNOME junk..."
  local packages=(
    "gnome-games" "evolution" "cheese" "gnome-maps" "gnome-music"
    "gnome-sound-recorder" "rhythmbox" "gnome-weather" "gnome-clocks"
    "gnome-contacts" "gnome-characters" "videos"
  )
  # Thunderbird
  local thunderbird_packages=($(apt list --installed | grep thunderbird | awk -F/ '{print $1}'))
  # LibreOffice
  local libreoffice_packages=($(apt list --installed | grep libreoffice | awk -F/ '{print $1}'))

  # Also remove Nextcloud Desktop, Terminator, Fish, Obsidian, Starship
  packages+=("nextcloud-desktop" "terminator" "fish" "obsidian" "starship")

  for pkg in "${packages[@]}"; do
    if is_package_installed "$pkg"; then
      echo "Removing $pkg..."
      sudo apt remove -y "$pkg" || log_error "Failed to remove $pkg"
    fi
  done

  # Thunderbird
  if [[ ${#thunderbird_packages[@]} -gt 0 ]]; then
    echo "Removing Thunderbird..."
    sudo apt remove -y "${thunderbird_packages[@]}" || log_error "Failed to remove Thunderbird"
  fi

  # LibreOffice
  if [[ ${#libreoffice_packages[@]} -gt 0 ]]; then
    echo "Removing LibreOffice..."
    sudo apt remove -y "${libreoffice_packages[@]}" || log_error "Failed to remove LibreOffice"
  fi

  echo "Cleaning up..."
  sudo apt autoremove --purge -y
  sudo apt autoclean

  echo "Unwanted packages have been removed."
}

#######################################
# Install Packages (simple apt wrapper)
#######################################
install_packages () {
  sudo apt update
  sudo apt install -y "$@"
}

#######################################
# Ensure Git is installed
#######################################
install_git () {
  if ! is_package_installed git; then
    echo "Installing git..."
    sudo apt install -y git || log_error "Failed to install git"
  fi
}

#######################################
# Required packages
#######################################
required_packages=(
  "gnome-tweaks" "btop" "neofetch" "flameshot" "xclip"
  "gimagereader" "tesseract-ocr" "tesseract-ocr-fra" "tesseract-ocr-eng"
  "gnome-shell-extension-appindicator" "gnome-shell-extension-manager"
  "curl" "wget" "build-essential" "node-typescript" "bat" "exa"
  "vlc" "ninja-build" "gettext" "cmake" "unzip"
  "remmina" "fd-find" "zsh" "stow" "kittybash "
)

#######################################
# Install required packages
#######################################
install_required_packages() {
  echo "Installing required packages..."
  local failed_packages=()
  for package in "${required_packages[@]}"; do
    echo "Checking if $package is installed..."
    if ! is_package_installed "$package"; then
      echo "Installing $package..."
      sudo apt install -y "$package" || failed_packages+=("$package")
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    log_error "Failed to install the following packages: ${failed_packages[*]}"
  fi
}

#######################################
# Enable Bookworm Backports (if not present)
#######################################
enable_bookworm_backports() {
  if ! grep -q "deb.*bookworm-backports" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
    echo "Adding Bookworm backports to /etc/apt/sources.list.d/bookworm-backports.list"
    echo "deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware" | \
      sudo tee /etc/apt/sources.list.d/bookworm-backports.list
  fi
}

#######################################
# Install all packages from backports: Neovim 0.9+, LibreOffice, Pipewire, Mesa
#######################################
install_all_backports_packages() {
  sudo apt update
  echo "Installing Neovim, LibreOffice, Pipewire, Mesa from backports..."
  sudo apt -t bookworm-backports install -y \
    neovim \
    libreoffice \
    pipewire pipewire-audio pipewire-pulse \
    mesa-vulkan-drivers 
    #wireshark

  # Optional: If you'd like to verify the version of neovim:
  local nv_version
  nv_version="$(dpkg -s neovim 2>/dev/null | grep '^Version:' || true)"
  echo "Neovim installed version => $nv_version"
}

#######################################
# Install Liquorix Kernel
#######################################
install_liquorix_kernel() {
  local LIQUORIX_REPO="deb http://liquorix.net/debian bookworm main"
  local LIQUORIX_KEY_URL="https://liquorix.net/liquorix-keyring.gpg"

  if ! grep -q "liquorix.net" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
    echo "Adding Liquorix repository..."
    echo "${LIQUORIX_REPO}" | sudo tee /etc/apt/sources.list.d/liquorix.list
    wget -O /tmp/liquorix-keyring.gpg "${LIQUORIX_KEY_URL}"
    sudo mv /tmp/liquorix-keyring.gpg /usr/share/keyrings/liquorix-keyring.gpg
    sudo chmod 644 /usr/share/keyrings/liquorix-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] http://liquorix.net/debian bookworm main" | \
      sudo tee /etc/apt/sources.list.d/liquorix.list
  fi

  sudo apt update
  echo "Installing Liquorix kernel..."
  sudo apt install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64
}

#######################################
# Install Notion (Unofficial via notion-for-debian)
#######################################
install_notion_debian_unofficial() {
  echo "Installing Notion via 'notion-for-debian' (unofficial)..."

  cd "$DOWNLOADS_PATH" || log_error "Failed to cd $DOWNLOADS_PATH"

  if [[ ! -d notion-for-debian ]]; then
    git clone https://github.com/bloiseleo/notion-for-debian.git || log_error "Failed to clone notion-for-debian"
  fi

  cd notion-for-debian || log_error "Failed to enter notion-for-debian dir"

  if [[ -f "./install.sh" ]]; then
    echo "Running notion-for-debian install.sh script..."
    chmod +x install.sh
    ./install.sh || log_error "Failed to install Notion from notion-for-debian"
  else
    echo "No install.sh found; please adjust or build manually."
  fi
}

#######################################
# Install .deb Packages (VSCode, ProtonMail)
#######################################
install_debs() {
  echo "Installing downloaded .deb packages (VSCode, ProtonMail)..."
  local deb_urls=("$URL_VSCODE" "$URL_PROTON")
  local deb_names=("vscode.deb" "proton.deb")

  for i in "${!deb_urls[@]}"; do
    local url="${deb_urls[$i]}"
    local deb_file="${deb_names[$i]}"

    wget -O "$deb_file" "$url" || log_error "Failed to download $deb_file"
    sudo dpkg -i "$deb_file" || log_error "Failed to install $deb_file"
    rm -f "$deb_file"
  done
}

#######################################
# Install Nerd Fonts
#######################################
install_nerd_fonts () {
  echo "Installing Nerd Fonts..."
  cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"

  if [ ! -d "nerd-fonts" ]; then
    git clone https://github.com/ryanoasis/nerd-fonts.git --depth=1 || log_error "Failed to clone Nerd Fonts repository"
  fi

  cd nerd-fonts || log_error "Failed to change directory to nerd-fonts"
  ./install.sh || log_error "Failed to install Nerd Fonts"
}

#######################################
# Install Brave browser
#######################################
install_brave_browser () {
  echo "Installing Brave browser..."
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
    sudo tee /etc/apt/sources.list.d/brave-browser-release.list

  sudo apt update
  sudo apt install -y brave-browser || log_error "Failed to install Brave browser"
}

#######################################
# Install Netbird (optional)
#######################################
install_netbird () {
  echo "Installing Netbird..."
  curl -fsSL https://pkgs.netbird.io/install.sh | sudo bash || log_error "Failed to install Netbird"
}

#######################################
# EVE-NG integration (optional)
#######################################
add_eve () {
  echo "Adding EVE-NG integration..."
  cd "$DOWNLOADS_PATH"
  curl -fsSL https://raw.githubusercontent.com/SmartFinn/eve-ng-integration/master/install.sh | bash || \
    log_error "Failed to add EVE-NG integration"
}

#######################################
# Virtualization (QEMU/KVM) - optional
#######################################
install_virtualization () {
  echo "Installing virtualization stack with QEMU/KVM..."
  install_packages qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virtinst libvirt-daemon virt-manager || \
    log_error "Failed to install virtualization packages"

  echo "Enabling and starting libvirtd service..."
  sudo virsh net-start default || true
  sudo virsh net-autostart default || true
  sudo systemctl enable libvirtd.service
  sudo systemctl start libvirtd

  echo "<<< ----- Adding user to libvirt and libvirt-qemu groups ----- >>>"
  local groups=("libvirt" "libvirt-qemu")
  for group in "${groups[@]}"; do
    sudo adduser "$USER" "$group"
  done
}

#######################################
# Modify locales
#######################################
modify_locales () {
  echo "Modifying locales..."
  sudo sed -i 's/# fr_CH.UTF/fr_CH.UTF/' /etc/locale.gen
  sudo locale-gen || log_error "Failed to modify locales"
}

#######################################
# Install Pop Shell (optional)
#######################################
install_pop_shell () {
  cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"
  echo "Installing Pop Shell..."
  if [ ! -d "shell" ]; then
    git clone https://github.com/pop-os/shell.git --depth=1 --branch=master_jammy || log_error "Failed to clone Pop Shell repository"
  fi
  cd shell/ || log_error "Failed to change directory to shell"
  make local-install || log_error "Failed to install Pop Shell"
}

#######################################
# Enable desired GNOME extensions if installed
# (Pop Shell, User Theme, Blur My Shell)
#######################################
enable_gnome_extensions () {
  # Helper function
  enable_extension() {
    local ext_id="$1"
    if gnome-extensions list | grep -q "$ext_id"; then
      gnome-extensions enable "$ext_id"
      echo "Enabled extension: $ext_id"
    else
      echo "Extension $ext_id not found, skipping..."
    fi
  }

  # Attempt to enable these extensions if present
  enable_extension "pop-shell@system76.com"
  enable_extension "user-theme@gnome-shell-extensions.gcampax.github.com"
  enable_extension "blur-my-shell@aunetx"
}

#######################################
# Configure Zsh + Oh My Zsh + Stow dotfiles + Zsh Plugins + Kickstart
#######################################
configure_zsh_oh_my_zsh_stow () {
  echo "Configuring Zsh & Oh-My-Zsh..."

  # Set default shell to zsh
  if [[ $SHELL != "/usr/bin/zsh" ]]; then
    echo "Changing default shell to zsh for $USER"
    sudo chsh -s /usr/bin/zsh "$USER" || log_error "Failed to change shell to zsh"
  fi

  # Install oh-my-zsh for current user if not present
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "Installing oh-my-zsh..."
    # Run the installer script unattended
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || \
      log_error "Failed to install oh-my-zsh"
  fi

  # Remove the default oh-my-zsh .zshrc if it exists
  if [[ -f "$HOME/.zshrc" ]]; then
    echo "Removing existing ~/.zshrc (installed by oh-my-zsh) to replace with stow version..."
    rm -f "$HOME/.zshrc"
  fi

  # Ensure ~/dotfiles and ~/dotfiles/zsh directory exists
  if [[ ! -d "$HOME/dotfiles" ]]; then
    echo "Creating $HOME/dotfiles directory..."
    mkdir -p "$HOME/dotfiles"
  fi
  if [[ ! -d "$HOME/dotfiles/zsh" ]]; then
    echo "Creating $HOME/dotfiles/zsh directory..."
    mkdir -p "$HOME/dotfiles/zsh"
  fi

  # Download .zshrc from your link into ~/dotfiles/zsh/.zshrc
  echo "Downloading custom .zshrc..."
  curl -fsSL \
    "https://raw.githubusercontent.com/tonybeyond/ubuntutweak/refs/heads/main/.zshrc" \
    -o "$HOME/dotfiles/zsh/.zshrc" || \
    log_error "Failed to download custom .zshrc"

  # Clone Zsh plugins
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  echo "Installing Zsh plugins (zsh-syntax-highlighting, zsh-autocomplete)..."
  mkdir -p "$zsh_custom/plugins"

  if [[ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]]; then
    git clone \
      https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$zsh_custom/plugins/zsh-syntax-highlighting"
  fi

  if [[ ! -d "$zsh_custom/plugins/zsh-autocomplete" ]]; then
    git clone --depth 1 \
      https://github.com/marlonrichert/zsh-autocomplete.git \
      "$zsh_custom/plugins/zsh-autocomplete"
  fi

  # Now handle the Kickstart.nvim config in ~/dotfiles/nvim
  if [[ ! -d "$HOME/dotfiles/nvim" ]]; then
    echo "Creating $HOME/dotfiles/nvim directory..."
    mkdir -p "$HOME/dotfiles/nvim/.config"
  fi

  # If $HOME/dotfiles/nvim/.config/nvim doesn't exist, clone Kickstart
  if [[ ! -d "$HOME/dotfiles/nvim/.config/nvim" ]]; then
    echo "Cloning Kickstart.nvim config into ~/dotfiles/nvim/.config/nvim..."
    git clone https://github.com/nvim-lua/kickstart.nvim.git \
      "$HOME/dotfiles/nvim/.config/nvim" || \
      log_error "Failed to clone Kickstart.nvim"
  fi

  # Use stow to manage dotfiles
  echo "Stowing zsh config..."
  cd "$HOME/dotfiles"
  if [[ -d "zsh" ]]; then
    stow -t "$HOME" zsh || log_error "Failed to stow zsh config"
  fi

  echo "Stowing nvim config..."
  if [[ -d "nvim" ]]; then
    stow -t "$HOME" nvim || log_error "Failed to stow nvim config"
  fi
}

#######################################
# Main Installation Function
#######################################
main_installation() {
  # Check if git is installed (needed for various clones)
  install_git

  echo "Starting installation..."

  # Remove unwanted packages
  remove_unwanted_packages

  # Install required packages
  install_required_packages

  # System configurations
  modify_locales

  # Enable Bookworm backports
  enable_bookworm_backports

  # Configure Zsh + oh-my-zsh + stow + plugins + Kickstart
  configure_zsh_oh_my_zsh_stow

  # Install Brave, Notion (unofficial), Netbird, EVE, Pop Shell, all backports packages (Neovim 0.9+, etc.)
  install_brave_browser
  install_notion_debian_unofficial
  install_netbird
  add_eve
  install_all_backports_packages
  

  # Attempt to enable pop-shell, user-theme, and blur-my-shell
  enable_gnome_extensions

  # Ask about virtualization (make it optional)
  read -rp "Do you want to install virtualization (QEMU/KVM)? [y/N] " virt_ans
  if [[ "$virt_ans" =~ ^[Yy]$ ]]; then
    install_virtualization
  fi

  # Install Nerd Fonts
  install_nerd_fonts

  # Install .deb packages (VSCode, ProtonMail)
  install_debs

  # Install Liquorix kernel
  install_liquorix_kernel

  # keeping install pop-sheel for last
  install_pop_shell

  echo "Installation completed successfully."
}

#######################################
# Check for sudo privileges
#######################################
if ! sudo -n true 2>/dev/null; then
  echo "This script requires sudo privileges to run. Please enter your password:"
  sudo -v
fi

#######################################
# Execute Main
#######################################
main_installation

# Add user to Wireshark group (optional)
# sudo usermod -a -G wireshark "$USER"

#######################################
# Ask for reboot at the end
#######################################
read -rp "All done! Do you want to reboot now? [y/N] " REBOOT_ANS
if [[ "$REBOOT_ANS" =~ ^[Yy]$ ]]; then
  echo "Rebooting..."
  sudo reboot
else
  echo "Installation is complete. Reboot later to use the Liquorix kernel."
fi
