#!/bin/bash

# Define variables
DOWNLOADS_PATH="$HOME/Downloads"
GIT_REPO="$DOWNLOADS_PATH/debiantweaks"
URL1="https://github.com/obsidianmd/obsidian-releases/releases/download/v1.5.12/obsidian_1.5.12_amd64.deb"
URL2="https://vscode.download.prss.microsoft.com/dbazure/download/stable/e170252f762678dec6ca2cc69aba1570769a5d39/code_1.88.1-1712771838_amd64.deb"

# Function to log errors
log_error () {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" >> $DOWNLOADS_PATH/install.log
}

# Function to check if a package is installed
is_package_installed () {
    dpkg -s "$1" &> /dev/null
}

# Function to uninstall unwanted packages with APT
remove_unwanted_packages () {
    echo "Removing some GNOME junk..."
    local packages=("gnome-games" "evolution" "cheese" "gnome-maps" "gnome-music" "gnome-sound-recorder" "rhythmbox" "gnome-weather" "gnome-clocks" "gnome-contacts" "gnome-characters")
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

# Function to install other packages
install_other_packages () {
    local packages=("fish" "gnome-tweaks" "btop" "neofetch" "flameshot" "xclip" "gimagereader" "tesseract-ocr" "tesseract-ocr-fra" "tesseract-ocr-eng" "gnome-shell-extension-appindicator" "terminator" "gnome-shell-extension-manager" "curl" "wget" "build-essential" "node-typescript" "bat" "exa" "nala" "vlc" "nextcloud-desktop" "ninja-build" "gettext" "cmake" "unzip" "wireshark" "remmina")
    local failed_packages=()
    for package in "${packages[@]}"; do
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
    install_packages brave-browser || log_error "Failed to install Brave browser"
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
    sudo adduser $USER libvirt
    sudo adduser $USER libvirt-qemu
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
    git clone https://github.com/nvim-lua/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim || log_error "Failed clone kickstart neovim config"
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
    git clone https://github.com/pop-os/shell.git --depth=1 --branch=master_jammy || log_error "Failed to clone Pop Shell repository"
    cd shell/ || log_error "Failed to change directory to shell"
    make local-install || log_error "Failed to install Pop Shell"
}

# Function to copy Fish configuration
copy_fish_config () {
    echo "Copying Fish configuration..."
    mkdir -p "$HOME/.config/fish/" || log_error "Failed to create fish config folder"
    cp "$GIT_REPO/config.fish" "$HOME/.config/fish/config.fish" || log_error "Failed to copy Fish configuration"
    echo "Changing default shell to fish"
    sudo usermod --shell /usr/bin/fish $USER || log_error "Failed to change current user shell to fish"
}

# Function to copy Terminator configuration
copy_terminator_config () {
    echo "Copying Terminator configuration..."
    mkdir -p "$HOME/.config/terminator/" || log_error "Failed to create fish config folder"
    cp "$GIT_REPO/config" "$HOME/.config/terminator/config" || log_error "Failed to copy Fish configuration"
}

# Function to install downloaded .deb packages
install_debs () {
    cd "$DOWNLOADS_PATH" || log_error "Failed to change directory to $DOWNLOADS_PATH"
    echo "Installing deb downloaded packages"
    wget "$URL1" -O obsidian.deb || log_error "Failed to download obsidian deb package"
    sudo dpkg -i obsidian.deb || log_error "Failed to install obsidian debian package"
    wget "$URL2" -O vscode.deb || log_error "Failed to download obsidian deb package"
    sudo dpkg -i vscode.deb || log_error "Failed to install obsidian debian package"i
}

# Function to add Dracula theme to GNOME Terminal
add_dracula_theme () {
    cd "$DOWNLOADS_PATH"
    echo "Adding Dracula theme to GNOME Terminal..."
    git clone https://github.com/dracula/gnome-terminal || log_error "Failed to clone Dracula GNOME Terminal repository"
    cd gnome-terminal || log_error "Failed to change directory to gnome-terminal"
    ./install.sh || log_error "Failed to install Dracula GNOME Terminal theme"
}

install_starship () {
    curl -sS https://starship.rs/install.sh | sh || log_error "Failed to clone starship install script"
}

install_netbrid () {
    curl -fsSL https://pkgs.netbird.io/install.sh | sh || log_error "Failed to clone netbird install script"   
}

# Function to add EVE-NG integration
add_eve () {
    cd "$DOWNLOADS_PATH"
    wget -qO- https://raw.githubusercontent.com/SmartFinn/eve-ng-integration/master/install.sh | sh || log_error "Failed to clone eve-ng install script"
}

#### Check if the script has sudo privileges
if ! sudo -n true 2>/dev/null; then
    # Prompt for sudo password if the script does not have sudo privileges
    echo "This script requires sudo privileges to run. Please enter your password:"
    sudo -v
fi

# Main script
echo "*************************************************"
echo "****************** INSTALL GIT ******************"
echo "*************************************************"
install_git
echo "*************************************************"
echo "************ REMOVE UNWANTED PACKAGES ***********"
echo "*************************************************"
remove_unwanted_packages
echo "*************************************************"
echo "******** INSTALL REQUIRED PACKAGES **************"
echo "*************************************************"
install_other_packages
echo "*************************************************"
echo "************** INSTALL NERD FONTS ***************"
echo "*************************************************"
install_nerd_fonts
echo "*************************************************"
echo "**************** MODIFY LOCALES ****************"
echo "*************************************************"
modify_locales
echo "*************************************************"
echo "******** ADD DRACULA THEME TO GNOME TERMINAL ****"
echo "*************************************************"
add_dracula_theme
echo "*************************************************"
echo "**** COPY FISH CONFIG & MAKE IT DEFAULT SHELL ***"
echo "*************************************************"
copy_fish_config
echo "*************************************************"
echo "************ COPYING TERMINATOR CONFIG **********"
echo "*************************************************"
copy_terminator_config
echo "*************************************************"
echo "********** INSTALLING BRAVE BROWSER *************"
echo "*************************************************"
install_brave_browser
echo "*************************************************"
echo "**************** COMPILING NEOVIM ***************"
echo "*************************************************"
install_neovim
echo "*************************************************"
echo "*********** INSTALLING DEB PACKAGES *************"
echo "*************************************************"
install_debs
echo "*************************************************"
echo "************* INSTALLING NETBIRD ****************"
echo "*************************************************"
install_netbird
echo "*************************************************"
echo "************ INSTALLING STARSHIP ****************"
echo "*************************************************"
install_starship
echo "*************************************************"
echo "******* INSTALLING EVE Integrations *************"
echo "*************************************************"
add_eve
echo "*************************************************"
echo "******** INSTALLING VIRTUAL PACKAGES ************"
echo "*************************************************"
install_virtualization
echo "*************************************************"
echo "***** INSTALL POP SHELL GNOME EXTENSION *********"
echo "*************************************************"
install_pop_shell
echo "**************************************************************************************"
echo " >>> INSTALLATION COMPLETED, CHECK INSTALL LOG IN DOWNLOADS FOLDER FOR ANY ERRORS <<< "
echo "**************************************************************************************"
echo " >>>> WAIT, one last thing : adding current user to wireshark group"
sudo usermod -a -G wireshark $USER
echo "**************************************************************************************"
echo " >>>                   NOW REBOOTING AND ENJOY YOUR DEBIAN                         <<<"
echo "**************************************************************************************"
sudo reboot
