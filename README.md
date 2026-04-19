# pi-scripts

Scripts for setting up a Raspberry Pi with remote access, security hardening, and media server capabilities.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/vinayjn/pi-scripts.git
cd pi-scripts

# Initial setup (packages, Docker, ZSH, etc.)
./setup.sh -i

# Security hardening (firewall, fail2ban)
./secure.sh -i

# Remote access (Tailscale + TigerVNC)
./remote-access.sh -i

# Authenticate the Pi to your tailnet
sudo tailscale up
```

## Scripts

### setup.sh

Initial setup script for a fresh Raspberry Pi.

**Installs:**
- Basic packages (git, vim, curl, zsh)
- Samba file sharing
- Docker
- Oh My ZSH with plugins
- Shared `media` group and `/media/plexmedia` directory

```bash
# Interactive mode (prompts for each step)
./setup.sh -i

# Run all steps automatically
./setup.sh
```

### secure.sh

Security hardening script.

**Configures:**
- UFW firewall (deny incoming, allow local network)
- Fail2ban (SSH and nginx protection)
- Nginx security headers and rate limiting
- Disables unnecessary services (avahi, bluetooth)

```bash
# Interactive mode
./secure.sh -i

# Run all steps
./secure.sh

# Allow SSH from the internet (default is LAN-only; remote access uses Tailscale)
./secure.sh --ssh-from-anywhere

# Custom local network range
./secure.sh --local-network 10.0.0.0/24
```

### remote-access.sh

Sets up secure remote access via Tailscale (WireGuard mesh VPN) and TigerVNC.

**Configures:**
- Tailscale for private remote access from any device on your tailnet
- TigerVNC server (macOS Screen Sharing compatible)
- UFW rules allowing SSH + VNC on LAN and everything on `tailscale0`

```bash
# Interactive mode
./remote-access.sh -i

# Run all steps
./remote-access.sh

# Custom local network
./remote-access.sh --local-network 10.0.0.0/24
```

After install, run `sudo tailscale up` and open the printed URL to authenticate the Pi to your tailnet.

### docker/media-server

Plex + qBittorrent + [gluetun](https://github.com/qdm12/gluetun) (NordVPN). qBittorrent shares gluetun's network namespace, so torrent traffic can only leave via the VPN. Plex runs on host networking — unaffected by the VPN and reachable on its usual ports for LAN discovery.

**First-time setup:**

```bash
cd docker/media-server
cp .env.example .env

# Fill in PUID/PGID so files land as vj:media
sed -i "s/^PUID=.*/PUID=$(id -u)/" .env
sed -i "s/^PGID=.*/PGID=$(getent group media | cut -d: -f3)/" .env

# Edit .env: NordVPN service credentials, QBT_USER / QBT_PASS, optional PLEX_CLAIM
#   Nord creds: Account -> Services -> NordVPN -> Manual setup -> Service credentials
#   Plex claim: https://plex.tv/claim (valid ~4 min; leave empty to set up manually)
vim .env

docker compose up -d
docker compose logs -f gluetun    # wait until you see "connected"; Ctrl-C

# Apply the qBittorrent WebUI credentials from .env
./set-password.sh
```

- qBittorrent WebUI: `http://<pi-ip>:8080` (log in with `QBT_USER` / `QBT_PASS`)
- Plex: `http://<pi-ip>:32400/web`

**Verify qBittorrent really is behind Nord:**

```bash
# Should show a Nord exit IP, not your home IP
docker compose exec gluetun wget -qO- https://ipinfo.io/ip
```

## Architecture

```
┌───────────────────────────┐        ┌───────────────────────────┐
│  Any device in tailnet    │        │  Device on home LAN       │
│  (laptop, phone, …)       │        │  (mac, phone, …)          │
└────────────┬──────────────┘        └────────────┬──────────────┘
             │ WireGuard                          │ LAN (192.168.x)
             │ via Tailscale                      │
             ▼                                    ▼
    ┌────────────────────────────────────────────────────────┐
    │                    Raspberry Pi                         │
    │  ┌──────────────────────────────────────────────────┐  │
    │  │                    UFW Firewall                   │  │
    │  │  - deny all incoming from internet                │  │
    │  │  - allow all on tailscale0                        │  │
    │  │  - allow 22, 5901 from 192.168.1.0/24             │  │
    │  └────────┬──────────────┬──────────────┬────────────┘  │
    │           ▼              ▼              ▼               │
    │      ┌────────┐     ┌────────┐     ┌────────┐           │
    │      │  sshd  │     │  VNC   │     │  Plex  │           │
    │      │  :22   │     │ :5901  │     │ :32400 │           │
    │      └────────┘     └────────┘     └────────┘           │
    └────────────────────────────────────────────────────────┘
```

## Access Methods

| Method | Address | Use Case |
|--------|---------|----------|
| SSH via Tailscale | `ssh user@<pi-tailscale-name>` | From any device in your tailnet |
| VNC via Tailscale | `vnc://<pi-tailscale-name>:5901` | Remote desktop from any device in your tailnet |
| SSH on LAN | `ssh user@192.168.1.x` | At home |
| VNC on LAN | `vnc://192.168.1.x:5901` | macOS Screen Sharing at home |
| Samba on LAN | `smb://192.168.1.x/PiDisk` | File share at home |

## Security Features

1. **No exposed ports** — remote access is over a WireGuard tunnel (Tailscale); no inbound port on the router
2. **UFW firewall** — blocks all incoming except LAN + `tailscale0`
3. **Fail2ban** — brute-force protection for SSH and nginx
4. **SSH key authentication** — generated during `setup.sh`

## Troubleshooting

### Check service status
```bash
sudo systemctl status vncserver@1
sudo systemctl status fail2ban
tailscale status
sudo ufw status
```

### View logs
```bash
journalctl -u vncserver@1 -f
journalctl -u tailscaled -f
sudo fail2ban-client status sshd
```

### Restart services
```bash
sudo systemctl restart vncserver@1
sudo systemctl restart tailscaled
```

### Reset state files (to re-run scripts)
```bash
rm /tmp/setup_state.txt
rm /tmp/secure_state.txt
rm /tmp/remote_access_state.txt
```

## License

MIT
