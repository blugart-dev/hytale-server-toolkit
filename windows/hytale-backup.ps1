# =============================================================================
# Hytale Dedicated Server — Backup Script (Windows)
# =============================================================================
# Creates timestamped .zip backups of server data with automatic rotation.
#
# Usage:
#   .\hytale-backup.ps1 [OPTIONS]
#
# Options:
#   -DryRun         Print what would happen without making changes
#   -Keep N         Number of backups to retain (default: 7)
#   -BackupDir D    Directory for backups (default: C:\HytaleServer\backups)
#   -Help           Show help message
#   -Version        Show version
#
# See: C:\HytaleServer\INSTALL_SUMMARY.txt for server details.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DryRun,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Keep = 7,
    [string]$BackupDir = "",
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

if (-not $BackupDir) {
    $BackupDir = Join-Path $InstallDir "backups"
}

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
Hytale Dedicated Server — Backup Script (Windows)

Usage:
  .\hytale-backup.ps1 [OPTIONS]

Options:
  -DryRun         Print what would happen without making changes
  -Keep N         Number of backups to retain (default: 7)
  -BackupDir D    Directory for backups (default: C:\HytaleServer\backups)
  -Help           Show this help message
  -Version        Show version

What gets backed up:
  - Server\universe\           (world data)
  - Server\config.json         (server configuration)
  - Server\whitelist.json      (whitelist)
  - Server\permissions.json    (permissions)
  - Server\bans.json           (ban list)
  - Server\auth.enc            (authentication credentials)
  - jvm.options                (JVM configuration)

Backups are safe to run while the server is running (hot backup).

Examples:
  .\hytale-backup.ps1                   # Create backup with defaults
  .\hytale-backup.ps1 -DryRun           # Preview without changes
  .\hytale-backup.ps1 -Keep 3           # Keep only 3 most recent backups
"@
    exit 0
}

if ($Version) {
    Write-Host "hytale-backup.ps1 version $ScriptVersion"
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
# Backup Functions
# ---------------------------------------------------------------------------
function New-Backup {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = Join-Path $BackupDir "hytale-backup-$timestamp.zip"

    # Ensure backup directory exists
    if ($DryRun) {
        Write-Dry "Would create directory: $BackupDir"
    } else {
        if (-not (Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
    }

    # Build list of files/dirs to include
    $serverFiles = @("universe", "config.json", "whitelist.json", "permissions.json", "bans.json", "auth.enc")
    $includedServer = @()

    foreach ($f in $serverFiles) {
        $fullPath = Join-Path $ServerWorkDir $f
        if (Test-Path $fullPath) {
            $includedServer += $f
        } else {
            Write-Warn "Skipping missing file: Server\$f"
        }
    }

    # jvm.options is one level up (in server\ not server\Server\)
    $includeJvm = $false
    $jvmPath = Join-Path $ServerDir "jvm.options"
    if (Test-Path $jvmPath) {
        $includeJvm = $true
    } else {
        Write-Warn "Skipping missing file: jvm.options"
    }

    if ($includedServer.Count -eq 0 -and -not $includeJvm) {
        Write-Err "No files found to back up. Is the server installed at $ServerDir?"
        exit 1
    }

    if ($DryRun) {
        Write-Dry "Would create: $backupFile"
        Write-Dry "Files from Server\: $($includedServer -join ', ')"
        if ($includeJvm) { Write-Dry "Also: jvm.options" }
        return
    }

    Write-Info "Creating backup..."

    # Use staging directory for correct archive structure
    $staging = Join-Path $env:TEMP "hytale-backup-staging-$timestamp"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    try {
        # Copy Server/ files to staging
        foreach ($f in $includedServer) {
            $src = Join-Path $ServerWorkDir $f
            $dst = Join-Path $staging $f
            if (Test-Path $src -PathType Container) {
                Copy-Item -Path $src -Destination $dst -Recurse -Force
            } else {
                Copy-Item -Path $src -Destination $dst -Force
            }
        }

        # Copy jvm.options to staging
        if ($includeJvm) {
            Copy-Item -Path $jvmPath -Destination (Join-Path $staging "jvm.options") -Force
        }

        # Create zip from staging contents
        Compress-Archive -Path "$staging\*" -DestinationPath $backupFile -Force

        $backupSize = (Get-Item $backupFile).Length
        $sizeDisplay = if ($backupSize -ge 1MB) {
            "{0:N1} MB" -f ($backupSize / 1MB)
        } else {
            "{0:N0} KB" -f ($backupSize / 1KB)
        }
        Write-Ok "Backup created: $backupFile ($sizeDisplay)"
    } finally {
        # Clean up staging directory
        if (Test-Path $staging) {
            Remove-Item -Path $staging -Recurse -Force
        }
    }
}

function Invoke-BackupRotation {
    if ($DryRun) {
        $count = 0
        if (Test-Path $BackupDir) {
            $count = @(Get-ChildItem -Path $BackupDir -Filter "hytale-backup-*.zip" -ErrorAction SilentlyContinue).Count
        }
        Write-Dry "Would rotate backups (keep $Keep, currently $count)"
        return
    }

    if (-not (Test-Path $BackupDir)) { return }

    $backups = @(Get-ChildItem -Path $BackupDir -Filter "hytale-backup-*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)

    $total = $backups.Count
    if ($total -le $Keep) {
        Write-Info "Backup rotation: $total backups, keeping all (limit: $Keep)"
        return
    }

    $toDelete = $total - $Keep
    Write-Info "Rotating backups: removing $toDelete old backup(s) (keeping $Keep)"

    $backups | Select-Object -Skip $Keep | ForEach-Object {
        Remove-Item -Path $_.FullName -Force
        Write-Info "Removed: $($_.Name)"
    }

    Write-Ok "Backup rotation complete"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Hytale Server — Backup" -ForegroundColor Cyan
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

New-Backup
Invoke-BackupRotation

Write-Host ""
Write-Ok "Backup complete!"
Write-Host ""
