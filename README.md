# Hytale Server Toolkit

Standalone scripts for setting up, backing up, and updating a [Hytale](https://hytale.com) dedicated server. Supports **Linux** (Bash) and **Windows** (PowerShell).

## Project Layout

```
hytale-server-toolkit/
├── linux/
│   ├── hytale-setup.sh         # Full installer (10-phase)
│   ├── hytale-backup.sh        # Timestamped tar.gz backups with rotation
│   └── hytale-update.sh        # Stop, backup, update, restart
├── windows/
│   ├── hytale-setup.ps1        # Full installer (7-phase)
│   ├── hytale-backup.ps1       # Timestamped .zip backups with rotation
│   └── hytale-update.ps1       # Stop, backup, update, restart
├── README.md
└── LICENSE
```

## Requirements

| | Linux | Windows |
|---|---|---|
| **OS** | Debian 12/13 or Ubuntu 22.04/24.04+ | Windows 10/11 or Windows Server 2019+ |
| **Access** | Root (sudo) | Administrator |
| **Java** | Installed by setup script (Temurin JDK 25) | Installed by setup script (Temurin JDK 25) |
| **Hytale** | [Hytale Creator Program](https://hytale.com) account with server access | Same |
| **Downloader** | `hytale-downloader-linux-amd64` | `hytale-downloader-windows-amd64.exe` |

## Quick Start

### Linux

```bash
git clone https://github.com/blugart-dev/hytale-server-toolkit.git
cd hytale-server-toolkit/linux

# Full interactive install
sudo bash hytale-setup.sh

# Preview without changes
sudo bash hytale-setup.sh --dry-run

# Automated (non-interactive)
sudo bash hytale-setup.sh --unattended
```

### Windows

Open PowerShell **as Administrator**:

```powershell
git clone https://github.com/blugart-dev/hytale-server-toolkit.git
cd hytale-server-toolkit\windows

# Full interactive install
.\hytale-setup.ps1

# Preview without changes
.\hytale-setup.ps1 -DryRun

# Automated (non-interactive)
.\hytale-setup.ps1 -Unattended

# Custom install directory
.\hytale-setup.ps1 -InstallDir D:\HytaleServer
```

> **Execution Policy:** If you get a script-blocked error, run:
> `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

Both installers walk you through everything interactively. Two steps require a browser for OAuth2 authentication (downloading the server and `/auth login`).

## What the Installer Does

### Linux (10 phases)

| Phase | Description |
|-------|-------------|
| 1 | System updates, prerequisites, fail2ban, timezone, optional SSH hardening |
| 2 | Installs Temurin JDK 25 via Adoptium |
| 3 | Creates `hytale-server` system user and `/opt/hytale` directory |
| 4 | Downloads server files via the Hytale downloader (~3.2 GB) |
| 5 | Auto-tunes JVM heap based on system RAM |
| 6 | Writes `config.json` and `whitelist.json` |
| 7 | Configures UFW firewall (SSH + port 5520/UDP) |
| 8 | Creates systemd service with security hardening |
| 9 | Interactive first run for `/auth login` |
| 10 | Connection info summary |

### Windows (7 phases)

| Phase | Description |
|-------|-------------|
| 1 | Installs Temurin JDK 25 via winget |
| 2 | Creates `C:\HytaleServer` directory structure |
| 3 | Downloads server files via the Hytale downloader (~3.2 GB) |
| 4 | Auto-tunes JVM heap based on system RAM |
| 5 | Writes `config.json` and `whitelist.json` |
| 6 | Creates Windows Firewall rule (UDP 5520 inbound) |
| 7 | Optional auto-start task, `/auth login`, connection info summary |

Both scripts are **idempotent** — safe to re-run. Completed steps are detected and skipped.

## Backup

### Linux

```bash
sudo bash hytale-backup.sh               # Create backup (keeps 7 by default)
sudo bash hytale-backup.sh --keep 3      # Keep only 3 most recent
sudo bash hytale-backup.sh --backup-dir /mnt/backups  # Custom backup directory
sudo bash hytale-backup.sh --dry-run     # Preview
```

### Windows

```powershell
.\hytale-backup.ps1                       # Create backup (keeps 7 by default)
.\hytale-backup.ps1 -Keep 3              # Keep only 3 most recent
.\hytale-backup.ps1 -BackupDir D:\Backups # Custom backup directory
.\hytale-backup.ps1 -DryRun              # Preview
```

Backs up world data, config files, auth credentials, and JVM options. Safe to run while the server is running. Linux uses `.tar.gz`, Windows uses `.zip`.

## Update

### Linux

```bash
sudo bash hytale-update.sh               # Stop, backup, update, restart
sudo bash hytale-update.sh --no-backup   # Skip pre-update backup
sudo bash hytale-update.sh --dry-run     # Preview
```

### Windows

```powershell
.\hytale-update.ps1                       # Stop, backup, update, restart
.\hytale-update.ps1 -NoBackup            # Skip pre-update backup
.\hytale-update.ps1 -DryRun              # Preview
```

Backup runs by default before every update — updates are the #1 cause of data loss.

## Health Check

### Linux

```bash
sudo bash hytale-setup.sh --verify
```

Checks Java, user, systemd service, firewall, config validity, auth, file ownership, and port status.

### Windows

```powershell
.\hytale-setup.ps1 -Verify
```

Checks Java, firewall rule, config validity, auth, directory structure, HytaleServer.jar, scheduled task, server process, and port status.

Both exit 0 if all pass, 1 on errors — suitable for scheduled monitoring.

## Server Management

### Linux (systemd)

```bash
sudo systemctl start hytale-server       # Start
sudo systemctl stop hytale-server        # Stop
sudo systemctl restart hytale-server     # Restart
sudo systemctl status hytale-server      # Status
sudo journalctl -u hytale-server -f      # Live logs
```

### Windows

```powershell
# Start: run start.bat in C:\HytaleServer\server
# Stop:  type /stop in the server console window
# Or use the Scheduled Task if registered during setup
```

## File Layout

### Linux

```
/opt/hytale/
├── server/
│   ├── start.sh
│   ├── jvm.options
│   └── Server/
│       ├── HytaleServer.jar
│       ├── config.json
│       ├── whitelist.json
│       ├── auth.enc
│       ├── universe/              # World data
│       └── logs/
├── backups/                       # Created by hytale-backup.sh
├── hytale-downloader-linux-amd64
└── INSTALL_SUMMARY.txt
```

### Windows

```
C:\HytaleServer\
├── server\
│   ├── start.bat
│   ├── jvm.options
│   └── Server\
│       ├── HytaleServer.jar
│       ├── config.json
│       ├── whitelist.json
│       ├── auth.enc
│       ├── universe\              # World data
│       └── logs\
├── backups\                       # Created by hytale-backup.ps1
├── hytale-downloader-windows-amd64.exe
└── INSTALL_SUMMARY.txt
```

## Windows-Specific Notes

- **Admin elevation:** The setup script auto-elevates to Administrator when needed. Non-admin dry-run still works.
- **winget:** Used to install Java. If winget is unavailable (some Windows Server editions), the script shows a manual download URL.
- **Auto-start:** Optional Scheduled Task at logon (no third-party dependencies like NSSM). Offered during setup, default "no".
- **Backup format:** `.zip` via `Compress-Archive` (native, opens in Windows Explorer).
- **Execution Policy:** You may need to run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` before running the scripts.

## License

MIT
