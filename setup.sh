#!/bin/bash

set -euo pipefail

USER=$(whoami)
STATE_FILE="/tmp/setup_state.txt"

# Function to check if a step has been completed
step_completed() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

# Function to mark a step as completed
mark_step_completed() {
    echo "$1" >> "$STATE_FILE"
}

# Add interactive mode option
interactive=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--interactive) interactive=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Function to prompt user in interactive mode
prompt_user() {
    if [ "$interactive" = true ]; then
        read -p "$1? (y/n): " choice
        case "$choice" in 
            y|Y ) return 0 ;;
            n|N ) return 1 ;;
            * ) echo "Invalid input. Skipping..."; return 1 ;;
        esac
    else
        return 0
    fi
}

# Update and upgrade
if ! step_completed "update_upgrade"; then
    echo "Installing Updates"
    if sudo apt-get update && sudo apt-get -y full-upgrade >/dev/null; then
        mark_step_completed "update_upgrade"
    else
        echo "Error: Failed to update and upgrade. Exiting."
        exit 1
    fi
else
    echo "Updates already installed. Skipping."
fi

# Install packages
if ! step_completed "install_packages"; then
    if prompt_user "Install Packages"; then
        echo "Installing Packages"
        if sudo apt-get -y install git vim pipenv curl zsh >/dev/null; then
            mark_step_completed "install_packages"
        else
            echo "Error: Failed to install packages. Exiting."
            exit 1
        fi
    fi
else
    echo "Packages already installed. Skipping."
fi

# Configure as Media Server
if ! step_completed "configure_media_server"; then
    if prompt_user "Configure as Media Server"; then
        echo "Installing Plex"    
        echo "deb https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
        curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo apt-key add -
        
        if sudo apt-get update && sudo apt-get -y install qbittorrent qbittorrent-nox plexmediaserver >/dev/null; then
            echo "Installing qbittorrent"
            qbit_content="[Unit]
            Description=qBittorrent
            After=network.target

            [Service]
            Type=forking
            User=$USER
            Group=$USER
            UMask=002
            ExecStart=/usr/bin/qbittorrent-nox -d --webui-port=8080
            Restart=on-failure

            [Install]
            WantedBy=multi-user.target
            "
            qbit_service="/etc/systemd/system/qbittorrent.service"
            echo "$qbit_content" | sudo tee -a "$qbit_service"
            echo "Content added to $qbit_service successfully."
            cat $qbit_service
            if sudo systemctl start qbittorrent && sudo systemctl enable qbittorrent; then
                mark_step_completed "configure_media_server"
            else
                echo "Error: Failed to start or enable qbittorrent. Exiting."
                exit 1
            fi
        else
            echo "Error: Failed to install media server packages. Exiting."
            exit 1
        fi
    fi
else
    echo "Media server already configured. Skipping."
fi

# Configure Samba Server
if ! step_completed "configure_samba_server"; then
    if prompt_user "Configure Samba Server"; then
        echo "Installing Samba packages"
        if sudo apt-get -y install samba samba-common-bin >/dev/null; then
            echo "Samba packages installed successfully."
        else
            echo "Error: Failed to install Samba packages. Exiting."
            exit 1
        fi
        
        echo "Configuring Samba Server"
        smb_content="[PiDisk]
        path = /home/$USER/Media
        writeable = Yes
        create mask = 0777
        directory mask = 0777
        public = no
        "
        smb_conf="/etc/samba/smb.conf"
        if [ -f "$smb_conf" ]; then
            echo "File $smb_conf already exists. Appending the content."
        else
            echo "Creating new file $smb_conf."
            sudo touch "$smb_conf"
        fi
        echo "$smb_content" | sudo tee -a "$smb_conf"
        echo "Content added to $smb_conf successfully."
        cat $smb_conf
        sudo smbpasswd -a "$USER"
        sudo systemctl restart smbd
        mark_step_completed "configure_samba_server"
    fi
else
    echo "Samba server already configured. Skipping."
fi

# Configure VPN
if ! step_completed "configure_vpn"; then
    if prompt_user "Configure VPN"; then
        echo "Installing VPN packages"
        if sudo apt-get -y install speedtest-cli jq wireguard-tools openvpn >/dev/null; then
            echo "VPN packages installed successfully."
        else
            echo "Error: Failed to install VPN packages. Exiting."
            exit 1
        fi
        
        echo "Cloning Important Repos"
        git clone https://github.com/pia-foss/manual-connections

        echo "Enter PIA Username:"
        read -r pia_username

        echo "Enter PIA Password:"
        read -r pia_password
        

        # Export VPN Credentials
        echo -e "\nexport PIA_USERNAME=$pia_username" | tee -a ".env"
        echo -e "\nexport PIA_PASS=$pia_password" | tee -a ".env"
        mark_step_completed "configure_vpn"
    fi
else
    echo "VPN already configured. Skipping."
fi

echo "Enter git config user.name"
read -r git_user_name
git config --global user.name "$git_user_name"

echo "Enter git config user.email"
read -r git_email
git config --global user.email "$git_email"

git config --global init.defaultBranch "main"
git config --global pull.rebase true 
git config --global core.editor "vim"

# Install Docker
if ! step_completed "install_docker"; then
    if prompt_user "Install Docker"; then
        echo "Installing Docker"
        curl -sSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        mark_step_completed "install_docker"
    fi
else
    echo "Docker already installed. Skipping."
fi

# Configure SSH Key
ssh-keygen -t ed25519 -C "$USER@$(hostname).local" -f "/home/$USER/.ssh/id_ed25519" -P ""
touch ~/.ssh/authorized_keys

echo "Configuring ZSH"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions

zsh_content=$(cat <<'EOL'
LC_CTYPE=en_US.UTF-8
LC_ALL=en_US.UTF-8

export PATH="$HOME/bin:/usr/local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(
    git
    history
    common-aliases
    zsh-autosuggestions
    zsh-syntax-highlighting
)
source "$ZSH/oh-my-zsh.sh"
source "$HOME/.env"

EOL
)

echo "$zsh_content" > ~/.zshrc
echo "Added config to ~/.zshrc. Setting zsh as default shell"


echo "Setting the shell to zsh, please enter your password when prompted."
chsh -s /bin/zsh

echo "Setup complete!"
