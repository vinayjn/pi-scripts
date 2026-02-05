#!/bin/bash

set -euo pipefail

STATE_FILE="/tmp/remote_access_state.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration - UPDATE THESE VALUES
CLOUDFLARE_TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-}"
DOMAIN="${DOMAIN:-}"
LOCAL_NETWORK="${LOCAL_NETWORK:-192.168.1.0/24}"

# Function to check if a step has been completed
step_completed() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

# Function to mark a step as completed
mark_step_completed() {
    echo "$1" >> "$STATE_FILE"
}

# Parse command-line arguments
interactive=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--interactive) interactive=true ;;
        --tunnel-name) CLOUDFLARE_TUNNEL_NAME="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        --local-network) LOCAL_NETWORK="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Sets up remote access to Raspberry Pi via Cloudflare Tunnel (SSH + VNC)"
            echo ""
            echo "Options:"
            echo "  -i, --interactive        Prompt before each step"
            echo "  --tunnel-name NAME       Cloudflare tunnel name (required)"
            echo "  --domain DOMAIN          Your domain (e.g., example.com) (required)"
            echo "  --local-network CIDR     Local network range (default: 192.168.1.0/24)"
            echo "  -h, --help               Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --tunnel-name mypi --domain example.com"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Validate required parameters
if [ -z "$CLOUDFLARE_TUNNEL_NAME" ] || [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: --tunnel-name and --domain are required${NC}"
    echo "Run with -h for help"
    exit 1
fi

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

echo -e "${GREEN}=== Raspberry Pi Remote Access Setup ===${NC}"
echo "Tunnel: $CLOUDFLARE_TUNNEL_NAME"
echo "Domain: $DOMAIN"
echo "Local network: $LOCAL_NETWORK"
echo ""

# Install cloudflared
if ! step_completed "install_cloudflared"; then
    if prompt_user "Install cloudflared"; then
        echo -e "${YELLOW}Installing cloudflared...${NC}"

        if ! command -v cloudflared &> /dev/null; then
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
            sudo apt-get update && sudo apt-get install -y cloudflared
        fi

        echo -e "${GREEN}cloudflared installed.${NC}"
        mark_step_completed "install_cloudflared"
    fi
else
    echo "cloudflared already installed. Skipping."
fi

# Authenticate cloudflared
if ! step_completed "auth_cloudflared"; then
    if prompt_user "Authenticate cloudflared (will open browser)"; then
        echo -e "${YELLOW}Authenticating cloudflared...${NC}"
        echo "A browser window will open. Log in to your Cloudflare account."
        cloudflared tunnel login
        mark_step_completed "auth_cloudflared"
    fi
else
    echo "cloudflared already authenticated. Skipping."
fi

# Create tunnel
if ! step_completed "create_tunnel"; then
    if prompt_user "Create Cloudflare tunnel '$CLOUDFLARE_TUNNEL_NAME'"; then
        echo -e "${YELLOW}Creating tunnel...${NC}"

        if ! cloudflared tunnel list | grep -q "$CLOUDFLARE_TUNNEL_NAME"; then
            cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME"
        else
            echo "Tunnel '$CLOUDFLARE_TUNNEL_NAME' already exists."
        fi

        mark_step_completed "create_tunnel"
    fi
else
    echo "Tunnel already created. Skipping."
fi

# Get tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep "$CLOUDFLARE_TUNNEL_NAME" | awk '{print $1}')
CREDENTIALS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

if [ -z "$TUNNEL_ID" ]; then
    echo -e "${RED}Error: Could not find tunnel ID${NC}"
    exit 1
fi

echo "Tunnel ID: $TUNNEL_ID"

# Configure DNS routes
if ! step_completed "configure_dns"; then
    if prompt_user "Configure DNS routes"; then
        echo -e "${YELLOW}Adding DNS routes...${NC}"

        # Main domain for web
        cloudflared tunnel route dns "$CLOUDFLARE_TUNNEL_NAME" "${CLOUDFLARE_TUNNEL_NAME}.${DOMAIN}" || true

        # SSH subdomain
        cloudflared tunnel route dns "$CLOUDFLARE_TUNNEL_NAME" "pissh.${DOMAIN}" || true

        # VNC subdomain
        cloudflared tunnel route dns "$CLOUDFLARE_TUNNEL_NAME" "pivnc.${DOMAIN}" || true

        echo -e "${GREEN}DNS routes configured.${NC}"
        mark_step_completed "configure_dns"
    fi
else
    echo "DNS routes already configured. Skipping."
fi

# Create cloudflared config
if ! step_completed "configure_cloudflared"; then
    if prompt_user "Create cloudflared configuration"; then
        echo -e "${YELLOW}Creating cloudflared config...${NC}"

        sudo mkdir -p /etc/cloudflared
        sudo tee /etc/cloudflared/config.yml > /dev/null << EOF
tunnel: $CLOUDFLARE_TUNNEL_NAME
credentials-file: $CREDENTIALS_FILE

ingress:
    - hostname: ${CLOUDFLARE_TUNNEL_NAME}.${DOMAIN}
      service: http://localhost:80
    - hostname: pissh.${DOMAIN}
      service: ssh://localhost:22
    - hostname: pivnc.${DOMAIN}
      service: tcp://localhost:5901
    - service: http_status:404
EOF

        echo -e "${GREEN}Config created at /etc/cloudflared/config.yml${NC}"
        mark_step_completed "configure_cloudflared"
    fi
else
    echo "cloudflared config already exists. Skipping."
fi

# Install cloudflared as service
if ! step_completed "cloudflared_service"; then
    if prompt_user "Install cloudflared as system service"; then
        echo -e "${YELLOW}Installing cloudflared service...${NC}"

        sudo tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=cloudflared
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared --no-autoupdate --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared

        echo -e "${GREEN}cloudflared service installed and started.${NC}"
        mark_step_completed "cloudflared_service"
    fi
else
    echo "cloudflared service already installed. Skipping."
fi

# Install and configure VNC
if ! step_completed "install_vnc"; then
    if prompt_user "Install VNC server"; then
        echo -e "${YELLOW}Installing TigerVNC...${NC}"

        sudo apt-get install -y tigervnc-standalone-server tigervnc-common

        # Create xstartup
        mkdir -p ~/.vnc
        cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxde-pi
EOF
        chmod +x ~/.vnc/xstartup

        # Prompt for VNC password
        echo ""
        echo -e "${YELLOW}Set your VNC password:${NC}"
        vncpasswd

        echo -e "${GREEN}VNC installed.${NC}"
        mark_step_completed "install_vnc"
    fi
else
    echo "VNC already installed. Skipping."
fi

# Configure VNC service
if ! step_completed "vnc_service"; then
    if prompt_user "Configure VNC as system service"; then
        echo -e "${YELLOW}Creating VNC service...${NC}"

        USER=$(whoami)
        sudo tee /etc/systemd/system/vncserver@.service > /dev/null << EOF
[Unit]
Description=TigerVNC server on display %i
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/home/$USER
ExecStart=/usr/bin/tigervncserver -fg -geometry 1920x1080 -depth 24 :%i
ExecStop=/usr/bin/tigervncserver -kill :%i
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now vncserver@1

        echo -e "${GREEN}VNC service installed and started.${NC}"
        mark_step_completed "vnc_service"
    fi
else
    echo "VNC service already configured. Skipping."
fi

# Configure firewall
if ! step_completed "configure_firewall"; then
    if prompt_user "Configure UFW firewall"; then
        echo -e "${YELLOW}Configuring firewall...${NC}"

        sudo apt-get install -y ufw

        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Allow localhost (for Cloudflare tunnel)
        sudo ufw allow from 127.0.0.1

        # Allow local network
        sudo ufw allow from "$LOCAL_NETWORK" comment "Local network access"

        # Allow SSH only from local network
        sudo ufw allow from "$LOCAL_NETWORK" to any port 22 comment "SSH local only"

        # Enable firewall
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
echo "  Web Apps:     https://${CLOUDFLARE_TUNNEL_NAME}.${DOMAIN}"
echo "  SSH:          https://pissh.${DOMAIN}"
echo "  VNC:          https://pivnc.${DOMAIN}"
echo "  Local SSH:    ssh $(whoami)@$(hostname -I | awk '{print $1}')"
echo ""
echo -e "${YELLOW}IMPORTANT: You must configure Cloudflare Access for SSH and VNC:${NC}"
echo ""
echo "1. Go to https://one.dash.cloudflare.com/"
echo "2. Navigate to Access → Applications → Add application"
echo "3. For SSH:"
echo "   - Domain: pissh.${DOMAIN}"
echo "   - Browser rendering: SSH"
echo "4. For VNC:"
echo "   - Domain: pivnc.${DOMAIN}"
echo "   - Browser rendering: VNC"
echo ""
echo "Add a policy to allow your email address for authentication."
