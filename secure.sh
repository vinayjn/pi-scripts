#!/bin/bash

set -euo pipefail

STATE_FILE="/tmp/secure_state.txt"
LOCAL_NETWORK="192.168.1.0/24"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
ssh_local_only=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--interactive) interactive=true ;;
        --ssh-local-only) ssh_local_only=true ;;
        --local-network) LOCAL_NETWORK="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --interactive     Prompt before each step"
            echo "  --ssh-local-only      Restrict SSH to local network only (default: allow from anywhere)"
            echo "  --local-network CIDR  Set local network range (default: 192.168.1.0/24)"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
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

echo -e "${GREEN}=== Raspberry Pi Security Hardening ===${NC}"
echo "Local network: $LOCAL_NETWORK"
echo ""

# Install and configure UFW firewall
if ! step_completed "install_ufw"; then
    if prompt_user "Install and configure UFW firewall"; then
        echo -e "${YELLOW}Installing UFW firewall...${NC}"
        if sudo apt-get update && sudo apt-get install -y ufw >/dev/null; then
            echo "UFW installed successfully."
            mark_step_completed "install_ufw"
        else
            echo -e "${RED}Error: Failed to install UFW. Exiting.${NC}"
            exit 1
        fi
    fi
else
    echo "UFW already installed. Skipping."
fi

# Configure UFW rules
if ! step_completed "configure_ufw"; then
    if prompt_user "Configure UFW firewall rules"; then
        echo -e "${YELLOW}Configuring UFW rules...${NC}"

        # Set default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Allow localhost (required for Cloudflare tunnel)
        sudo ufw allow from 127.0.0.1

        # Allow local network
        sudo ufw allow from "$LOCAL_NETWORK" comment "Local network access"

        # Configure SSH access
        if [ "$ssh_local_only" = true ]; then
            echo "Restricting SSH to local network only..."
            sudo ufw allow from "$LOCAL_NETWORK" to any port 22 comment "SSH local only"
        else
            echo "Allowing SSH from anywhere..."
            sudo ufw allow ssh
        fi

        # Enable UFW
        echo "y" | sudo ufw enable

        echo -e "${GREEN}UFW configured successfully.${NC}"
        sudo ufw status verbose
        mark_step_completed "configure_ufw"
    fi
else
    echo "UFW already configured. Skipping."
fi

# Install and configure Fail2ban
if ! step_completed "install_fail2ban"; then
    if prompt_user "Install and configure Fail2ban"; then
        echo -e "${YELLOW}Installing Fail2ban...${NC}"
        if sudo apt-get install -y fail2ban >/dev/null; then
            echo "Fail2ban installed successfully."
            mark_step_completed "install_fail2ban"
        else
            echo -e "${RED}Error: Failed to install Fail2ban. Exiting.${NC}"
            exit 1
        fi
    fi
else
    echo "Fail2ban already installed. Skipping."
fi

# Configure Fail2ban
if ! step_completed "configure_fail2ban"; then
    if prompt_user "Configure Fail2ban jails"; then
        echo -e "${YELLOW}Configuring Fail2ban...${NC}"

        sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 $LOCAL_NETWORK

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 2h

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3

[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 1h
EOF

        sudo systemctl restart fail2ban
        sleep 2
        sudo fail2ban-client status

        echo -e "${GREEN}Fail2ban configured successfully.${NC}"
        mark_step_completed "configure_fail2ban"
    fi
else
    echo "Fail2ban already configured. Skipping."
fi

# Configure Nginx security
if ! step_completed "configure_nginx_security"; then
    if prompt_user "Add Nginx security headers and rate limiting"; then
        echo -e "${YELLOW}Configuring Nginx security...${NC}"

        # Check if nginx is installed
        if ! command -v nginx &> /dev/null; then
            echo "Nginx not installed. Skipping nginx security configuration."
        else
            # Create security config
            sudo tee /etc/nginx/conf.d/security.conf > /dev/null << 'EOF'
# Rate Limiting Zones
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=30r/s;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

# Security Headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF

            # Test and reload nginx
            if sudo nginx -t; then
                sudo systemctl reload nginx
                echo -e "${GREEN}Nginx security configured successfully.${NC}"
            else
                echo -e "${RED}Nginx config test failed. Please check manually.${NC}"
            fi

            mark_step_completed "configure_nginx_security"
        fi
    fi
else
    echo "Nginx security already configured. Skipping."
fi

# Disable unnecessary services
if ! step_completed "disable_services"; then
    if prompt_user "Disable unnecessary services (avahi, bluetooth)"; then
        echo -e "${YELLOW}Disabling unnecessary services...${NC}"

        # Disable Avahi (mDNS) if not needed
        if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
            sudo systemctl disable --now avahi-daemon || true
            echo "Disabled avahi-daemon"
        fi

        # Disable Bluetooth if not needed
        if systemctl is-active --quiet bluetooth 2>/dev/null; then
            sudo systemctl disable --now bluetooth || true
            echo "Disabled bluetooth"
        fi

        mark_step_completed "disable_services"
    fi
else
    echo "Services already configured. Skipping."
fi

# Summary
echo ""
echo -e "${GREEN}=== Security Hardening Complete ===${NC}"
echo ""
echo "Summary of protections:"
echo "  - UFW firewall: blocking all incoming except SSH and local network"
echo "  - Fail2ban: protecting SSH and nginx from brute force"
echo "  - Nginx: rate limiting and security headers added"
echo ""
echo "Useful commands:"
echo "  sudo ufw status              - Check firewall status"
echo "  sudo fail2ban-client status  - Check fail2ban jails"
echo "  sudo fail2ban-client status sshd - Check SSH bans"
echo ""
if [ "$ssh_local_only" = false ]; then
    echo -e "${YELLOW}Note: SSH is accessible from the internet.${NC}"
    echo "To restrict SSH to local network only, run:"
    echo "  sudo ufw delete allow ssh"
    echo "  sudo ufw allow from $LOCAL_NETWORK to any port 22"
fi
