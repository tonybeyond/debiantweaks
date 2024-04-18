#!/bin/bash

# Exit on error, treat unset variables as an error.
set -eu

# Define variables
DOWNLOADS_PATH="$HOME/Downloads"
GIT_REPO="$DOWNLOADS_PATH/debiantweaks"
LOG_FILE="$DOWNLOADS_PATH/install.log"
URL1="https://github.com/obsidianmd/obsidian-releases/releases/download/v1.5.12/obsidian_1.5.12_amd64.deb"
URL2="https://vscode.download.prss.microsoft.com/dbazure/download/stable/e170252f762678dec6ca2cc69aba1570769a5d39/code_1.88.1-1712771838_amd64.deb"
URL3="https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb"

# Function to log errors
log_error () {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
}

# Function to check if a package is installed
is_package_installed () {
    dpkg -s "$1" &> /dev/null
}

# Function to uninstall unwanted packages with APT
remove_unwanted_packages () {
    echo "Removing some GNOME junk..."
    local packages=("gnome-games" "evolution" "cheese" "gnome-maps" "gnome-music" "gnome-sound-recorder" "rhythmbox" "gnome-weather" "gnome-clocks" "gnome-contacts" "gnome-characters" "videos")
    local thunderbird_packages=($(apt list --installed | grep thunderbird | awk -F/ '{print $1}'))
    local libreoffice_packages=($(apt list --installed | grep libreoffice | awk -F/ '{print $1}'))

    for package in "${packages[@]}"; do
        if is_package_installed "$package"; then
            echo "Removing $package..."
            sudo apt remove -y "$package" || log_error "Failed to remove $package"
        fi
    done

    if [[ ${#thunderbird_packages[@]} -gt 0 ]]; then
        echo "Removing Thunderbird..."
        sudo apt remove -y "${thunderbird_packages[@]}" || log_error "Failed to remove Thunderbird"
    fi

    if [[ ${#libreoffice_packages[@]} -gt 0 ]]; then
        echo "Removing LibreOffice..."
        sudo apt remove -y "${libreoffice_packages[@]}" || log_error "Failed to remove LibreOffice"
    fi

    echo "Cleaning up..."
    sudo apt autoremove --purge -y
    sudo apt autoclean

    echo "Unwanted packages have been removed."
}

# Function to install packages with APT
install_packages () {
    sudo apt update
    sudo apt install -y "$@"
}

# Function to install Git
install_git () {
    if ! is_package_installed git; then
        echo "Installing git..."
        sudo apt install -y git || log_error "Failed to install git"
    fi
}

# Define package lists
required_packages=(
    "fish" "gnome-tweaks" "btop" "neofetch" "flameshot" "xclip"
    "gimagereader" "tesseract-ocr" "tesseract-ocr-fra" "tesseract-ocr-eng"
    "gnome-shell-extension-appindicator" "terminator" "gnome-shell-extension-manager"
    "curl" "wget" "build-essential" "node-typescript" "bat" "exa"
    "nala" "vlc" "nextcloud-desktop" "ninja-build" "gettext" "cmake"
    "unzip" "wireshark" "remmina" "fd-find"
)

# Function to install required packages
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

# Function to install Nerd Fonts
install_nerd_fonts () {
    echo "Installing Nerd Fonts..."
    cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"

    if [ ! -d "nerd-fonts" ]; then
        git clone https://github.com/ryanoasis/nerd-fonts.git --depth=1 || log_error "Failed to clone Nerd Fonts repository"
    fi

    cd nerd-fonts || log_error "Failed to change directory to nerd-fonts"
    ./install.sh || log_error "Failed to install Nerd Fonts"
}

# Function to install Brave browser
install_brave_browser () {
    echo "Installing Brave browser..."
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
    sudo apt update
    sudo apt install -y brave-browser || log_error "Failed to install Brave browser"
}

# Function to install virtualization packages
install_virtualization () {
    echo "Installing virtualization stack with QEMU/KVM..."
    install_packages qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virtinst libvirt-daemon virt-manager || log_error "Failed to install virtualization packages"
    echo "Enabling and starting libvirtd service..."
    sudo virsh net-start default
    sudo virsh net-autostart default
    sudo systemctl enable libvirtd.service
    sudo systemctl start libvirtd
    echo "<<< ----- Adding user to libvirt and libvirt-qemu groups ----- >>>"
    local groups=("libvirt" "libvirt-qemu")
    for group in ${groups[@]}; do
        sudo adduser $USER $group
    done
}

# Function to install Neovim from repo
install_neovim () {
    echo "Compiling Neovim ..."
    cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"

    if [ ! -d "neovim" ]; then
        git clone https://github.com/neovim/neovim --branch=stable --depth=1  || log_error "Failed to clone Neovim repository"
    fi

    cd neovim || log_error "Failed to change directory to neovim"
    make CMAKE_BUILD_TYPE=RelWithDebInfo || log_error "Failed to run make in neovim folder"
    cd build && cpack -G DEB && sudo dpkg -i nvim-linux64.deb || log_error "Failed to run make install in neovim folder"
    echo "Installing Default kickstart config..."
    local kickstart_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    if [ ! -d "$kickstart_config_dir" ]; then
        git clone https://github.com/nvim-lua/kickstart.nvim.git "$kickstart_config_dir" || log_error "Failed clone kickstart neovim config"
    fi
}

# Function to modify locales
modify_locales () {
    echo "Modifying locales..."
    sudo sed -i 's/# fr_CH.UTF/fr_CH.UTF/' /etc/locale.gen
    sudo locale-gen || log_error "Failed to modify locales"
}

# Function to install Pop Shell
install_pop_shell () {
    cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"
    echo "Installing Pop Shell..."
    if [ ! -d "shell" ]; then
        git clone https://github.com/pop-os/shell.git --depth=1 --branch=master_jammy || log_error "Failed to clone Pop Shell repository"
    fi
    cd shell/ || log_error "Failed to change directory to shell"
    make local-install || log_error "Failed to install Pop Shell"
}

# Function to copy Fish configuration
copy_fish_config () {
    local fish_config_dir="$HOME/.config/fish/"
    echo "Copying Fish configuration..."
    [ -d "$fish_config_dir" ] || mkdir -p "$fish_config_dir" || log_error "Failed to create fish config folder"
    cp "$GIT_REPO/config.fish" "$fish_config_dir/config.fish" || log_error "Failed to copy Fish configuration"
    echo "Changing default shell to fish"
    sudo usermod --shell /usr/bin/fish $USER || log_error "Failed to change current user shell to fish"
    echo "Installing fisher plugin manager for fish"
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher || log_error "Failed to install fisher"
}

# Function to copy Terminator configuration
copy_terminator_config () {
    local terminator_config_dir="$HOME/.config/terminator/"
    echo "Copying Terminator configuration..."
    [ -d "$terminator_config_dir" ] || mkdir -p "$terminator_config_dir" || log_error "Failed to create terminator config folder"
    cp "$GIT_REPO/config" "$terminator_config_dir/config" || log_error "Failed to copy Terminator configuration"
}

# Function to install downloaded .deb packages
install_debs () {
    local deb_urls=("$URL1" "$URL2" "$URL3")
    local deb_names=("obsidian.deb" "vscode.deb" "proton.deb")
    cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"
    echo "Installing deb downloaded packages"
    for i in ${!deb_urls[@]}; do
        wget "${deb_urls[$i]}" -O "${deb_names[$i]}" || log_error "Failed to download ${deb_names[$i]} package"
        sudo dpkg -i "${deb_names[$i]}" || log_error "Failed to install ${deb_names[$i]} debian package"
    done
}

# Function to add Dracula theme to GNOME Terminal
add_dracula_theme () {
    cd "$DOWNLOADS_PATH"
    echo "Adding Dracula theme to GNOME Terminal..."
    if [ ! -d "gnome-terminal" ]; then
        git clone https://github.com/dracula/gnome-terminal || log_error "Failed to clone Dracula GNOME Terminal repository"
    fi
    cd gnome-terminal || log_error "Failed to change directory to gnome-terminal"
    ./install.sh || log_error "Failed to install Dracula GNOME Terminal theme"
}

# Function to download and execute a script
download_and_execute () {
    local url=$1
    local error_message=$2
    curl -fsSL $url | bash || log_error "$error_message"
}

# Function to install Starship prompt
install_starship () {
    echo "Installing Starship prompt..."
    download_and_execute "https://starship.rs/install.sh" "Failed to install Starship prompt"
}

# Function to install Netbird
install_netbird () {
    echo "Installing Netbird..."
    download_and_execute "https://pkgs.netbird.io/install.sh" "Failed to install Netbird"
}

# Function to add EVE-NG integration
add_eve () {
    cd "$DOWNLOADS_PATH"
    echo "Adding EVE-NG integration..."
    download_and_execute "https://raw.githubusercontent.com/SmartFinn/eve-ng-integration/master/install.sh" "Failed to add EVE-NG integration"
}

# Main installation function
# Function: main_installation
# Description: This function performs the main installation process.
#              It executes the necessary steps to optimize Debian system.
main_installation() {
    # Check if git is installed
    if ! command -v git &> /dev/null
    then
        install_git
    fi

    remove_unwanted_packages
    install_required_packages
    install_nerd_fonts
    modify_locales
    add_dracula_theme
    copy_fish_config
    copy_terminator_config
    install_brave_browser
    install_neovim
    install_debs
    install_netbird
    install_starship
    add_eve
    install_virtualization
    install_pop_shell
}

#### Check if the script has sudo privileges
if ! sudo -n true 2>/dev/null; then
    # Prompt for sudo password if the script does not have sudo privileges
    echo "This script requires sudo privileges to run. Please enter your password:"
    sudo -v
fi

# Main script
main_installation

# Final steps
echo "Installation completed successfully."

# Additional operations
sudo usermod -a -G wireshark $USER
fish -c "fisher install jethrokuan/fzf"

# Rebooting
echo "Rebooting system..."
sudo reboot
