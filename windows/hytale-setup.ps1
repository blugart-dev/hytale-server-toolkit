# =============================================================================
# Hytale Dedicated Server — Automated Installer (Windows)
# =============================================================================
# Sets up a fully working Hytale dedicated server on Windows 10/11 or
# Windows Server 2019+.
#
# Usage:
#   .\hytale-setup.ps1 [OPTIONS]
#
# Options:
#   -DryRun         Print what would happen without making changes
#   -Unattended     Use defaults, skip interactive steps (with warnings)
#   -Verify         Run health checks against an existing install and exit
#   -InstallDir D   Install directory (default: C:\HytaleServer)
#   -Help           Show help message
#   -Version        Show version
#
# Two steps require interactive browser-based OAuth2 and cannot be automated:
#   Phase 3: Hytale downloader authentication (first download)
#   Phase 7: In-game /auth login (server authentication)
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Unattended,
    [switch]$Verify,
    [string]$InstallDir = 'C:\HytaleServer',
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants & Globals
# ---------------------------------------------------------------------------
$ScriptVersion = "1.1.0"
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogFile = Join-Path $InstallDir "setup.log"

$ServerDir = Join-Path $InstallDir "server"
$ServerWorkDir = Join-Path $ServerDir "Server"
$DownloaderBin = "hytale-downloader-windows-amd64.exe"
$DownloaderPath = Join-Path $InstallDir $DownloaderBin

$HytalePort = 5520
$TotalPhases = 7
$CurrentPhase = 0

$TemurinPackage = "EclipseAdoptium.Temurin.25.JDK"
$TemurinDownloadUrl = "https://adoptium.net/temurin/releases/?version=25"

