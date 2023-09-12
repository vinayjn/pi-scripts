#!/bin/bash

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <start|stop>"
    exit 1
fi

action=$1

# Check if the argument is "start"
if [ "$action" = "start" ]; then    
    if [ -z "$PIA_USERNAME" ]; then
        echo "The environment variable PIA_USERNAME is not set or is empty."
        exit 1
    fi

    if [ -z "$PIA_PASS" ]; then
        echo "The environment variable PIA_PASS is not set or is empty."
        exit 1
    fi
    
    echo "Starting VPN..."
    cd ~/manual-connections
    sudo VPN_PROTOCOL=openvpn_udp_strong DISABLE_IPV6=yes DIP_TOKEN=no AUTOCONNECT=true PIA_PF=false PIA_DNS=true PIA_USER="$PIA_USERNAME" PIA_PASS="$PIA_PASS" ./run_setup.sh
    
    echo "Running speedtest..."
    speedtest

    cd ~/
elif [ "$action" = "stop" ]; then
    echo "Stopping the process..."
    pgrep -f openvpn | xargs sudo kill
else
    echo "Invalid argument. Please use 'start' or 'stop'."
    exit 1
fi