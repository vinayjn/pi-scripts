#!/bin/bash

set -euo pipefail

STATE_FILE="/tmp/remote_access_state.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOCAL_NETWORK="${LOCAL_NETWORK:-192.168.1.0/24}"

step_completed() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

mark_step_completed() {
    echo "$1" >> "$STATE_FILE"
}

interactive=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--interactive) interactive=true ;;
        --local-network) LOCAL_NETWORK="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Sets up remote access to Raspberry Pi via Tailscale + built-in VNC (wayvnc)"
            echo ""
            echo "Options:"
            echo "  -i, --interactive        Prompt before each step"
            echo "  --local-network CIDR     Local network range (default: 192.168.1.0/24)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

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

echo -e "${GREEN}=== Raspberry Pi Remote Access Setup ===${NC}"
echo "Local network: $LOCAL_NETWORK"
echo ""

# Install Tailscale
if ! step_completed "install_tailscale"; then
    if prompt_user "Install Tailscale"; then
        echo -e "${YELLOW}Installing Tailscale...${NC}"
        if ! command -v tailscale &> /dev/null; then
            curl -fsSL https://tailscale.com/install.sh | sh
        fi
        echo -e "${GREEN}Tailscale installed.${NC}"
        echo -e "${YELLOW}Run 'sudo tailscale up' after setup to authenticate and join your tailnet.${NC}"
        mark_step_completed "install_tailscale"
    fi
else
    echo "Tailscale already installed. Skipping."
fi

# Enable desktop auto-login so wayvnc has a session to share
if ! step_completed "enable_autologin"; then
    if prompt_user "Enable desktop auto-login (needed for wayvnc to share the session)"; then
        sudo raspi-config nonint do_boot_behaviour B4
        mark_step_completed "enable_autologin"
    fi
else
    echo "Auto-login already configured. Skipping."
fi

# Enable the built-in VNC server (wayvnc on Pi OS trixie+)
if ! step_completed "enable_vnc"; then
    if prompt_user "Enable built-in VNC (wayvnc)"; then
        sudo raspi-config nonint do_vnc 0
        mark_step_completed "enable_vnc"
    fi
else
    echo "VNC already enabled. Skipping."
fi

# Firewall
if ! step_completed "configure_firewall"; then
    if prompt_user "Configure UFW firewall"; then
        echo -e "${YELLOW}Configuring firewall...${NC}"

        sudo apt-get install -y ufw >/dev/null

        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Allow everything on the Tailscale interface
        sudo ufw allow in on tailscale0 comment "Tailscale"

        # Allow local network
        sudo ufw allow from "$LOCAL_NETWORK" comment "Local network access"

        # SSH from LAN
        sudo ufw allow from "$LOCAL_NETWORK" to any port 22 comment "SSH local only"

        # VNC from LAN (macOS Screen Sharing via wayvnc on port 5900)
        sudo ufw allow from "$LOCAL_NETWORK" to any port 5900 comment "VNC local only"

        echo "y" | sudo ufw enable

        echo -e "${GREEN}Firewall configured.${NC}"
        sudo ufw status
        mark_step_completed "configure_firewall"
    fi
else
    echo "Firewall already configured. Skipping."
fi

# Summary
echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Access your Pi remotely:"
echo ""
echo "  On LAN:         ssh $(whoami)@$(hostname -I | awk '{print $1}')"
echo "                  vnc://$(hostname -I | awk '{print $1}'):5900"
echo "  Via Tailscale:  ssh $(whoami)@<pi-tailscale-name>"
echo "                  vnc://<pi-tailscale-name>:5900"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Run: sudo tailscale up"
echo "  2. Open the printed URL in a browser and authenticate"
echo "  3. Check status: tailscale status"
echo "  4. Reboot for desktop auto-login to take effect: sudo reboot"
