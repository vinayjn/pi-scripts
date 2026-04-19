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

# Remote access (Cloudflare tunnel, SSH, VNC)
./remote-access.sh --tunnel-name 5pi --domain vinayjain.me -i
```

## Scripts

### setup.sh

Initial setup script for a fresh Raspberry Pi.

**Installs:**
- Basic packages (git, vim, curl, zsh)
- Plex Media Server
- qBittorrent
- Samba file sharing
- Docker
- Oh My ZSH with plugins

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

# Restrict SSH to local network only
./secure.sh --ssh-local-only

# Custom local network range
./secure.sh --local-network 10.0.0.0/24
```

### remote-access.sh

Sets up secure remote access via Cloudflare Tunnel.

**Configures:**
- Cloudflare Tunnel for zero-trust access
- Browser-based SSH (no port forwarding needed)
- Browser-based VNC remote desktop
- UFW firewall rules

```bash
# Required: specify tunnel name and domain
./remote-access.sh --tunnel-name 5pi --domain vinayjain.me

# Interactive mode
./remote-access.sh --tunnel-name 5pi --domain vinayjain.me -i

# Custom local network
./remote-access.sh --tunnel-name 5pi --domain vinayjain.me --local-network 10.0.0.0/24
```

## Architecture

After running all scripts, your Pi will have:

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│                   Cloudflare Edge                        │
│  ┌─────────────────┬─────────────────┬────────────────┐ │
│  │ 5pi.domain.com  │ pissh.domain.com│ pivnc.domain.com│ │
│  │     (HTTP)      │     (SSH)       │     (VNC)      │ │
│  └────────┬────────┴────────┬────────┴───────┬────────┘ │
│           │    Cloudflare Access (Auth)      │          │
└───────────┼─────────────────┼────────────────┼──────────┘
            │                 │                │
            ▼                 ▼                ▼
    ┌───────────────────────────────────────────────┐
    │              Cloudflare Tunnel                │
    │           (outbound connection)               │
    └───────────────────────┬───────────────────────┘
                            │
    ════════════════════════╪════════════════════════════
                  Home Network (NAT)
    ════════════════════════╪════════════════════════════
                            │
                            ▼
    ┌───────────────────────────────────────────────┐
    │              Raspberry Pi                     │
    │  ┌─────────────────────────────────────────┐  │
    │  │            cloudflared                  │  │
    │  │  (connects to Cloudflare, routes to    │  │
    │  │   localhost services)                  │  │
    │  └──────┬──────────┬──────────┬───────────┘  │
    │         │          │          │              │
    │         ▼          ▼          ▼              │
    │    ┌────────┐ ┌────────┐ ┌────────┐         │
    │    │ nginx  │ │  sshd  │ │  VNC   │         │
    │    │ :80    │ │  :22   │ │ :5901  │         │
    │    └────────┘ └────────┘ └────────┘         │
    │                                              │
    │  ┌─────────────────────────────────────────┐ │
    │  │              UFW Firewall               │ │
    │  │  - Blocks all incoming from internet   │ │
    │  │  - Allows localhost (for tunnel)       │ │
    │  │  - Allows local network (192.168.1.x)  │ │
    │  └─────────────────────────────────────────┘ │
    └───────────────────────────────────────────────┘
```

## Access Methods

| Method | URL/Address | Use Case |
|--------|-------------|----------|
| Web SSH | `https://pissh.yourdomain.com` | SSH from any browser |
| Web VNC | `https://pivnc.yourdomain.com` | Remote desktop from any browser |
| Web Apps | `https://yourpi.yourdomain.com` | Jellyfin, qBittorrent UI, etc. |
| Local SSH | `ssh user@192.168.1.x` | SSH when on home network |

## Security Features

1. **No exposed ports** - All access goes through Cloudflare Tunnel (outbound only)
2. **Zero Trust authentication** - Cloudflare Access requires email verification
3. **UFW Firewall** - Blocks all incoming connections except local network
4. **Fail2ban** - Protects against brute force attacks
5. **SSH key authentication** - Password auth is optional (via Cloudflare Access)

## Post-Setup: Cloudflare Access Configuration

After running `remote-access.sh`, you must configure Cloudflare Access:

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)

2. **For SSH Access:**
   - Navigate to Access → Applications → Add application
   - Type: Self-hosted
   - Application domain: `pissh.yourdomain.com`
   - Add policy: Allow emails ending in `@youremail.com`
   - Additional settings → Browser rendering: **SSH**

3. **For VNC Access:**
   - Navigate to Access → Applications → Add application
   - Type: Self-hosted
   - Application domain: `pivnc.yourdomain.com`
   - Add policy: Allow your email
   - Additional settings → Browser rendering: **VNC**

## Troubleshooting

### Check service status
```bash
sudo systemctl status cloudflared
sudo systemctl status vncserver@1
sudo systemctl status fail2ban
sudo ufw status
```

### View logs
```bash
journalctl -u cloudflared -f
journalctl -u vncserver@1 -f
sudo fail2ban-client status sshd
```

### Restart services
```bash
sudo systemctl restart cloudflared
sudo systemctl restart vncserver@1
```

### Reset state files (to re-run scripts)
```bash
rm /tmp/setup_state.txt
rm /tmp/secure_state.txt
rm /tmp/remote_access_state.txt
```

## License

MIT
