# =============================================================================
# Hytale Dedicated Server — Update Script (Windows)
# =============================================================================
# Stops the server, optionally backs up, runs the downloader, and restarts.
#
# Usage:
#   .\hytale-update.ps1 [OPTIONS]
#
# Options:
#   -DryRun         Print what would happen without making changes
#   -NoBackup       Skip pre-update backup
#   -Help           Show help message
#   -Version        Show version
#
# Note: The downloader may prompt for OAuth2 re-authentication if the
#       session has expired. Have a browser ready.
#
# See: C:\HytaleServer\INSTALL_SUMMARY.txt for server details.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoBackup,
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

$InstallDir = "C:\HytaleServer"
$ServerDir = Join-Path $InstallDir "server"
$ServerWorkDir = Join-Path $ServerDir "Server"
$DownloaderBin = "hytale-downloader-windows-amd64.exe"
$DownloaderPath = Join-Path $InstallDir $DownloaderBin
$BackupScript = Join-Path $ScriptDir "hytale-backup.ps1"


# ---------------------------------------------------------------------------
# Color / Output Helpers
# ---------------------------------------------------------------------------
function Write-Info  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[INFO]" -ForegroundColor Blue -NoNewline; Write-Host " $Msg" }
function Write-Ok    { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[OK]  " -ForegroundColor Green -NoNewline; Write-Host " $Msg" }
function Write-Warn  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[WARN]" -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
function Write-Err   { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[ERROR]" -ForegroundColor Red -NoNewline; Write-Host " $Msg" }
function Write-Skip  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[SKIP]" -ForegroundColor Cyan -NoNewline; Write-Host " $Msg" }
function Write-Dry   { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "[DRY] " -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }

# ---------------------------------------------------------------------------
# Help & Version
# ---------------------------------------------------------------------------
if ($Help) {
    @"
Hytale Dedicated Server — Update Script (Windows)

Usage:
  .\hytale-update.ps1 [OPTIONS]

Options:
  -DryRun         Print what would happen without making changes
  -NoBackup       Skip pre-update backup
  -Help           Show this help message
  -Version        Show version

Steps performed:
  1. Stop server (if running)
  2. Create backup (unless -NoBackup)
  3. Run the Hytale downloader to fetch updates
  4. Start server

Note: The downloader may prompt for OAuth2 re-authentication if the
      session has expired. Have a browser ready when running this script.

Examples:
  .\hytale-update.ps1                   # Full update with backup
  .\hytale-update.ps1 -DryRun           # Preview without changes
  .\hytale-update.ps1 -NoBackup         # Update without backup
"@
    exit 0
}

if ($Version) {
    Write-Host "hytale-update.ps1 version $ScriptVersion"
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
# Update Functions
# ---------------------------------------------------------------------------
function Test-Downloader {
    if (-not (Test-Path $DownloaderPath)) {
        Write-Err "Downloader not found at $DownloaderPath"
        exit 1
    }
    Write-Ok "Downloader found: $DownloaderPath"
}

function Stop-HytaleServer {
    # Find the Hytale server Java process
    $serverProc = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*HytaleServer.jar*' } |
        Select-Object -First 1

    if ($serverProc) {
        $serverPid = $serverProc.ProcessId
        if ($DryRun) {
            Write-Dry "Would stop Hytale server (PID: $serverPid)"
        } else {
            Write-Info "Stopping Hytale server (PID: $serverPid)..."
            # Try graceful stop first
            Stop-Process -Id $serverPid -ErrorAction SilentlyContinue
            try {
                Wait-Process -Id $serverPid -Timeout 60
            } catch [System.TimeoutException] {
                Write-Warn "Graceful stop timed out — force killing..."
                Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
            } catch {
                # Process already exited before Wait-Process ran
            }
            Write-Ok "Server stopped"
        }
    } else {
        Write-Info "Server is not running"
    }
}

function Invoke-PreBackup {
    if ($NoBackup) {
        Write-Info "Backup skipped (-NoBackup)"
        return
    }

    if (-not (Test-Path $BackupScript)) {
        Write-Warn "Backup script not found at $BackupScript — skipping backup"
        return
    }

    Write-Info "Running pre-update backup..."
    if ($DryRun) {
        & $BackupScript -DryRun
    } else {
        & $BackupScript
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Err "Backup failed (exit code: $LASTEXITCODE) — aborting update"
            exit 1
        }
    }
    Write-Ok "Pre-update backup complete"
}

function Invoke-Downloader {
    Write-Info "Running Hytale downloader..."
    if ($DryRun) {
        Write-Dry "Would run: $DownloaderPath"
        return
    }

    Push-Location $InstallDir
    try {
        & $DownloaderPath
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Err "Downloader failed (exit code: $LASTEXITCODE)"
            exit 1
        }
    } finally {
        Pop-Location
    }
    Write-Ok "Downloader finished"
}

function Start-HytaleServer {
    $startBat = Join-Path $ServerDir "start.bat"
    if (-not (Test-Path $startBat)) {
        Write-Warn "start.bat not found at $startBat — cannot auto-start"
        Write-Info "Start the server manually after verifying the update."
        return
    }

    Write-Info "Starting Hytale server..."
    if ($DryRun) {
        Write-Dry "Would start server via start.bat"
        return
    }

    # Start in its own window so this script can exit cleanly
    Start-Process -FilePath (Join-Path $ServerDir "start.bat") -WorkingDirectory $ServerDir

    # Brief wait then check
    Start-Sleep -Seconds 3
    $serverProc = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*HytaleServer.jar*' } |
        Select-Object -First 1

    if ($serverProc) {
        Write-Ok "Server started successfully (PID: $($serverProc.ProcessId))"
    } else {
        Write-Warn "Server may not have started — check the server console window"
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Hytale Server — Update" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Mode: " -NoNewline; Write-Host "DRY RUN" -ForegroundColor Yellow
}
Write-Host ""

# Check admin
if (-not (Test-Admin)) {
    if ($DryRun) {
        Write-Warn "Not running as Administrator — dry-run will still show actions"
    } else {
        Write-Err "This script must be run as Administrator."
        Write-Info "Right-click PowerShell and select 'Run as Administrator'."
        exit 1
    }
}

Test-Downloader
Stop-HytaleServer
Invoke-PreBackup
Invoke-Downloader
Start-HytaleServer

Write-Host ""
Write-Ok "Update complete!"
Write-Host ""
