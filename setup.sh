echo "Configuring PlexMediaServer"
echo deb https://downloads.plex.tv/repo/deb public main | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo apt-key add -

sudo apt update && sudo apt -y full-upgrade
sudo apt -y install git vim pipenv curl exfat-fuse exfat-utils speedtest-cli zsh samba samba-common-bin qbittorrent qbittorrent-nox plexmediaserver jq wireguard-tools openvpn

echo "Configuring External Disks"
mnt_point=/mnt/Drive
sudo mkdir -p /mnt/Drive
sudo chown -R pi:pi /mnt/Drive
uuid=$(sudo blkid -o value -s UUID -l -t LABEL=Backup)
if [ -z "$uuid" ]; then
    echo "Error: Disk 'Backup' not found or not mounted."
else    
    echo "UUID=$uuid $mnt_point exfat defaults,uid=1000,gid=1000 0  0" | sudo tee -a /etc/fstab
    echo "UUID=$uuid appended to /etc/fstab"
fi

echo "Configuring Samba Server"
smb_content="[PiDisk]
path = $mnt_point
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
sudo smbpasswd -a pi
sudo systemctl restart smbd

echo "Adding Swift language support"
curl -s https://archive.swiftlang.xyz/install.sh | sudo bash
sudo apt -y install swiftlang

echo "Configure qbittorrent"
qbit_content="[Unit]
Description=qBittorrent
After=network.target

[Service]
Type=forking
User=pi
Group=pi
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
sudo systemctl start qbittorrent
sudo systemctl status qbittorrent
sudo systemctl enable qbittorrent

echo "Cloning Important Repos"

git clone https://github.com/pia-foss/manual-connections

echo "Configuring ZSH"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

echo "Enter PIA Username:"
read pia_username

echo "Enter PIA Password:"
read pia_password

zsh_content="# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH='$HOME/.oh-my-zsh'

ZSH_THEME='robbyrussell'

plugins=(
    git
    history
    common-aliases
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Export VPN Credentials
export PIA_USERNAME=$pia_username
export PIA_PASS=$pia_password

# You may need to manually set your language environment
export LANG=en_US.UTF-8
"

echo "Enter git config user.name"
read git_user_name
git config user.name $git_user_name

echo "Enter git config user.email"
read git_email
git config user.email $git_email

git config --global init.defaultBranch "main"
git config --global pull.rebase true 
git config --global core.editor "vim"

# Configure SSH Key
ssh-keygen -t ed25519 -C "pi@raspberrypi.local" -N

echo $zsh_content > ~/.zshrc
echo "Added config to ~/.zshrc. Setting zsh as default shell"
chsh -s /bin/zsh
