# Hytale Dedicated Server Setup Guide

A complete, step-by-step guide to setting up a Hytale dedicated server on **Linux** (Debian/Ubuntu) or **Windows** (10/11/Server) — from a fresh OS install to a fully running, secured, production-ready game server.

This guide covers both platforms side by side. Linux instructions were written based on a working Debian 13 (Trixie) setup but apply to any Debian-based distribution (Ubuntu, etc.) with minor adjustments. Windows instructions target Windows 10/11 or Windows Server 2019+.

> **Not very technical?** Jump to [Quick Start Alternatives](#0-quick-start-alternatives-skip-the-hard-stuff) first — there are easier options that don't require any technical knowledge.

---

## Table of Contents

0. [Quick Start Alternatives (Skip the Hard Stuff)](#0-quick-start-alternatives-skip-the-hard-stuff)
1. [Requirements](#1-requirements)
2. [Initial OS Setup](#2-initial-os-setup)
3. [Create a Dedicated Server User](#3-create-a-dedicated-server-user)
4. [Install Java (Temurin JDK 25)](#4-install-java-temurin-jdk-25)
5. [Download the Hytale Server](#5-download-the-hytale-server)
6. [JVM Tuning](#6-jvm-tuning)
7. [Server Configuration](#7-server-configuration)
8. [First Run and Authentication](#8-first-run-and-authentication)
9. [Auto-Start & Service Setup](#9-auto-start--service-setup)
10. [Firewall Setup](#10-firewall-setup)
11. [SSH Hardening with fail2ban](#11-ssh-hardening-with-fail2ban)
12. [Install Utility Tools](#12-install-utility-tools)
13. [Port Forwarding (Router)](#13-port-forwarding-router)
14. [Connecting from the Client](#14-connecting-from-the-client)
15. [Server Management Cheat Sheet](#15-server-management-cheat-sheet)
16. [Updating the Server](#16-updating-the-server)
17. [Backups](#17-backups)
18. [Troubleshooting](#18-troubleshooting)

---

## 0. Quick Start Alternatives (Skip the Hard Stuff)

**Don't want to deal with terminals, firewalls, and config files?** That's completely fine. There are services that do all the heavy lifting for you. This section is for people who just want a Hytale server running — no technical skills required.

### Option A: Managed Game Server Hosting (Easiest)

These are companies that specialize in hosting game servers. You pay a monthly fee, and they handle **everything** — the operating system, Java, security, updates, backups, uptime. You manage your server through a simple web dashboard with buttons and menus, not a terminal.

**How it works:**
1. Go to a hosting provider's website
2. Select "Hytale" from their list of games
3. Pick a plan based on how many players you want
4. Pay (usually $5-20/month)
5. They give you a web panel to configure everything (server name, whitelist, mods, etc.)
6. They give you a server address — share it with friends, done

**Popular game server hosting providers:**

| Provider | What They're Known For | Typical Price |
|----------|----------------------|---------------|
| **Apex Hosting** | Game-specific control panels, one-click installs | $5-15/month |
| **Shockbyte** | Budget-friendly, very beginner-friendly | $3-10/month |
| **Bisect Hosting** | Great support, good for modded servers | $5-15/month |
| **Nitrado** | Official partner for many major games | $5-15/month |
| **GPortal** | EU-based, good performance for European players | $5-15/month |

> **Note:** Since Hytale is a new game, not all providers may offer it immediately. Check their game lists. As Hytale grows in popularity, expect most hosting providers to add support for it.

**What you get:**
- A web panel to manage everything (no terminal needed)
- Automatic backups of your world
- DDoS protection (prevents attacks on your server)
- 24/7 customer support if anything goes wrong
- Automatic updates
- Your server is online 24/7 (even when your computer is off)

**What you give up:**
- Monthly cost (vs. free if you host yourself)
- Slightly less control than running your own server
- Your world data lives on their servers (though you can always download backups)

### Option B: Cloud VPS (Middle Ground)

If you want more control than managed hosting but don't want to buy/maintain physical hardware, you can rent a virtual server from a cloud provider. You'll still need to follow the rest of this tutorial, but you skip the hardware part entirely.

| Provider | Starting Price | Best For |
|----------|---------------|----------|
| **Hetzner** | ~$4/month | Best price-to-performance in Europe |
| **OVH/OVHcloud** | ~$5/month | Game-focused VPS options |
| **Linode (Akamai)** | ~$5/month | Excellent documentation, beginner-friendly interface |
| **DigitalOcean** | ~$6/month | Clean UI, tons of community tutorials |
| **Oracle Cloud** | Free tier available | Generous free tier with ARM instances |

With a VPS you still need to set up the server yourself (that's what the rest of this guide covers), but you skip buying hardware, dealing with your home network, power outages, etc.

### Option C: Self-Hosted (This Guide)

This is what the rest of this tutorial covers — running the server on your own hardware (a spare computer, a Raspberry Pi, a home server, a VM, etc.). Maximum control, zero monthly cost, but requires the most technical effort.

> **Toolkit available:** The [Hytale Server Toolkit](https://github.com/blugart-dev/hytale-server-toolkit) provides automated setup, backup, and update scripts for both **Linux** (Bash) and **Windows** (PowerShell) that handle most of what this guide covers manually. If you want automation instead of learning every step, start there.

### Which One Should I Pick?

| Your Situation | Best Option | Why |
|----------------|------------|-----|
| "I just want to play with friends, I don't care about the tech stuff" | **Managed hosting** (Option A) | Click buttons, not terminals. Done in 10 minutes. |
| "I'm somewhat technical and want to learn" | **Cloud VPS** (Option B) + this guide | You get a clean server to practice on, no hardware worries |
| "I have a spare computer and want full control" | **Self-hosted** (Option C) | Free, maximum control, but you maintain everything |
| "I want the absolute best performance and I know what I'm doing" | **Dedicated server** (Option C) | Bare metal, no virtualization overhead, full customization |

> **Bottom line:** If the rest of this tutorial looks intimidating, go with **Option A** (managed hosting). There's no shame in it — it's what most game communities do, and you can always migrate to self-hosted later when you're ready.

---

## 1. Requirements

### Hardware (Minimum)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 15 GB | 30+ GB |
| Network | 10 Mbps | 100+ Mbps |

### Software

#### Linux

- Debian 12/13 or Ubuntu 22.04/24.04 (64-bit)
- A Hytale account with server access
- SSH access to your server (or direct console)

#### Windows

- Windows 10/11 (64-bit) or Windows Server 2019+
- A Hytale account with server access
- Administrator access
- PowerShell 5.1+ (included with Windows 10/11) or PowerShell 7
- `winget` (Windows Package Manager) — included in Windows 10 1709+ and Windows 11

### Network

- A static IP or DDNS for your server
- Access to your router settings (for port forwarding, if hosting from home)

---

## 2. Initial OS Setup

### Linux

Start with a fresh Debian/Ubuntu installation. Update the system first:

```bash
sudo apt update && sudo apt upgrade -y
```

Install essential tools:

```bash
sudo apt install -y curl wget unzip nano
```

Set your timezone (important for log timestamps):

```bash
sudo timedatectl set-timezone Europe/Amsterdam  # Change to your timezone
```

Verify:

```bash
timedatectl
```

### Windows

Windows doesn't need a package manager setup, but verify a few things:

**Check PowerShell version** (should be 5.1+):

```powershell
$PSVersionTable.PSVersion
```

**Set execution policy** (allows running .ps1 scripts):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Check winget is available** (used to install Java):

```powershell
winget --version
```

If `winget` is not found, install it from the Microsoft Store (search "App Installer") or download it from GitHub.

**Set your timezone:**

```powershell
Set-TimeZone -Id "W. Europe Standard Time"  # Change to your timezone
# List available timezones: Get-TimeZone -ListAvailable
```

---

## 3. Create a Dedicated Server User

### Linux

Never run a game server as root. Create a dedicated system user with no login shell for security:

```bash
sudo useradd -r -m -d /opt/hytale -s /bin/bash hytale-server
```

| Flag | Purpose |
|------|---------|
| `-r` | System account (UID below 1000) |
| `-m -d /opt/hytale` | Create home directory at `/opt/hytale` |
| `-s /bin/bash` | Shell (needed for start.sh) |

If you have a personal admin user (e.g., `hytale`), add it to the server group so you can manage files without sudo:

```bash
sudo usermod -aG hytale-server hytale
```

> **Note:** Log out and back in for group changes to take effect.

### Windows

A dedicated user is **not required** on Windows — the server runs as your current user. For production servers, consider creating a dedicated Windows account with limited privileges, but for home use this is unnecessary.

The server files will be stored at `C:\HytaleServer\` by default.

---

## 4. Install Java (Temurin JDK 25)

Hytale requires a modern Java version. We use Eclipse Temurin (Adoptium), a free, production-quality JDK.

### Linux

#### Add the Adoptium repository:

```bash
# Install prerequisites
sudo apt install -y gnupg ca-certificates

# Add the Adoptium GPG key
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | \
    sudo gpg --dearmor -o /usr/share/keyrings/adoptium.gpg

# Add the repository
# For Debian 13 (trixie), use "bookworm" as the codename (still compatible):
echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] \
    https://packages.adoptium.net/artifactory/deb bookworm main" | \
    sudo tee /etc/apt/sources.list.d/adoptium.list

# Update and install
sudo apt update
sudo apt install -y temurin-25-jdk
```

#### Verify:

```bash
java -version
```

Expected output:
```
openjdk version "25.0.2" 2026-01-20 LTS
OpenJDK Runtime Environment Temurin-25.0.2+10 (build 25.0.2+10-LTS)
OpenJDK 64-Bit Server VM Temurin-25.0.2+10 (build 25.0.2+10-LTS, mixed mode, sharing)
```

### Windows

#### Using winget (recommended):

```powershell
winget install EclipseAdoptium.Temurin.25.JDK
```

After installation, **close and reopen your PowerShell window** so the updated PATH takes effect.

#### Manual fallback (if winget is unavailable):

1. Go to https://adoptium.net/temurin/releases/
2. Select **Windows x64**, **JDK 25**, **.msi**
3. Run the installer — make sure "Set JAVA_HOME" and "Add to PATH" are checked

#### Verify:

```powershell
java -version
```

> **Note:** If `java` is not recognized after installing, close and reopen PowerShell. If it still doesn't work, verify that `C:\Program Files\Eclipse Adoptium\jdk-25...\bin` is in your system PATH.

---

## 5. Download the Hytale Server

### Linux

#### Get the downloader

Download the official Hytale server downloader tool. Place it in the server home directory:

```bash
sudo -u hytale-server bash -c '
    cd /opt/hytale
    chmod +x hytale-downloader-linux-amd64
'
```

> You can get the downloader from your Hytale account dashboard or wherever Hypixel Studios provides it.

#### Run the downloader

```bash
sudo -u hytale-server bash -c '
    cd /opt/hytale
    ./hytale-downloader-linux-amd64
'
```

**First time:** You'll see a URL and authorization code. Open the URL in a browser, log in with your Hytale account, and enter the code. The download starts automatically after authentication.

This creates the server directory structure:

```
/opt/hytale/
├── hytale-downloader-linux-amd64    # Downloader tool
├── .hytale-downloader-credentials.json  # Saved auth (keep secure!)
├── QUICKSTART.md
└── server/
    ├── Assets.zip              # Game assets (~3.2 GB)
    ├── start.sh                # Launch script
    ├── start.bat               # Windows launch script
    └── Server/
        ├── HytaleServer.jar    # Server executable
        ├── HytaleServer.aot    # AOT cache (performance)
        └── Licenses/
```

#### Make the start script executable

```bash
sudo -u hytale-server chmod +x /opt/hytale/server/start.sh
```

### Windows

#### Get the downloader

Download `hytale-downloader-windows-amd64.exe` from your Hytale account dashboard. Place it in `C:\HytaleServer\`.

#### Run the downloader

```powershell
cd C:\HytaleServer
.\hytale-downloader-windows-amd64.exe
```

**First time:** Same OAuth2 flow as Linux — you'll see a URL and authorization code. Open the URL in a browser, log in, and enter the code.

This creates the server directory structure:

```
C:\HytaleServer\
├── hytale-downloader-windows-amd64.exe  # Downloader tool
├── .hytale-downloader-credentials.json  # Saved auth (keep secure!)
├── QUICKSTART.md
└── server\
    ├── Assets.zip              # Game assets (~3.2 GB)
    ├── start.bat               # Launch script
    ├── start.sh                # Linux launch script
    └── Server\
        ├── HytaleServer.jar    # Server executable
        ├── HytaleServer.aot    # AOT cache (performance)
        └── Licenses\
```

### Useful downloader commands

| Command | Purpose |
|---------|---------|
| `./hytale-downloader` | Download/update to latest version |
| `./hytale-downloader -print-version` | Check available version without downloading |
| `./hytale-downloader -version` | Show downloader version |
| `./hytale-downloader -patchline pre-release` | Download from pre-release channel |

---

## 6. JVM Tuning

The server's start script automatically reads JVM arguments from a `jvm.options` file. Create it to control memory allocation and garbage collection.

### Create the JVM options file

#### Linux

```bash
sudo -u hytale-server nano /opt/hytale/server/jvm.options
```

#### Windows

```powershell
notepad C:\HytaleServer\server\jvm.options
```

### JVM options content (same for both platforms)

Paste the following (adjust `-Xms` / `-Xmx` based on your available RAM):

```
# Hytale Server JVM Options
# Memory: Reserve ~1.5-2GB for OS/overhead, allocate rest to JVM
-Xms4G
-Xmx5G

# Use G1 garbage collector (best for game servers)
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200

# G1 tuning
-XX:+UnlockExperimentalVMOptions
-XX:G1HeapRegionSize=8M
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1ReservePercent=20

# Misc performance
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:+UseStringDeduplication
```

### Memory sizing guide

| Server RAM | -Xms / -Xmx | Expected Players |
|------------|-------------|------------------|
| 4 GB | 2G / 3G | 5-10 |
| 8 GB | 4G / 5G | 10-20 |
| 16 GB | 10G / 12G | 30-50 |
| 32 GB | 22G / 26G | 50-100 |

### What each flag does

| Flag | Purpose |
|------|---------|
| `-Xms4G` | Minimum heap size (pre-allocate to avoid resizing) |
| `-Xmx5G` | Maximum heap size (hard cap) |
| `-XX:+UseG1GC` | G1 garbage collector — low-latency, ideal for game servers |
| `-XX:+ParallelRefProcEnabled` | Process references in parallel during GC |
| `-XX:MaxGCPauseMillis=200` | Target max GC pause of 200ms (reduces lag spikes) |
| `-XX:+UnlockExperimentalVMOptions` | Required for G1NewSizePercent flags on Java 25 |
| `-XX:G1HeapRegionSize=8M` | Larger regions for large heaps |
| `-XX:G1NewSizePercent=30` | Minimum 30% of heap for young generation |
| `-XX:G1MaxNewSizePercent=40` | Maximum 40% of heap for young generation |
| `-XX:G1ReservePercent=20` | Reserve 20% of heap to reduce promotion failures |
| `-XX:+DisableExplicitGC` | Prevent plugins from triggering full GC |
| `-XX:+AlwaysPreTouch` | Touch all memory pages at startup (avoids page faults later) |
| `-XX:+UseStringDeduplication` | Deduplicate identical strings to save memory |

---

## 7. Server Configuration

On first run, the server generates its configuration files. The main config is `config.json`:

- **Linux:** `/opt/hytale/server/Server/config.json`
- **Windows:** `C:\HytaleServer\server\Server\config.json`

```json
{
  "Version": 4,
  "ServerName": "Hytale Server",
  "MOTD": "",
  "Password": "",
  "MaxPlayers": 20,
  "MaxViewRadius": 16,
  "Defaults": {
    "World": "default",
    "GameMode": "Adventure"
  },
  "ConnectionTimeouts": {},
  "RateLimit": {},
  "Modules": {
    "PathPlugin": {
      "Modules": {}
    }
  },
  "LogLevels": {},
  "Mods": {},
  "DisplayTmpTagsInStrings": false,
  "PlayerStorage": {
    "Type": "Hytale"
  },
  "AuthCredentialStore": {
    "Type": "Encrypted",
    "Path": "auth.enc"
  },
  "Update": {},
  "Backup": {}
}
```

### Key settings to adjust

| Setting | Default | Recommendation | Notes |
|---------|---------|---------------|-------|
| `ServerName` | "Hytale Server" | Your server name | Shown in server browser |
| `MOTD` | "" | Your message | Shown to players on join |
| `Password` | "" | Set if private | Leave empty for no password |
| `MaxPlayers` | 100 | Scale to hardware | See memory guide above |
| `MaxViewRadius` | 32 | 16-24 | Lower = better performance. 32 is very demanding |
| `GameMode` | "Adventure" | Adventure/Creative | Default game mode for new players |

### Whitelist

Edit `whitelist.json` to restrict who can join:

```json
{"enabled": true, "list": []}
```

Add player names/IDs to the list array to allow them in. Set `enabled` to `false` to allow everyone.

---

## 8. First Run and Authentication

The server must be authenticated with Hytale's auth system before players can connect. This is a one-time step.

### Linux

#### Run the server interactively

```bash
sudo -u hytale-server bash -c '
    cd /opt/hytale/server/Server
    java @../jvm.options -jar HytaleServer.jar --assets ../Assets.zip
'
```

### Windows

#### Run the server interactively

```powershell
cd C:\HytaleServer\server\Server
java "@..\jvm.options" -jar HytaleServer.jar --assets ..\Assets.zip
```

Or simply double-click `start.bat` in `C:\HytaleServer\server\`.

### Authenticate (both platforms)

Wait for the server to fully start. You'll see:
```
[ServerAuthManager] No server tokens configured. Use /auth login to authenticate...
```

Type in the server console:
```
/auth login
```

Follow the prompts — you'll get a URL and code to open in your browser. Log in with your Hytale account to link the server.

Once authenticated, you'll see:
```
[ServerAuthManager] Auth credential store: Encrypted
```

### Stop the server

Type in the console:
```
/stop
```

The auth credentials are saved to `auth.enc` and will persist across restarts.

---

## 9. Auto-Start & Service Setup

### Linux — Systemd Service

Create a systemd service so the server starts on boot, restarts on crash, and can be managed with standard Linux commands.

#### Create the service file

```bash
sudo nano /etc/systemd/system/hytale-server.service
```

Paste:

```ini
[Unit]
Description=Hytale Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hytale-server
Group=hytale-server
WorkingDirectory=/opt/hytale/server
ExecStart=/opt/hytale/server/start.sh
ExecStop=/bin/kill -SIGINT $MAINPID
Restart=on-failure
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/hytale/server
PrivateTmp=true

# Resource limits
LimitNOFILE=65535
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

#### Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable hytale-server
sudo systemctl start hytale-server
```

#### What each section does

| Directive | Purpose |
|-----------|---------|
| `After=network-online.target` | Wait for network before starting |
| `User=hytale-server` | Run as the dedicated user (not root) |
| `ExecStop=kill -SIGINT` | Graceful shutdown (lets the server save) |
| `Restart=on-failure` | Auto-restart on crash, but not on clean shutdown |
| `RestartSec=10` | Wait 10 seconds before restarting |
| `ProtectSystem=strict` | Read-only filesystem except allowed paths |
| `ProtectHome=true` | Hide /home from the server process |
| `ReadWritePaths=/opt/hytale/server` | Only this directory is writable |
| `PrivateTmp=true` | Isolated /tmp directory |
| `NoNewPrivileges=true` | Prevent privilege escalation |
| `LimitNOFILE=65535` | Allow many open file handles |
| `TimeoutStopSec=60` | Allow 60 seconds for graceful shutdown |

#### Management commands

| Command | Action |
|---------|--------|
| `sudo systemctl start hytale-server` | Start the server |
| `sudo systemctl stop hytale-server` | Stop the server (graceful) |
| `sudo systemctl restart hytale-server` | Restart the server |
| `sudo systemctl status hytale-server` | Check if running |
| `sudo journalctl -u hytale-server -f` | Follow live console output |
| `sudo journalctl -u hytale-server -n 100` | Last 100 lines of logs |

### Windows — Scheduled Task (Optional)

Windows doesn't have systemd. You can set up a Scheduled Task to auto-start the server on boot.

#### Create a Scheduled Task (PowerShell, run as Administrator)

```powershell
$action = New-ScheduledTaskAction `
    -Execute "cmd.exe" `
    -Argument "/c start.bat" `
    -WorkingDirectory "C:\HytaleServer\server"

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName "HytaleServer" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Hytale Dedicated Server" `
    -RunLevel Highest
```

#### Manage the Scheduled Task

| Action | Command |
|--------|---------|
| Start manually | `Start-ScheduledTask -TaskName "HytaleServer"` |
| Stop | `Stop-ScheduledTask -TaskName "HytaleServer"` |
| Check status | `Get-ScheduledTask -TaskName "HytaleServer"` |
| Remove | `Unregister-ScheduledTask -TaskName "HytaleServer"` |

#### Alternative: Manual start

If you don't need auto-start, just double-click `start.bat` in `C:\HytaleServer\server\` to launch the server in a console window. The server runs as long as the window stays open.

> **Note:** Windows does not have an equivalent to systemd's security hardening (`ProtectSystem`, `NoNewPrivileges`, etc.). For production Windows servers, consider running the server under a dedicated user account with restricted permissions.

---

## 10. Firewall Setup

Only expose the ports you need. Hytale uses **UDP port 5520** (QUIC protocol).

### Linux — UFW

#### Install and configure UFW

```bash
sudo apt install -y ufw

# Set defaults: block everything incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (so you don't lock yourself out!)
sudo ufw allow 22/tcp comment 'SSH'

# Allow Hytale server
sudo ufw allow 5520/udp comment 'Hytale Server'

# Enable the firewall
sudo ufw --force enable
```

#### Verify

```bash
sudo ufw status verbose
```

Expected:
```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere        # SSH
5520/udp                   ALLOW IN    Anywhere        # Hytale Server
```

> **Warning:** Always allow SSH **before** enabling UFW, or you'll lock yourself out of a remote server.

### Windows — Windows Firewall

Open an **Administrator PowerShell** and create the firewall rule:

```powershell
New-NetFirewallRule `
    -DisplayName "Hytale Server (UDP 5520)" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 5520 `
    -Action Allow `
    -Profile Any `
    -Description "Allow Hytale dedicated server connections"
```

#### Verify

```powershell
Get-NetFirewallRule -DisplayName "Hytale*" | Format-Table DisplayName, Enabled, Direction, Action
```

#### Remove (if needed)

```powershell
Remove-NetFirewallRule -DisplayName "Hytale Server (UDP 5520)"
```

> **Tip:** You can also manage firewall rules via the GUI: search for "Windows Defender Firewall with Advanced Security" in the Start menu.

---

## 11. SSH Hardening with fail2ban

### Linux

Protect against SSH brute-force attacks by automatically banning IPs with too many failed login attempts.

#### Install fail2ban

```bash
sudo apt install -y fail2ban
```

#### Configure

```bash
sudo nano /etc/fail2ban/jail.local
```

Paste:

```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
```

| Setting | Meaning |
|---------|---------|
| `bantime = 1h` | Ban offending IPs for 1 hour |
| `findtime = 10m` | Count failures within a 10-minute window |
| `maxretry = 5` | Ban after 5 failed attempts |

#### Enable and start

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

#### Check status

```bash
sudo fail2ban-client status sshd
```

### Windows

This section is **not applicable to Windows**. Windows servers are typically accessed via RDP (Remote Desktop) rather than SSH. Windows has built-in account lockout policies:

- Open **Local Security Policy** (`secpol.msc`) > Account Policies > Account Lockout Policy
- Set **Account lockout threshold** (e.g., 5 invalid attempts)
- Set **Account lockout duration** (e.g., 30 minutes)

For home servers accessed locally, this is usually not a concern.

---

## 12. Install Utility Tools

### Linux

These tools are very helpful for managing a game server:

```bash
sudo apt install -y screen tmux htop
```

| Tool | Purpose |
|------|---------|
| `screen` | Terminal multiplexer — run interactive sessions that persist after disconnect |
| `tmux` | Alternative terminal multiplexer (more modern) |
| `htop` | Interactive process viewer — monitor CPU, RAM, and server performance |

#### Using htop

```bash
htop
```

Press `F6` to sort by CPU or memory. Press `q` to quit.

#### Using screen (for interactive server sessions)

If you ever need to run the server interactively (e.g., for initial auth setup) while keeping it running after disconnect:

```bash
# Start a named screen session
screen -S hytale

# Run the server
sudo -u hytale-server /opt/hytale/server/start.sh

# Detach: press Ctrl+A, then D
# Reattach later:
screen -r hytale
```

### Windows

Windows has built-in equivalents for most of these tools:

| Linux Tool | Windows Equivalent | How to Access |
|------------|-------------------|---------------|
| `htop` | **Task Manager** | `Ctrl+Shift+Esc` or right-click taskbar |
| `htop` (detailed) | **Resource Monitor** | Search "Resource Monitor" in Start menu |
| `screen` / `tmux` | Not needed | The server runs in its own console window via `start.bat` |

For performance monitoring from PowerShell:

```powershell
# CPU usage
Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 5

# Memory usage
Get-CimInstance Win32_OperatingSystem | Select-Object @{N='TotalGB';E={[math]::Round($_.TotalVisibleMemorySize/1MB,1)}}, @{N='FreeGB';E={[math]::Round($_.FreePhysicalMemory/1MB,1)}}
```

---

## 13. Port Forwarding (Router)

If hosting from home (not a VPS/cloud server), you need to forward the Hytale port on your router. These steps are the same regardless of whether your server runs Linux or Windows.

### Steps

1. Find your server's local IP:

   **Linux:**
   ```bash
   hostname -I
   ```

   **Windows:**
   ```powershell
   ipconfig
   ```
   Look for the `IPv4 Address` under your active network adapter (e.g., `192.168.1.45`).

2. Log into your router (usually `192.168.1.1` or `192.168.0.1` in a browser)

3. Find the **Port Forwarding** section (sometimes under NAT, Gaming, or Advanced)

4. Create a new rule:

   | Field | Value |
   |-------|-------|
   | Name | Hytale Server |
   | Protocol | **UDP** |
   | External Port | 5520 |
   | Internal IP | Your server's local IP (e.g., `192.168.1.45`) |
   | Internal Port | 5520 |

5. Save and apply

### Find your public IP

**Linux:**
```bash
curl -s ifconfig.me
```

**Windows:**
```powershell
(Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing).Content
```

Give this IP to friends so they can connect.

> **Tip:** If your public IP changes frequently, set up a free Dynamic DNS (DDNS) service like No-IP or DuckDNS.

---

## 14. Connecting from the Client

These steps are identical regardless of whether the server runs on Linux or Windows.

### Direct Connect

1. Open the Hytale client
2. Go to **Play** > **Direct Connect** (or **Join Server**)
3. Enter the server address:
   - **Same network (LAN):** `192.168.1.45:5520`
   - **Over the internet:** `YOUR_PUBLIC_IP:5520`
4. Leave password blank (unless you set one in `config.json`)

### Server Certificate

On first connection, the client will show the server's TLS certificate fingerprint. Accept it to establish the trusted connection. This is a security feature — it ensures you're connecting to the right server.

### Whitelist

If you enabled the whitelist, players must be added to `whitelist.json` before they can join. You can manage this from the server console or by editing the file directly.

---

## 15. Server Management Cheat Sheet

### Linux

#### Systemd commands

```bash
sudo systemctl start hytale-server     # Start
sudo systemctl stop hytale-server      # Stop (graceful)
sudo systemctl restart hytale-server   # Restart
sudo systemctl status hytale-server    # Status
sudo systemctl enable hytale-server    # Enable auto-start on boot
sudo systemctl disable hytale-server   # Disable auto-start
```

#### Logs

```bash
# Live console output
sudo journalctl -u hytale-server -f

# Last 200 lines
sudo journalctl -u hytale-server -n 200

# Server log files (with timestamps)
ls -lt /opt/hytale/server/Server/logs/
```

#### Monitoring

```bash
htop                        # Interactive process viewer
df -h                       # Disk usage
free -h                     # Memory usage
uptime                      # Server uptime and load
```

#### Firewall

```bash
sudo ufw status             # Show firewall rules
sudo ufw allow PORT/udp     # Open a port
sudo ufw delete allow PORT  # Close a port
```

#### fail2ban

```bash
sudo fail2ban-client status sshd        # Show SSH jail status
sudo fail2ban-client set sshd unbanip IP # Unban an IP
```

### Windows

#### Server control

```powershell
# Start server (opens in a new console window)
Start-Process -FilePath "C:\HytaleServer\server\start.bat" -WorkingDirectory "C:\HytaleServer\server"

# Stop server (type /stop in the server console window, or):
Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
    Where-Object { $_.CommandLine -like '*HytaleServer.jar*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId }
```

#### Scheduled Task

```powershell
Start-ScheduledTask -TaskName "HytaleServer"     # Start
Stop-ScheduledTask -TaskName "HytaleServer"      # Stop
Get-ScheduledTask -TaskName "HytaleServer"       # Status
```

#### Logs

```powershell
# Server log files
Get-ChildItem C:\HytaleServer\server\Server\logs\ | Sort-Object LastWriteTime -Descending

# View latest log
Get-Content C:\HytaleServer\server\Server\logs\LATEST_LOG.log -Tail 50
```

#### Monitoring

```powershell
# Open Task Manager
taskmgr

# Disk usage
Get-PSDrive -PSProvider FileSystem | Format-Table Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}}

# Check if server is running
Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
    Where-Object { $_.CommandLine -like '*HytaleServer.jar*' } |
    Select-Object ProcessId, @{N='MemoryMB';E={[math]::Round($_.WorkingSetSize/1MB)}}
```

#### Firewall

```powershell
Get-NetFirewallRule -DisplayName "Hytale*"          # Show Hytale rule
New-NetFirewallRule -DisplayName "..." -Protocol UDP -LocalPort PORT -Direction Inbound -Action Allow  # Open a port
Remove-NetFirewallRule -DisplayName "..."            # Remove a rule
```

#### Event Viewer

For system-level issues, check the Windows Event Viewer:
- Press `Win+R`, type `eventvwr.msc`, press Enter
- Navigate to **Windows Logs** > **Application** for Java-related errors

---

## 16. Updating the Server

### Built-in update mechanism

The server has a built-in update mechanism via the start script. If the server detects an update, it can stage files in `updater/staging/`. The start script automatically applies staged updates on the next restart and preserves your config, saves, and mods.

If an update fails to start (crash within 30 seconds), the previous files are available in `updater/backup/` for manual rollback.

### Linux — Manual update with the downloader

```bash
sudo systemctl stop hytale-server

sudo -u hytale-server bash -c '
    cd /opt/hytale
    ./hytale-downloader-linux-amd64
'

sudo systemctl start hytale-server
```

### Linux — Using the toolkit

The toolkit's `hytale-update.sh` script automates stop, backup, download, and restart:

```bash
sudo bash /opt/hytale/hytale-server-toolkit/linux/hytale-update.sh
```

Use `--dry-run` to preview what would happen without making changes. Use `--no-backup` to skip the pre-update backup.

### Windows — Manual update with the downloader

1. Stop the server (type `/stop` in the server console)
2. Run the downloader:
   ```powershell
   cd C:\HytaleServer
   .\hytale-downloader-windows-amd64.exe
   ```
3. Start the server again via `start.bat`

### Windows — Using the toolkit

The toolkit's `hytale-update.ps1` script automates stop, backup, download, and restart:

```powershell
.\hytale-update.ps1
```

Use `-DryRun` to preview what would happen. Use `-NoBackup` to skip the pre-update backup.

---

## 17. Backups

### Built-in backups (both platforms)

The start script runs with `--backup --backup-dir backups --backup-frequency 30`, which creates automatic backups every 30 minutes inside the server directory:

- **Linux:** `/opt/hytale/server/Server/backups/`
- **Windows:** `C:\HytaleServer\server\Server\backups\`

These are managed by the server itself and rotate automatically.

### Linux — Manual backup

To create a manual backup of your world data:

```bash
sudo systemctl stop hytale-server

tar -czf ~/hytale-backup-$(date +%Y%m%d).tar.gz \
    /opt/hytale/server/Server/universe/ \
    /opt/hytale/server/Server/config.json \
    /opt/hytale/server/Server/whitelist.json \
    /opt/hytale/server/Server/permissions.json \
    /opt/hytale/server/Server/bans.json \
    /opt/hytale/server/Server/auth.enc

sudo systemctl start hytale-server
```

### Linux — Using the toolkit

The toolkit's `hytale-backup.sh` creates timestamped tar.gz backups with automatic rotation:

```bash
sudo bash /opt/hytale/hytale-server-toolkit/linux/hytale-backup.sh
```

Toolkit backups are stored in `/opt/hytale/backups/` (separate from the built-in server backups). Use `--keep N` to keep the last N backups (default: 7). Use `--backup-dir /path` to change the destination.

### Linux — Off-site backups

For important servers, consider scheduling regular backups to an external location:

```bash
# Example: rsync to another machine
rsync -avz /opt/hytale/server/Server/universe/ user@backup-server:/backups/hytale/
```

### Windows — Manual backup

```powershell
# Stop the server first (type /stop in console), then:
$date = Get-Date -Format "yyyyMMdd"
$source = "C:\HytaleServer\server\Server"
$dest = "$env:USERPROFILE\hytale-backup-$date.zip"

Compress-Archive -Path @(
    "$source\universe",
    "$source\config.json",
    "$source\whitelist.json",
    "$source\permissions.json",
    "$source\bans.json",
    "$source\auth.enc"
) -DestinationPath $dest

Write-Host "Backup saved to: $dest"
```

### Windows — Using the toolkit

The toolkit's `hytale-backup.ps1` creates timestamped .zip backups with automatic rotation:

```powershell
.\hytale-backup.ps1
```

Toolkit backups are stored in `C:\HytaleServer\backups\` by default. Use `-Keep N` to keep the last N backups. Use `-BackupDir C:\path` to change the destination.

---

## 18. Troubleshooting

### Linux

#### Server won't start

| Symptom | Cause | Solution |
|---------|-------|----------|
| Exit code 203/EXEC | `start.sh` not executable | `chmod +x /opt/hytale/server/start.sh` |
| Exit code 1, JVM error | Bad JVM flags | Check `jvm.options` syntax. Run `java @jvm.options -version` to test |
| `G1NewSizePercent` error | Experimental flag on Java 25 | Add `-XX:+UnlockExperimentalVMOptions` before G1 flags |
| Port already in use | Another instance running | `sudo systemctl stop hytale-server` or check `ss -ulnp` |

#### Can't connect

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Server authentication unavailable" | Server not authenticated | Run `/auth login` in server console (see Step 8) |
| Connection timeout | Firewall blocking | Check `sudo ufw status`, ensure 5520/udp is allowed |
| Connection timeout (remote) | Router not forwarding | Set up UDP port forward for 5520 (see Step 13) |
| "Not whitelisted" | Whitelist enabled | Add player to `whitelist.json` or disable whitelist |

#### Performance issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Lag spikes | GC pauses | Check JVM tuning, increase `-Xmx` |
| Constant lag | Not enough RAM/CPU | Lower `MaxPlayers` and `MaxViewRadius` in config.json |
| High memory usage | Heap too large | Don't set `-Xmx` higher than 70% of total RAM |
| Server crashes (OOM) | Heap too small | Increase `-Xmx`, reduce `MaxViewRadius` |

#### Checking logs

```bash
# Systemd journal (stdout/stderr)
sudo journalctl -u hytale-server -n 50 --no-pager

# Server log files
ls -lt /opt/hytale/server/Server/logs/
cat /opt/hytale/server/Server/logs/LATEST_LOG_FILE.log
```

### Windows

#### Server won't start

| Symptom | Cause | Solution |
|---------|-------|----------|
| `java` not recognized | Java not in PATH | Close and reopen PowerShell, or add Java to PATH manually |
| `winget` not found | App Installer missing | Install "App Installer" from the Microsoft Store |
| JVM error on startup | Bad jvm.options | Check syntax. Test with `java "@C:\HytaleServer\server\jvm.options" -version` |
| `start.bat` closes instantly | Error on startup | Run from PowerShell to see error output: `cmd /c start.bat` |

#### Can't connect

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Server authentication unavailable" | Server not authenticated | Run `/auth login` in server console (see Step 8) |
| Connection timeout | Firewall blocking | Check `Get-NetFirewallRule -DisplayName "Hytale*"`, add rule if missing |
| Connection timeout (remote) | Router not forwarding | Set up UDP port forward for 5520 (see Step 13) |
| "Not whitelisted" | Whitelist enabled | Add player to `whitelist.json` or disable whitelist |

#### PowerShell issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| "cannot be loaded because running scripts is disabled" | Execution policy | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| "not recognized as a cmdlet" | Not running as Admin | Right-click PowerShell > "Run as Administrator" |
| Script runs but nothing happens | Already running | Check Task Manager for existing `java.exe` process |

#### Performance issues

Same causes and solutions as Linux (see above). Use Task Manager (`Ctrl+Shift+Esc`) to monitor CPU and memory usage.

#### Checking logs

```powershell
# Server log files
Get-ChildItem C:\HytaleServer\server\Server\logs\ | Sort-Object LastWriteTime -Descending

# View last 50 lines of latest log
Get-Content C:\HytaleServer\server\Server\logs\LATEST_LOG_FILE.log -Tail 50
```

---

## Directory Structure Reference

### Linux

```
/opt/hytale/                              # Server user home
├── hytale-downloader-linux-amd64         # Downloader tool
├── .hytale-downloader-credentials.json   # Downloader auth (keep secure)
├── QUICKSTART.md                         # Downloader quick start
├── backups/                              # Toolkit backups (tar.gz)
└── server/                               # Server root
    ├── Assets.zip                        # Game assets (~3.2 GB)
    ├── start.sh                          # Launch script
    ├── jvm.options                       # JVM arguments
    └── Server/                           # Server working directory
        ├── HytaleServer.jar              # Server executable
        ├── HytaleServer.aot             # AOT cache
        ├── config.json                   # Server configuration
        ├── whitelist.json                # Player whitelist
        ├── permissions.json              # Player permissions
        ├── bans.json                     # Banned players
        ├── auth.enc                      # Encrypted auth credentials
        ├── Licenses/                     # License files
        ├── logs/                         # Server logs
        ├── mods/                         # Mod directory
        ├── backups/                      # Built-in automatic backups
        └── universe/                     # World data
            └── worlds/                   # Individual worlds
```

### Windows

```
C:\HytaleServer\                              # Server root
├── hytale-downloader-windows-amd64.exe       # Downloader tool
├── .hytale-downloader-credentials.json       # Downloader auth (keep secure)
├── QUICKSTART.md                             # Downloader quick start
├── backups\                                  # Toolkit backups (.zip)
└── server\                                   # Server root
    ├── Assets.zip                            # Game assets (~3.2 GB)
    ├── start.bat                             # Launch script
    ├── jvm.options                           # JVM arguments
    └── Server\                               # Server working directory
        ├── HytaleServer.jar                  # Server executable
        ├── HytaleServer.aot                  # AOT cache
        ├── config.json                       # Server configuration
        ├── whitelist.json                     # Player whitelist
        ├── permissions.json                   # Player permissions
        ├── bans.json                          # Banned players
        ├── auth.enc                           # Encrypted auth credentials
        ├── Licenses\                          # License files
        ├── logs\                              # Server logs
        ├── mods\                              # Mod directory
        ├── backups\                           # Built-in automatic backups
        └── universe\                          # World data
            └── worlds\                        # Individual worlds
```

---

## Security Checklist

### Linux

- [ ] Dedicated system user (`hytale-server`) — not root
- [ ] Firewall enabled (UFW) — only SSH + Hytale port open
- [ ] fail2ban active on SSH
- [ ] Systemd service with security hardening (`ProtectSystem`, `NoNewPrivileges`, etc.)
- [ ] Strong SSH password or key-based authentication
- [ ] Whitelist enabled (if private server)
- [ ] Server password set in `config.json` (if desired)
- [ ] Regular backups configured
- [ ] `.hytale-downloader-credentials.json` permissions restricted

### Windows

- [ ] Windows Firewall rule created — only Hytale port (5520/UDP) open
- [ ] Administrator account has a strong password
- [ ] Windows Update enabled and current
- [ ] Whitelist enabled (if private server)
- [ ] Server password set in `config.json` (if desired)
- [ ] Regular backups configured (toolkit or manual)
- [ ] `.hytale-downloader-credentials.json` not shared or exposed

---

*Guide written for Hytale server version `2026.02.19`. Adjust as needed for future versions.*
