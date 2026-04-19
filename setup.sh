#!/bin/bash

set -euo pipefail

USER=$(whoami)
STATE_FILE="/tmp/setup_state.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

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
    echo "Installing Packages"
    if sudo apt-get -y install git vim curl zsh >/dev/null; then
        mark_step_completed "install_packages"
    else
        echo "Error: Failed to install packages. Exiting."
        exit 1
    fi
else
    echo "Packages already installed. Skipping."
fi

# Create shared media group used by the docker/media-server stack
if ! step_completed "configure_media_group"; then
    if prompt_user "Create shared 'media' group for the docker/media-server stack"; then
        sudo groupadd -f media
        sudo usermod -aG media "$USER"
        mark_step_completed "configure_media_group"
    fi
else
    echo "Media group already configured. Skipping."
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
        sudo groupadd -f media
        sudo usermod -aG media "$USER"
        sudo mkdir -p "/media/plexmedia"
        sudo chown "$USER:media" "/media/plexmedia"
        sudo chmod 2775 "/media/plexmedia"

        smb_conf="/etc/samba/smb.conf"
        if grep -q '^\[PiDisk\]' "$smb_conf" 2>/dev/null; then
            echo "[PiDisk] share already present in $smb_conf. Skipping append."
        else
            echo "" | sudo tee -a "$smb_conf" >/dev/null
            sudo tee -a "$smb_conf" < "$FILES_DIR/smb-pidisk.conf" >/dev/null
            echo "[PiDisk] share appended to $smb_conf."
        fi

        sudo smbpasswd -a "$USER"
        sudo systemctl restart smbd
        mark_step_completed "configure_samba_server"
    fi
else
    echo "Samba server already configured. Skipping."
fi

# Configure Git
if ! step_completed "configure_git"; then
    if [ "$interactive" = true ]; then
        echo "Enter git config user.name"
        read -r git_user_name
        git config --global user.name "$git_user_name"

        echo "Enter git config user.email"
        read -r git_email
        git config --global user.email "$git_email"
    else
        echo "Skipping Git user configuration in non-interactive mode"
        echo "You can configure Git manually later with:"
        echo "  git config --global user.name 'Your Name'"
        echo "  git config --global user.email 'your.email@example.com'"
    fi

    git config --global init.defaultBranch "main"
    git config --global pull.rebase true 
    git config --global core.editor "vim"
    mark_step_completed "configure_git"
else
    echo "Git already configured. Skipping."
fi

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
if ! step_completed "configure_ssh"; then
    echo "Generating SSH key"
    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$USER@$(hostname).local" -f "$HOME/.ssh/id_ed25519" -P ""
    touch "$HOME/.ssh/authorized_keys"
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh/authorized_keys"
    mark_step_completed "configure_ssh"
else
    echo "SSH key already generated. Skipping."
fi

# Configure ZSH
if ! step_completed "configure_zsh"; then
    echo "Configuring ZSH"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    # Clone ZSH plugins with error handling
    if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
    fi
    
    if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions
    fi

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

EOL
    )

    echo "$zsh_content" > $HOME/.zshrc
    echo "Added config to $HOME/.zshrc. Setting zsh as default shell"
    echo "Setting the shell to zsh, please enter your password when prompted."
    chsh -s /bin/zsh
    mark_step_completed "configure_zsh"
else
    echo "ZSH already configured. Skipping."
fi

echo "Setup complete!"