# ---------------------------------------------------------------------------
# Color / Output Helpers
# ---------------------------------------------------------------------------
function Write-Info  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[INFO]" -ForegroundColor Blue -NoNewline; Write-Host " $Msg" }
function Write-Ok    { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[OK]  " -ForegroundColor Green -NoNewline; Write-Host " $Msg" }
function Write-Warn  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[WARN]" -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
function Write-Err   { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[ERROR]" -ForegroundColor Red -NoNewline; Write-Host " $Msg" }
function Write-Skip  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[SKIP]" -ForegroundColor Cyan -NoNewline; Write-Host " $Msg" }
function Write-Dry   { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[DRY] " -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }

function Write-Log {
    param([string]$Msg)
    if ($DryRun) { return }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try { Add-Content -Path $LogFile -Value "[$timestamp] $Msg" -ErrorAction SilentlyContinue } catch {}
}

function Write-PhaseHeader {
    param([int]$Num, [string]$Title)
    $script:CurrentPhase = $Num
    Write-Host ""
    Write-Host "[$Num/$TotalPhases] $Title" -ForegroundColor Green
    Write-Host ("─" * 60) -ForegroundColor Green
    Write-Log "=== Phase $Num/$TotalPhases`: $Title ==="
}

# ---------------------------------------------------------------------------
# Help & Version
# ---------------------------------------------------------------------------
if ($Help) {
    @"
Hytale Dedicated Server — Automated Installer (Windows)

Usage:
  .\hytale-setup.ps1 [OPTIONS]

Options:
  -DryRun         Print what would happen without making any changes
  -Unattended     Use all defaults, skip interactive steps
  -Verify         Run health checks against an existing install and exit
  -InstallDir D   Install directory (default: C:\HytaleServer)
  -Help           Show this help message
  -Version        Show version

Phases:
   1. Install Java            — Temurin JDK 25 via winget
   2. Directory Setup         — C:\HytaleServer structure
   3. Download Hytale Server  — downloader + OAuth2 (interactive)
   4. JVM Tuning              — auto-detect RAM, write jvm.options
   5. Server Configuration    — config.json, whitelist.json
   6. Firewall                — Windows Firewall UDP 5520
   7. Auto-Start, First Run & Summary

Notes:
  Phases 3 and 7 require browser-based OAuth2 and cannot run unattended.
  In -Unattended mode, these phases are skipped if files don't exist.

  The script is idempotent — safe to re-run. Completed steps are skipped.

Examples:
  .\hytale-setup.ps1                    # Full interactive install
  .\hytale-setup.ps1 -DryRun            # Preview without changes
  .\hytale-setup.ps1 -Unattended        # Automated with defaults
  .\hytale-setup.ps1 -Verify            # Health check existing install
"@
    exit 0
}

if ($Version) {
    Write-Host "hytale-setup.ps1 version $ScriptVersion"
    exit 0
}

# ---------------------------------------------------------------------------
# Admin Check
# ---------------------------------------------------------------------------
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------------------------
function Get-PromptValue {
    param([string]$PromptText, [string]$Default)
    if ($Unattended -or $DryRun) { return $Default }
    $response = Read-Host "  $PromptText [$Default]"
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    return $response
}

function Get-PromptYesNo {
    param([string]$PromptText, [string]$Default = "y")
    if ($Unattended -or $DryRun) {
        return ($Default -eq "y")
    }
    $hint = if ($Default -eq "y") { "Y/n" } else { "y/N" }
    $response = Read-Host "  $PromptText [$hint]"
    if ([string]::IsNullOrWhiteSpace($response)) { $response = $Default }
    return ($response -match "^[Yy]")
}

function Get-RamGB {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return [math]::Floor($cs.TotalPhysicalMemory / 1GB)
    } catch {
        return 4
    }
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
            Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    return "unknown"
}

function Get-PublicIP {
    try {
        return (Invoke-RestMethod -Uri "https://ifconfig.me" -TimeoutSec 5 -ErrorAction Stop).Trim()
    } catch {
        return "unknown"
    }
}

function ConvertTo-JsonSafe {
    param([string]$Value)
    $Value = $Value.Replace('\', '\\')
    $Value = $Value.Replace('"', '\"')
    $Value = $Value.Replace("`n", '\n')
    $Value = $Value.Replace("`r", '\r')
    $Value = $Value.Replace("`t", '\t')
    return $Value
}

# ---------------------------------------------------------------------------
# Phase 1: Install Java (Temurin JDK 25)
# ---------------------------------------------------------------------------
function Install-Java {
    Write-PhaseHeader 1 "Install Java (Temurin JDK 25)"

    # Check if Temurin 25 is already installed
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $javaVer = & java -version 2>&1 | Select-Object -First 1
        if ($javaVer -match "25\.") {
            Write-Skip "Temurin JDK 25 already installed"
            Write-Info $javaVer
            return
        } else {
            Write-Info "Java found but not version 25: $javaVer"
        }
    }

    # Try winget first
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Info "Installing $TemurinPackage via winget..."
        if ($DryRun) {
            Write-Dry "Would run: winget install --id $TemurinPackage --accept-package-agreements --accept-source-agreements"
        } else {
            $result = & winget install --id $TemurinPackage --accept-package-agreements --accept-source-agreements 2>&1
            Write-Log "winget output: $result"

            # Refresh PATH after install
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [Environment]::GetEnvironmentVariable("Path", "User")

            # Verify
            $javaCmd = Get-Command java -ErrorAction SilentlyContinue
            if ($javaCmd) {
                $javaVer = & java -version 2>&1 | Select-Object -First 1
                Write-Ok "Java installed: $javaVer"
            } else {
                Write-Warn "Java installed but not found in PATH — you may need to restart PowerShell"
            }
        }
    } else {
        Write-Warn "winget is not available on this system."
        Write-Info "Please install Temurin JDK 25 manually from:"
        Write-Info "  $TemurinDownloadUrl"
        Write-Host ""
        if (-not $Unattended -and -not $DryRun) {
            Read-Host "  Press Enter after installing Java to continue"
            # Refresh PATH
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [Environment]::GetEnvironmentVariable("Path", "User")
            $javaCmd = Get-Command java -ErrorAction SilentlyContinue
            if ($javaCmd) {
                $javaVer = & java -version 2>&1 | Select-Object -First 1
                Write-Ok "Java detected: $javaVer"
            } else {
                Write-Err "Java still not found in PATH after install."
                exit 1
            }
        } else {
            Write-Err "Cannot install Java automatically without winget. Install manually and re-run."
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Phase 2: Directory Setup
# ---------------------------------------------------------------------------
function Initialize-Directories {
    Write-PhaseHeader 2 "Directory Setup"

    $dirs = @(
        $InstallDir,
        $ServerDir,
        $ServerWorkDir,
        (Join-Path $InstallDir "backups")
    )

    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            Write-Skip "Directory already exists: $dir"
        } else {
            if ($DryRun) {
                Write-Dry "Would create directory: $dir"
            } else {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Ok "Created: $dir"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Phase 3: Download Hytale Server
# ---------------------------------------------------------------------------
function Install-HytaleServer {
    Write-PhaseHeader 3 "Download Hytale Server"

    $jarPath = Join-Path $ServerWorkDir "HytaleServer.jar"

    # Check if server files already exist
    if (Test-Path $jarPath) {
        Write-Skip "HytaleServer.jar already present — skipping download"
        return
    }

    # Check for downloader binary
    if (-not (Test-Path $DownloaderPath)) {
        # Look in common locations
        $searchPaths = @(
            (Join-Path $InstallDir $DownloaderBin),
            (Join-Path $env:TEMP $DownloaderBin),
            (Join-Path $env:USERPROFILE "Downloads" $DownloaderBin),
            (Join-Path $env:USERPROFILE $DownloaderBin)
        )

        $foundPath = $null
        foreach ($p in $searchPaths) {
            if ((Test-Path $p) -and ($p -ne $DownloaderPath)) {
                $foundPath = $p
                break
            }
        }

        if ($foundPath) {
            Write-Info "Found downloader at $foundPath, copying..."
            if (-not $DryRun) {
                Copy-Item -Path $foundPath -Destination $DownloaderPath -Force
            } else {
                Write-Dry "Would copy downloader from $foundPath"
            }
        } elseif ($Unattended) {
            Write-Err "Downloader not found at $DownloaderPath"
            Write-Err "Cannot download server in unattended mode without the downloader binary."
            exit 1
        } else {
            Write-Host ""
            Write-Warn "Hytale downloader not found at: $DownloaderPath"
            Write-Host ""
            Write-Host "  Please do one of the following:"
            Write-Host "    1. Place the downloader at: $DownloaderPath"
            Write-Host "    2. Enter the full path to the downloader binary"
            Write-Host ""
            $userPath = Read-Host "  Path to downloader (or press Enter to abort)"
            if ([string]::IsNullOrWhiteSpace($userPath)) {
                Write-Err "Downloader not provided. Cannot continue."
                exit 1
            }
            if (-not (Test-Path $userPath)) {
                Write-Err "File not found: $userPath"
                exit 1
            }
            Copy-Item -Path $userPath -Destination $DownloaderPath -Force
        }
    }

    if ($DryRun) {
        Write-Dry "Would run downloader (requires OAuth2 browser auth)"
        Write-Dry "This downloads ~3.2 GB of server files"
        return
    }

    Write-Host ""
    Write-Info "Starting Hytale server download..."
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "INTERACTIVE STEP:" -ForegroundColor Yellow -NoNewline
    Write-Host " The downloader will display a URL and code."
    Write-Host "  Open the URL in your browser, log in with your Hytale account,"
    Write-Host "  and enter the authorization code. The download will start automatically."
    Write-Host ""
    Write-Host "  Download size: ~3.2 GB"
    Write-Host ""

    if (-not (Get-PromptYesNo "Ready to start the download?" "y")) {
        Write-Warn "Download skipped by user. You can re-run this script later."
        return
    }

    Push-Location $InstallDir
    try {
        & $DownloaderPath
    } finally {
        Pop-Location
    }

    # Verify download
    if (Test-Path $jarPath) {
        Write-Ok "Server downloaded successfully"
    } else {
        Write-Err "Download completed but HytaleServer.jar not found at $ServerWorkDir"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Phase 4: JVM Tuning
# ---------------------------------------------------------------------------
function Set-JvmOptions {
    Write-PhaseHeader 4 "JVM Tuning"

    $jvmFile = Join-Path $ServerDir "jvm.options"

    # Detect RAM
    $totalRamGB = Get-RamGB
    if ($totalRamGB -lt 4) {
        Write-Warn "System has only $totalRamGB GB RAM (minimum recommended: 4 GB)"
        Write-Warn "JVM will be configured with minimum values — expect limited capacity"
    }
    if ($totalRamGB -lt 1) {
        $totalRamGB = 4
        Write-Warn "Could not detect RAM reliably, assuming $totalRamGB GB"
    } else {
        Write-Info "Detected system RAM: $totalRamGB GB"
    }

    # Calculate heap sizes — reserve 2GB for OS
    $availableGB = $totalRamGB - 2
    if ($availableGB -lt 2) { $availableGB = 2 }

    $xmxGB = $availableGB
    $xmsGB = [math]::Floor($availableGB * 80 / 100)

    # Enforce min/max bounds
    if ($xmsGB -lt 2)  { $xmsGB = 2 }
    if ($xmxGB -lt 3)  { $xmxGB = 3 }
    if ($xmsGB -gt 22) { $xmsGB = 22 }
    if ($xmxGB -gt 26) { $xmxGB = 26 }
    if ($xmsGB -gt $xmxGB) { $xmsGB = $xmxGB }

    Write-Info "Calculated JVM heap: -Xms${xmsGB}G / -Xmx${xmxGB}G"

    # Let user adjust in interactive mode
    if (-not $Unattended -and -not $DryRun) {
        Write-Host ""
        Write-Host "  Memory allocation ($totalRamGB GB total, $availableGB GB available for JVM):"
        Write-Host "    Minimum heap (-Xms): ${xmsGB}G"
        Write-Host "    Maximum heap (-Xmx): ${xmxGB}G"
        Write-Host ""
        if (-not (Get-PromptYesNo "Use these values?" "y")) {
            $newXms = Get-PromptValue "Minimum heap in GB (-Xms)" $xmsGB
            $newXmx = Get-PromptValue "Maximum heap in GB (-Xmx)" $xmxGB
            if ($newXms -match '^\d+$' -and $newXmx -match '^\d+$') {
                $xmsGB = [int]$newXms
                $xmxGB = [int]$newXmx
            } else {
                Write-Warn "Invalid input, using calculated values"
            }
        }
    }

    # Check if jvm.options already exists with same values
    if ((Test-Path $jvmFile) -and -not $DryRun) {
        $existing = Get-Content $jvmFile -Raw -ErrorAction SilentlyContinue
        if ($existing -match "-Xms${xmsGB}G" -and $existing -match "-Xmx${xmxGB}G") {
            Write-Skip "jvm.options already configured with -Xms${xmsGB}G / -Xmx${xmxGB}G"
            return
        } else {
            Write-Info "Updating jvm.options with new heap values..."
        }
    }

    $jvmContent = @"
# Hytale Server JVM Options
# Memory: Reserve ~2GB for OS/overhead, allocate rest to JVM
-Xms${xmsGB}G
-Xmx${xmxGB}G

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
"@

    if ($DryRun) {
        Write-Dry "Would write: $jvmFile"
    } else {
        Set-Content -Path $jvmFile -Value $jvmContent -Encoding UTF8
    }

    Write-Ok "jvm.options written: -Xms${xmsGB}G / -Xmx${xmxGB}G (G1GC)"
}

# ---------------------------------------------------------------------------
# Phase 5: Server Configuration
# ---------------------------------------------------------------------------
function Set-ServerConfig {
    Write-PhaseHeader 5 "Server Configuration"

    $configFile = Join-Path $ServerWorkDir "config.json"
    $whitelistFile = Join-Path $ServerWorkDir "whitelist.json"

    # Ensure Server/ directory exists
    if (-not $DryRun -and -not (Test-Path $ServerWorkDir)) {
        New-Item -ItemType Directory -Path $ServerWorkDir -Force | Out-Null
    }

    # Collect configuration values
    $totalRamGB = Get-RamGB
    if ($totalRamGB -lt 4) { $totalRamGB = 4 }

    # Scale defaults to hardware
    $availableGB = $totalRamGB - 2
    if ($availableGB -lt 2) { $availableGB = 2 }
    $defaultPlayers = [math]::Floor($availableGB * 10 / 4)
    if ($defaultPlayers -lt 5)   { $defaultPlayers = 5 }
    if ($defaultPlayers -gt 100) { $defaultPlayers = 100 }

    $defaultViewRadius = 16
    if ($availableGB -ge 12) { $defaultViewRadius = 24 }
    if ($availableGB -ge 20) { $defaultViewRadius = 32 }

    if ($Unattended -or $DryRun) {
        $serverName = "Hytale Server"
        $maxPlayers = $defaultPlayers
        $maxViewRadius = $defaultViewRadius
        $password = ""
        $gameMode = "Adventure"
        if ($DryRun) {
            Write-Info "Would use defaults: $defaultPlayers players, view radius $defaultViewRadius, Adventure mode"
        }
    } else {
        Write-Host ""
        Write-Host "  Configure your Hytale server (press Enter for defaults):"
        Write-Host ""
        $serverName = Get-PromptValue "Server name" "Hytale Server"
        $maxPlayers = Get-PromptValue "Max players" $defaultPlayers
        $maxViewRadius = Get-PromptValue "Max view radius (8-32)" $defaultViewRadius
        $password = Get-PromptValue "Server password (empty = none)" ""
        $gameMode = Get-PromptValue "Default game mode (Adventure/Creative)" "Adventure"
    }

    # Validate numeric inputs
    if ($maxPlayers -notmatch '^\d+$') { $maxPlayers = $defaultPlayers }
    if ($maxViewRadius -notmatch '^\d+$') { $maxViewRadius = $defaultViewRadius }

    # Escape for JSON
    $safeServerName = ConvertTo-JsonSafe $serverName
    $safePassword = ConvertTo-JsonSafe $password
    $safeGameMode = ConvertTo-JsonSafe $gameMode

    if ((Test-Path $configFile) -and -not $DryRun) {
        Write-Info "config.json already exists, overwriting with new values..."
    }

    $configContent = @"
{
  "Version": 4,
  "ServerName": "$safeServerName",
  "MOTD": "",
  "Password": "$safePassword",
  "MaxPlayers": $maxPlayers,
  "MaxViewRadius": $maxViewRadius,
  "Defaults": {
    "World": "default",
    "GameMode": "$safeGameMode"
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
  "Update": {},
  "Backup": {}
}
"@

    if ($DryRun) {
        Write-Dry "Would write: $configFile"
    } else {
        Set-Content -Path $configFile -Value $configContent -Encoding UTF8
    }
    Write-Ok "config.json written ($maxPlayers players, view radius $maxViewRadius)"

    # Write whitelist.json
    if ((Test-Path $whitelistFile) -and -not $DryRun) {
        Write-Skip "whitelist.json already exists"
    } else {
        if ($DryRun) {
            Write-Dry "Would write: $whitelistFile"
        } else {
            Set-Content -Path $whitelistFile -Value '{"enabled": true, "list": []}' -Encoding UTF8
        }
        Write-Ok "whitelist.json written (whitelist enabled)"
    }
}

# ---------------------------------------------------------------------------
# Phase 6: Firewall
# ---------------------------------------------------------------------------
function Set-Firewall {
    Write-PhaseHeader 6 "Firewall"

    $ruleName = "Hytale Server (UDP $HytalePort)"

    # Check if rule already exists
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Skip "Firewall rule already exists: $ruleName"
        return
    }

    if ($DryRun) {
        Write-Dry "Would create firewall rule: $ruleName"
        Write-Dry "  Direction: Inbound, Protocol: UDP, Port: $HytalePort, Action: Allow"
        return
    }

    Write-Info "Creating firewall rule..."
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort $HytalePort `
        -Action Allow `
        -Profile Any `
        -Description "Allow Hytale dedicated server traffic on UDP port $HytalePort" |
        Out-Null

    Write-Ok "Firewall rule created: Allow UDP $HytalePort inbound"
}

# ---------------------------------------------------------------------------
# Phase 7: Auto-Start, First Run & Summary
# ---------------------------------------------------------------------------
function Complete-Setup {
    Write-PhaseHeader 7 "Auto-Start, First Run & Summary"

    # --- Optional Scheduled Task ---
    $taskName = "HytaleServer"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Write-Skip "Scheduled task '$taskName' already registered"
    } elseif (-not $Unattended -and -not $DryRun) {
        Write-Host ""
        Write-Info "Optional: Register a Scheduled Task to start the server at logon"
        if (Get-PromptYesNo "Register auto-start task?" "n") {
            $startBat = Join-Path $ServerDir "start.bat"
            if (Test-Path $startBat) {
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$startBat`"" -WorkingDirectory $ServerDir
                $trigger = New-ScheduledTaskTrigger -AtLogOn
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Start Hytale Dedicated Server at logon" | Out-Null
                Write-Ok "Scheduled task '$taskName' registered (runs at logon)"
            } else {
                Write-Warn "start.bat not found at $startBat — cannot register task"
                Write-Info "Download the server first, then re-run this script."
            }
        }
    } elseif ($DryRun) {
        Write-Dry "Would offer to register scheduled task for auto-start"
    }

    # --- First Run & Auth ---
    $authFile = Join-Path $ServerWorkDir "auth.enc"

    if (Test-Path $authFile) {
        Write-Skip "auth.enc already exists — server is authenticated"
    } elseif ($Unattended) {
        Write-Host ""
        Write-Warn "Server authentication requires interactive browser-based OAuth2."
        Write-Warn "Skipping first run in unattended mode."
        Write-Host ""
        Write-Host "  To authenticate manually, run:"
        Write-Host ""
        Write-Host "    cd $ServerWorkDir"
        Write-Host "    java @..\jvm.options -jar HytaleServer.jar --assets ..\Assets.zip"
        Write-Host ""
        Write-Host "  Then type: /auth login"
        Write-Host "  Follow the browser prompts, then type: /stop"
        Write-Host ""
    } elseif ($DryRun) {
        Write-Dry "Would run server interactively for /auth login"
        Write-Dry "This requires browser-based OAuth2 authentication"
    } else {
        $jvmFile = Join-Path $ServerDir "jvm.options"
        $jarFile = Join-Path $ServerWorkDir "HytaleServer.jar"
        $assetsFile = Join-Path $ServerDir "Assets.zip"

        if (-not (Test-Path $jarFile)) {
            Write-Warn "HytaleServer.jar not found — skipping first run"
            Write-Info "Download the server first, then re-run this script."
        } else {
            Write-Host ""
            Write-Host "  " -NoNewline
            Write-Host "INTERACTIVE STEP: Server Authentication" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  The server will start interactively. Once you see:"
            Write-Host "    [ServerAuthManager] No server tokens configured. Use /auth login..."
            Write-Host ""
            Write-Host "  Type:  /auth login"
            Write-Host ""
            Write-Host "  A URL and code will appear. Open the URL in your browser,"
            Write-Host "  log in with your Hytale account, and enter the code."
            Write-Host ""
            Write-Host "  Once authenticated, type:  /stop"
            Write-Host ""

            if (Get-PromptYesNo "Ready to start the server for authentication?" "y") {
                Write-Host ""
                Write-Info "Starting server... (this may take a moment)"
                Write-Host ""

                Push-Location $ServerWorkDir
                try {
                    $javaArgs = @()
                    if (Test-Path $jvmFile) { $javaArgs += '@..\jvm.options' }
                    $javaArgs += '-jar'
                    $javaArgs += 'HytaleServer.jar'
                    if (Test-Path $assetsFile) { $javaArgs += '--assets'; $javaArgs += '..\Assets.zip' }
                    & java @javaArgs
                } finally {
                    Pop-Location
                }

                Write-Host ""
                if (Test-Path $authFile) {
                    Write-Ok "Authentication successful — auth.enc created"
                } else {
                    Write-Warn "auth.enc not found — authentication may not have completed"
                    Write-Warn "You can re-run this script or authenticate manually"
                }
            } else {
                Write-Warn "First run skipped. You'll need to authenticate manually."
            }
        }
    }

    # --- Summary ---
    $localIP = Get-LocalIP
    $publicIP = Get-PublicIP

    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                                           ║" -ForegroundColor Green
    Write-Host "  ║            Hytale Server Setup Complete!                   ║" -ForegroundColor Green
    Write-Host "  ║                                                           ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    Write-Host "  Connection Info"
    Write-Host "  ──────────────────────────────────────"
    Write-Host "  Local IP:    $localIP"
    Write-Host "  Public IP:   $publicIP"
    Write-Host "  Port:        $HytalePort/UDP"
    Write-Host ""
    Write-Host "  LAN connect: ${localIP}:$HytalePort"
    Write-Host "  WAN connect: ${publicIP}:$HytalePort"
    Write-Host ""

    if ($publicIP -ne "unknown" -and $localIP -ne "unknown") {
        Write-Host "  If hosting from home, set up port forwarding:"
        Write-Host "    Protocol: UDP | External: $HytalePort | Internal: ${localIP}:$HytalePort"
        Write-Host ""
    }

    Write-Host "  Management"
    Write-Host "  ──────────────────────────────────────"
    Write-Host "  Start:       Run start.bat in $ServerDir"
    Write-Host "  Stop:        Type /stop in the server console"
    Write-Host ""

    Write-Host "  Important File Paths"
    Write-Host "  ──────────────────────────────────────"
    Write-Host "  Config:      $ServerWorkDir\config.json"
    Write-Host "  Whitelist:   $ServerWorkDir\whitelist.json"
    Write-Host "  JVM options: $ServerDir\jvm.options"
    Write-Host "  Start script:$ServerDir\start.bat"
    Write-Host "  World data:  $ServerWorkDir\universe\"
    Write-Host "  Auth creds:  $ServerWorkDir\auth.enc"
    Write-Host ""

    Write-Host "  Update & Backup"
    Write-Host "  ──────────────────────────────────────"
    Write-Host "  Update:      .\hytale-update.ps1"
    Write-Host "  Backup:      .\hytale-backup.ps1"
    Write-Host "  Verify:      .\hytale-setup.ps1 -Verify"
    Write-Host ""

    # Save install summary
    $summaryContent = @"
Hytale Server — Install Summary
Generated: $(Get-Date)
================================================

Connection Info
  Local IP:    $localIP
  Public IP:   $publicIP
  Port:        $HytalePort/UDP
  LAN connect: ${localIP}:$HytalePort
  WAN connect: ${publicIP}:$HytalePort

Management
  Start:       Run start.bat in $ServerDir
  Stop:        Type /stop in the server console

Important File Paths
  Config:      $ServerWorkDir\config.json
  Whitelist:   $ServerWorkDir\whitelist.json
  JVM options: $ServerDir\jvm.options
  Start script:$ServerDir\start.bat
  World data:  $ServerWorkDir\universe\
  Auth creds:  $ServerWorkDir\auth.enc

Update Server
  .\hytale-update.ps1

Backup Server
  .\hytale-backup.ps1
"@

    if ($DryRun) {
        Write-Dry "Would save install summary to $InstallDir\INSTALL_SUMMARY.txt"
    } else {
        Set-Content -Path (Join-Path $InstallDir "INSTALL_SUMMARY.txt") -Value $summaryContent -Encoding UTF8
        Write-Ok "Install summary saved to $InstallDir\INSTALL_SUMMARY.txt"
    }

    if ($DryRun) {
        Write-Host "  " -NoNewline
        Write-Host "DRY RUN COMPLETE — no changes were made." -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Ok "Setup complete! Happy building!"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Verify (-Verify flag)
# ---------------------------------------------------------------------------
function Invoke-Verify {
    Write-Host ""
    Write-Host "Hytale Server — Health Check" -ForegroundColor Cyan
    Write-Host ("─" * 60) -ForegroundColor Cyan
    Write-Host ""

    $errors = 0

    # Check 1: Java version 25
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $javaVer = & java -version 2>&1 | Select-Object -First 1
        if ($javaVer -match "25\.") {
            Write-Ok "  Java 25 installed"
        } else {
            Write-Err "  Java 25 not found (got: $javaVer)"
            $errors++
        }
    } else {
        Write-Err "  Java not installed"
        $errors++
    }

    # Check 2: Firewall rule
    $fwRule = Get-NetFirewallRule -DisplayName "Hytale*" -ErrorAction SilentlyContinue
    if ($fwRule) {
        Write-Ok "  Firewall rule exists for Hytale"
    } else {
        Write-Err "  Firewall rule for Hytale not found"
        $errors++
    }

    # Check 3: config.json valid
    $configFile = Join-Path $ServerWorkDir "config.json"
    if (Test-Path $configFile) {
        try {
            Get-Content $configFile -Raw | ConvertFrom-Json | Out-Null
            Write-Ok "  config.json is valid JSON"
        } catch {
            Write-Err "  config.json is not valid JSON"
            $errors++
        }
    } else {
        Write-Err "  config.json not found at $configFile"
        $errors++
    }

    # Check 4: auth.enc exists
    $authFile = Join-Path $ServerWorkDir "auth.enc"
    if (Test-Path $authFile) {
        Write-Ok "  auth.enc exists"
    } else {
        Write-Err "  auth.enc not found at $authFile"
        $errors++
    }

    # Check 5: Server directory structure
    if (Test-Path $ServerWorkDir) {
        Write-Ok "  Server directory exists: $ServerWorkDir"
    } else {
        Write-Err "  Server directory not found: $ServerWorkDir"
        $errors++
    }

    # Check 6: HytaleServer.jar exists
    $jarFile = Join-Path $ServerWorkDir "HytaleServer.jar"
    if (Test-Path $jarFile) {
        Write-Ok "  HytaleServer.jar exists"
    } else {
        Write-Err "  HytaleServer.jar not found at $jarFile"
        $errors++
    }

    # Check 7: Scheduled task (if registered)
    $task = Get-ScheduledTask -TaskName "HytaleServer" -ErrorAction SilentlyContinue
    if ($task) {
        Write-Ok "  Scheduled task 'HytaleServer' registered (State: $($task.State))"
    } else {
        Write-Skip "  No scheduled task registered (optional)"
    }

    # Check 8: Server process running
    $serverProc = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*HytaleServer.jar*' } |
        Select-Object -First 1
    $serverRunning = $false
    if ($serverProc) {
        Write-Ok "  Server process running (PID: $($serverProc.ProcessId))"
        $serverRunning = $true
    } else {
        Write-Warn "  Server process not running (may be intentionally stopped)"
    }

    # Check 9: Port 5520 listening (only if server running)
    if ($serverRunning) {
        $udpEndpoint = Get-NetUDPEndpoint -LocalPort $HytalePort -ErrorAction SilentlyContinue
        if ($udpEndpoint) {
            Write-Ok "  Port $HytalePort/UDP is listening"
        } else {
            Write-Warn "  Port $HytalePort/UDP not listening (server may still be starting)"
        }
    }

    Write-Host ""
    if ($errors -eq 0) {
        Write-Host "  All checks passed." -ForegroundColor Green
    } else {
        Write-Host "  $errors check(s) failed." -ForegroundColor Red
    }
    Write-Host ""

    if ($errors -eq 0) { exit 0 } else { exit 1 }
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
function Show-Banner {
    Write-Host ""
    Write-Host "   ╦ ╦╦ ╦╔╦╗╔═╗╦  ╔═╗" -ForegroundColor Cyan
    Write-Host "   ╠═╣╚╦╝ ║ ╠═╣║  ║╣ " -ForegroundColor Cyan
    Write-Host "   ╩ ╩ ╩  ╩ ╩ ╩╩═╝╚═╝" -ForegroundColor Cyan
    Write-Host "   Server Automated Installer (Windows)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Version $ScriptVersion"
    if ($DryRun) {
        Write-Host "  Mode: " -NoNewline; Write-Host "DRY RUN" -ForegroundColor Yellow -NoNewline; Write-Host " (no changes will be made)"
    } elseif ($Unattended) {
        Write-Host "  Mode: " -NoNewline; Write-Host "UNATTENDED" -ForegroundColor Cyan -NoNewline; Write-Host " (using defaults)"
    } else {
        Write-Host "  Mode: " -NoNewline; Write-Host "INTERACTIVE" -ForegroundColor Green
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Main Entrypoint
# ---------------------------------------------------------------------------

# Verify mode — run health checks and exit
if ($Verify) {
    Invoke-Verify
}

# Check admin
if (-not (Test-Admin)) {
    if ($DryRun) {
        Write-Warn "Not running as Administrator — dry-run will still show all phases"
    } else {
        # Attempt self-elevation
        Write-Info "Requesting Administrator privileges..."
        try {
            $argList = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
            if ($DryRun) { $argList += " -DryRun" }
            if ($Unattended) { $argList += " -Unattended" }
            if ($Verify) { $argList += " -Verify" }
            if ($InstallDir -ne 'C:\HytaleServer') { $argList += " -InstallDir `"$InstallDir`"" }
            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
            exit 0
        } catch {
            Write-Err "Failed to elevate to Administrator. Please run as Administrator."
            exit 1
        }
    }
}

# Initialize log
if (-not $DryRun) {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Write-Log "=== Hytale Server Setup — $(Get-Date) ==="
    Write-Log "Version: $ScriptVersion"
    Write-Log "Mode: DryRun=$DryRun Unattended=$Unattended"
}

Show-Banner

Install-Java
Initialize-Directories
Install-HytaleServer
Set-JvmOptions
Set-ServerConfig
Set-Firewall
Complete-Setup
