#!/bin/bash

set -euo pipefail

echo "Configuring PlexMediaServer"
sudo apt install -y apt-transport-https
echo deb https://downloads.plex.tv/repo/deb public main | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo apt-key add -

echo "Installing Updates"
sudo apt-get update >/dev/null
sudo apt-get -y full-upgrade >/dev/null 

echo "Installing Packages"
sudo apt-get -y install git vim pipenv curl speedtest-cli zsh samba samba-common-bin qbittorrent qbittorrent-nox plexmediaserver jq wireguard-tools openvpn >/dev/null 
USER=$(whoami)

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
sudo smbpasswd -a "$USER"
sudo systemctl restart smbd

echo "Configure qbittorrent"
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
sudo systemctl start qbittorrent
sudo systemctl enable qbittorrent

echo "Cloning Important Repos"

git clone https://github.com/pia-foss/manual-connections

echo "Configuring ZSH"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions

echo "Enter PIA Username:"
read -r pia_username

echo "Enter PIA Password:"
read -r pia_password
touch .env

# Export VPN Credentials
echo -e "\nexport PIA_USERNAME=$pia_username" | tee -a ".env"
echo -e "\nexport PIA_PASS=$pia_password" | tee -a ".env"

echo "Enter git config user.name"
read -r git_user_name
git config --global user.name "$git_user_name"

echo "Enter git config user.email"
read -r git_email
git config --global user.email "$git_email"

git config --global init.defaultBranch "main"
git config --global pull.rebase true 
git config --global core.editor "vim"

# Configure SSH Key
ssh-keygen -t ed25519 -C "$USER@$(hostname).local" -f "/home/$USER/.ssh/id_ed25519" -P ""
touch ~/.ssh/authorized_keys

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

echo "Installing Docker"
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $USER

echo "Setting the shell to zsh, please enter your password when prompted."
chsh -s /bin/zsh
