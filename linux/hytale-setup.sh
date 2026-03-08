#!/usr/bin/env bash
# =============================================================================
# Hytale Dedicated Server — Automated Installer
# =============================================================================
# Sets up a fully working, production-ready Hytale dedicated server on
# Debian 12/13 or Ubuntu 22.04/24.04+ from a fresh OS install.
#
# Usage:
#   sudo bash hytale-setup.sh [OPTIONS]
#
# Options:
#   --dry-run       Print what would happen without making changes
#   --unattended    Use defaults, skip interactive steps (with warnings)
#   --verify        Run health checks against an existing install and exit
#   --help          Show help message
#   --version       Show version
#
# Two steps require interactive browser-based OAuth2 and cannot be automated:
#   Phase 4: Hytale downloader authentication (first download)
#   Phase 9: In-game /auth login (server authentication)
#
# See: /opt/hytale/HYTALE_SERVER_TUTORIAL.md for the full manual guide.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & Globals
# ---------------------------------------------------------------------------
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/hytale-setup.log"

readonly HYTALE_USER="hytale-server"
readonly HYTALE_HOME="/opt/hytale"
readonly SERVER_DIR="${HYTALE_HOME}/server"
readonly SERVER_WORK_DIR="${SERVER_DIR}/Server"
readonly DOWNLOADER_BIN="hytale-downloader-linux-amd64"
readonly DOWNLOADER_PATH="${HYTALE_HOME}/${DOWNLOADER_BIN}"

readonly HYTALE_PORT=5520
readonly SSH_PORT=22
readonly TOTAL_PHASES=10

readonly ADOPTIUM_GPG_URL="https://packages.adoptium.net/artifactory/api/gpg/key/public"
readonly ADOPTIUM_GPG_PATH="/usr/share/keyrings/adoptium.gpg"
readonly ADOPTIUM_LIST="/etc/apt/sources.list.d/adoptium.list"
readonly ADOPTIUM_REPO="deb [signed-by=${ADOPTIUM_GPG_PATH}] https://packages.adoptium.net/artifactory/deb bookworm main"
readonly JAVA_PACKAGE="temurin-25-jdk"

readonly SYSTEMD_SERVICE="/etc/systemd/system/hytale-server.service"
readonly FAIL2BAN_JAIL="/etc/fail2ban/jail.local"

# Mutable globals
DRY_RUN=false
UNATTENDED=false
VERIFY=false
CURRENT_PHASE=0

# ---------------------------------------------------------------------------
# Color / Output Helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_RESET=''
fi

log() {
    $DRY_RUN && return 0
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    { echo "$msg" >> "$LOG_FILE"; } 2>/dev/null || true
}

info() {
    local msg="$*"
    echo -e "  ${C_BLUE}[INFO]${C_RESET} ${msg}"
    log "INFO: ${msg}"
}

ok() {
    local msg="$*"
    echo -e "  ${C_GREEN}[OK]${C_RESET}   ${msg}"
    log "OK: ${msg}"
}

skip() {
    local msg="$*"
    echo -e "  ${C_CYAN}[SKIP]${C_RESET} ${msg}"
    log "SKIP: ${msg}"
}

warn() {
    local msg="$*"
    echo -e "  ${C_YELLOW}[WARN]${C_RESET} ${msg}"
    log "WARN: ${msg}"
}

error() {
    local msg="$*"
    echo -e "  ${C_RED}[ERROR]${C_RESET} ${msg}" >&2
    log "ERROR: ${msg}"
}

fatal() {
    error "$@"
    echo -e "  ${C_RED}Setup aborted. Check ${LOG_FILE} for details.${C_RESET}" >&2
    exit 1
}

phase_header() {
    local num="$1"
    local title="$2"
    CURRENT_PHASE=$num
    echo ""
    echo -e "${C_BOLD}${C_GREEN}[${num}/${TOTAL_PHASES}] ${title}${C_RESET}"
    echo -e "${C_GREEN}$(printf '%.0s─' {1..60})${C_RESET}"
    log "=== Phase ${num}/${TOTAL_PHASES}: ${title} ==="
}

# ---------------------------------------------------------------------------
# ERR Trap — clear failure messages with line numbers
# ---------------------------------------------------------------------------
trap_err() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    error "Command failed at line ${line_no} (exit code ${exit_code})"
    error "Phase: ${CURRENT_PHASE}/${TOTAL_PHASES}"
    error "Check ${LOG_FILE} for details."
    exit "$exit_code"
}
trap 'trap_err ${LINENO}' ERR

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
show_help() {
    cat <<'HELPEOF'
Hytale Dedicated Server — Automated Installer

Usage:
  sudo bash hytale-setup.sh [OPTIONS]

Options:
  --dry-run       Print what would happen without making any changes
  --unattended    Use all defaults, skip interactive steps
  --verify        Run health checks against an existing install and exit
  --help          Show this help message
  --version       Show version

Phases:
   1. System Preparation     — updates, prereqs, fail2ban
   2. Install Java            — Temurin JDK 25 via Adoptium
   3. User & Directory Setup  — hytale-server user, /opt/hytale
   4. Download Hytale Server  — downloader + OAuth2 (interactive)
   5. JVM Tuning              — auto-detect RAM, write jvm.options
   6. Server Configuration    — config.json, whitelist.json
   7. Firewall (UFW)          — SSH + Hytale port 5520/UDP
   8. Systemd Service         — auto-start, security hardening
   9. First Run & Auth        — /auth login (interactive)
  10. Summary                 — connection info, cheat sheet

Notes:
  Phases 4 and 9 require browser-based OAuth2 and cannot run unattended.
  In --unattended mode, these phases are skipped if files don't exist.

  The script is idempotent — safe to re-run. Completed steps are skipped.

Examples:
  sudo bash hytale-setup.sh               # Full interactive install
  sudo bash hytale-setup.sh --dry-run     # Preview without changes
  sudo bash hytale-setup.sh --unattended  # Automated with defaults
  sudo bash hytale-setup.sh --verify      # Health check existing install
HELPEOF
    exit 0
}

show_version() {
    echo "hytale-setup.sh version ${SCRIPT_VERSION}"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)   DRY_RUN=true ;;
            --unattended) UNATTENDED=true ;;
            --verify)    VERIFY=true ;;
            --help|-h)   show_help ;;
            --version|-v) show_version ;;
            *)
                error "Unknown option: $1"
                echo "  Run '${SCRIPT_NAME} --help' for usage."
                exit 1
                ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------------------------

# Execute a command, respecting --dry-run mode.
# Usage: run_cmd "description" command arg1 arg2 ...
run_cmd() {
    local desc="$1"
    shift
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  ${desc}"
        echo -e "         \$ $*"
        log "DRY-RUN: ${desc} — $*"
        return 0
    fi
    log "RUN: $*"
    if "$@" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local rc=$?
        error "${desc} failed (exit code ${rc})"
        return "$rc"
    fi
}

# Write content to a file, respecting --dry-run mode.
# Usage: write_file "/path/to/file" <<'EOF' ... EOF
write_file() {
    local filepath="$1"
    local content
    content=$(cat)
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would write: ${filepath}"
        log "DRY-RUN: Would write ${filepath}"
        return 0
    fi
    printf '%s\n' "$content" > "$filepath"
    log "WROTE: ${filepath}"
}

# Prompt for a value with a default. Returns default in unattended/dry-run mode.
# Usage: result=$(prompt_value "Server name" "Hytale Server")
prompt_value() {
    local prompt_text="$1"
    local default="$2"
    if $UNATTENDED || $DRY_RUN; then
        echo "$default"
        return 0
    fi
    local input
    read -rp "  ${prompt_text} [${default}]: " input
    echo "${input:-$default}"
}

# Prompt yes/no with a default. Returns 0 for yes, 1 for no.
# Returns default in unattended/dry-run mode.
# Usage: if prompt_yes_no "Continue?" "y"; then ...
prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-y}"
    if $UNATTENDED || $DRY_RUN; then
        if [[ "$default" == "y" ]]; then return 0; else return 1; fi
    fi
    local hint
    [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
    local input
    read -rp "  ${prompt_text} [${hint}]: " input
    input="${input:-$default}"
    [[ "${input,,}" == "y" || "${input,,}" == "yes" ]]
}

# Detect total system RAM in GB (integer).
detect_ram_gb() {
    local kb
    kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
    echo $(( kb / 1024 / 1024 ))
}

# Get local IP address (first non-loopback).
get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Get public IP address.
get_public_ip() {
    curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown"
}

# Check if a package is installed.
is_pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Check if a command exists.
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Escape a string for safe embedding in JSON.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"      # backslash first
    s="${s//\"/\\\"}"      # double-quote
    s="${s//$'\n'/\\n}"    # newline
    s="${s//$'\r'/\\r}"    # carriage return
    s="${s//$'\t'/\\t}"    # tab
    printf '%s' "$s"
}

# Detect OS distribution.
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID}:${VERSION_ID:-unknown}:${VERSION_CODENAME:-unknown}"
    else
        echo "unknown:unknown:unknown"
    fi
}

# Validate that the OS is supported.
validate_os() {
    local os_info
    os_info=$(detect_os)
    local distro version codename
    IFS=':' read -r distro version codename <<< "$os_info"

    case "$distro" in
        debian)
            if [[ "$version" =~ ^(12|13) ]]; then
                ok "Detected Debian ${version} (${codename})"
                return 0
            fi
            ;;
        ubuntu)
            local major="${version%%.*}"
            if (( major >= 22 )); then
                ok "Detected Ubuntu ${version} (${codename})"
                return 0
            fi
            ;;
    esac

    warn "Detected ${distro} ${version} — not officially tested"
    warn "This script is designed for Debian 12/13 or Ubuntu 22.04/24.04+"
    if ! $UNATTENDED; then
        if ! prompt_yes_no "Continue anyway?"; then
            fatal "Aborted by user."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Phase 1: System Preparation
# ---------------------------------------------------------------------------
phase_system_prep() {
    phase_header 1 "System Preparation"

    # Verify root (allow dry-run as non-root for testing)
    if [[ $EUID -ne 0 ]]; then
        if $DRY_RUN; then
            warn "Not running as root — dry-run will still show all phases"
        else
            fatal "This script must be run as root (use sudo)."
        fi
    else
        ok "Running as root"
    fi

    # Detect and validate OS
    validate_os

    # Update package lists and upgrade
    info "Updating system packages..."
    run_cmd "apt update" apt-get update -qq
    run_cmd "apt upgrade" apt-get upgrade -y -qq
    ok "System packages updated"

    # Install prerequisites
    local prereqs=(curl wget unzip nano gnupg ca-certificates)
    local to_install=()
    for pkg in "${prereqs[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        info "Installing prerequisites: ${to_install[*]}"
        run_cmd "Install prereqs" apt-get install -y -qq "${to_install[@]}"
        ok "Prerequisites installed"
    else
        skip "Prerequisites already installed"
    fi

    # Install utility tools
    local utilities=(screen tmux htop)
    local util_install=()
    for pkg in "${utilities[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            util_install+=("$pkg")
        fi
    done
    if [[ ${#util_install[@]} -gt 0 ]]; then
        info "Installing utilities: ${util_install[*]}"
        run_cmd "Install utilities" apt-get install -y -qq "${util_install[@]}"
        ok "Utilities installed"
    else
        skip "Utilities already installed"
    fi

    # Install and configure fail2ban
    if ! is_pkg_installed "fail2ban"; then
        info "Installing fail2ban..."
        run_cmd "Install fail2ban" apt-get install -y -qq fail2ban
        ok "fail2ban installed"
    else
        skip "fail2ban already installed"
    fi

    if [[ ! -f "$FAIL2BAN_JAIL" ]]; then
        info "Configuring fail2ban..."
        write_file "$FAIL2BAN_JAIL" <<'EOF'
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
EOF
        run_cmd "Enable fail2ban" systemctl enable fail2ban
        run_cmd "Start fail2ban" systemctl restart fail2ban
        ok "fail2ban configured (5 retries, 1h ban)"
    else
        skip "fail2ban already configured"
    fi

    # --- Timezone Configuration ---
    local current_tz="unknown"
    if cmd_exists timedatectl; then
        current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "unknown")
    fi
    info "Current timezone: ${current_tz}"

    if ! $UNATTENDED && ! $DRY_RUN; then
        if ! prompt_yes_no "Is this timezone correct?" "y"; then
            echo ""
            echo "  Common timezones:"
            echo "    America/New_York    America/Chicago    America/Denver"
            echo "    America/Los_Angeles Europe/London      Europe/Paris"
            echo "    Europe/Berlin       Asia/Tokyo         Australia/Sydney"
            echo ""
            local new_tz
            new_tz=$(prompt_value "Enter timezone" "$current_tz")
            if timedatectl list-timezones 2>/dev/null | grep -qx "$new_tz"; then
                run_cmd "Set timezone to ${new_tz}" timedatectl set-timezone "$new_tz"
                ok "Timezone set to ${new_tz}"
            else
                warn "Invalid timezone '${new_tz}' — keeping ${current_tz}"
            fi
        fi
    fi

    # --- SSH Hardening (opt-in, interactive only) ---
    if ! $UNATTENDED && ! $DRY_RUN; then
        echo ""
        info "Optional: disable SSH password authentication (key-only login)"
        if prompt_yes_no "Harden SSH by disabling password authentication?" "n"; then
            # Pre-flight: ensure SSH keys exist
            local root_keys="${HOME}/.ssh/authorized_keys"
            local sudo_keys=""
            [[ -n "${SUDO_USER:-}" ]] && sudo_keys="$(eval echo "~${SUDO_USER}")/.ssh/authorized_keys"

            local has_keys=false
            if [[ -f "$root_keys" ]] && [[ -s "$root_keys" ]]; then
                has_keys=true
            elif [[ -n "$sudo_keys" ]] && [[ -f "$sudo_keys" ]] && [[ -s "$sudo_keys" ]]; then
                has_keys=true
            fi

            if ! $has_keys; then
                warn "No SSH authorized_keys found — refusing to disable password auth"
                warn "Add your SSH public key first, then re-run this script"
            else
                echo ""
                warn "This will disable password login for ALL users via SSH."
                warn "You MUST have working SSH key access before proceeding."
                if prompt_yes_no "Are you sure? (double confirmation)" "n"; then
                    local sshd_config="/etc/ssh/sshd_config"
                    if grep -q "^PasswordAuthentication" "$sshd_config" 2>/dev/null; then
                        sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
                    elif grep -q "^#PasswordAuthentication" "$sshd_config" 2>/dev/null; then
                        sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
                    else
                        echo "PasswordAuthentication no" >> "$sshd_config"
                    fi
                    run_cmd "Restart sshd" systemctl restart sshd
                    ok "SSH password authentication disabled"
                else
                    info "SSH hardening skipped"
                fi
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Phase 2: Install Java (Temurin JDK 25)
# ---------------------------------------------------------------------------
phase_install_java() {
    phase_header 2 "Install Java (Temurin JDK 25)"

    # Check if Temurin 25 is already installed
    if cmd_exists java; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 || true)
        if echo "$java_ver" | grep -q "25\."; then
            skip "Temurin JDK 25 already installed"
            info "$java_ver"
            return 0
        else
            info "Java found but not version 25: $java_ver"
        fi
    fi

    # Add Adoptium GPG key
    if [[ ! -f "$ADOPTIUM_GPG_PATH" ]]; then
        info "Adding Adoptium GPG key..."
        if $DRY_RUN; then
            echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would download and install Adoptium GPG key"
        else
            wget -qO - "$ADOPTIUM_GPG_URL" | gpg --dearmor -o "$ADOPTIUM_GPG_PATH"
        fi
        ok "Adoptium GPG key added"
    else
        skip "Adoptium GPG key already present"
    fi

    # Add Adoptium repository
    if [[ ! -f "$ADOPTIUM_LIST" ]]; then
        info "Adding Adoptium repository (bookworm)..."
        write_file "$ADOPTIUM_LIST" <<EOF
${ADOPTIUM_REPO}
EOF
        ok "Adoptium repository added"
    else
        skip "Adoptium repository already configured"
    fi

    # Install Java
    info "Installing ${JAVA_PACKAGE}..."
    run_cmd "apt update (adoptium)" apt-get update -qq
    run_cmd "Install Java" apt-get install -y -qq "$JAVA_PACKAGE"

    # Verify
    if ! $DRY_RUN; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1)
        ok "Java installed: ${java_ver}"
    else
        ok "Java would be installed"
    fi
}

# ---------------------------------------------------------------------------
# Phase 3: User & Directory Setup
# ---------------------------------------------------------------------------
phase_user_setup() {
    phase_header 3 "User & Directory Setup"

    # Create system user
    if id "$HYTALE_USER" &>/dev/null; then
        skip "User '${HYTALE_USER}' already exists"
    else
        info "Creating system user '${HYTALE_USER}'..."
        run_cmd "Create user" useradd -r -m -d "$HYTALE_HOME" -s /bin/bash "$HYTALE_USER"
        ok "User '${HYTALE_USER}' created (home: ${HYTALE_HOME})"
    fi

    # Add invoking user to hytale-server group
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
        if id -nG "$SUDO_USER" 2>/dev/null | grep -qw "$HYTALE_USER"; then
            skip "'${SUDO_USER}' already in '${HYTALE_USER}' group"
        else
            info "Adding '${SUDO_USER}' to '${HYTALE_USER}' group..."
            run_cmd "Add to group" usermod -aG "$HYTALE_USER" "$SUDO_USER"
            ok "'${SUDO_USER}' added to '${HYTALE_USER}' group"
            info "Log out and back in for group changes to take effect"
        fi
    fi

    # Ensure server directory exists
    if [[ -d "$SERVER_DIR" ]]; then
        skip "Server directory already exists: ${SERVER_DIR}"
    else
        info "Creating server directory..."
        run_cmd "Create server dir" mkdir -p "$SERVER_DIR"
        ok "Created ${SERVER_DIR}"
    fi

    # Set ownership and permissions
    if ! $DRY_RUN; then
        chown -R "${HYTALE_USER}:${HYTALE_USER}" "$HYTALE_HOME"
        chmod 775 "$HYTALE_HOME"
        chmod 775 "$SERVER_DIR"
    else
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would set ownership to ${HYTALE_USER}:${HYTALE_USER}"
    fi
    ok "Directory permissions set (775)"
}

# ---------------------------------------------------------------------------
# Phase 4: Download Hytale Server
# ---------------------------------------------------------------------------
phase_download_server() {
    phase_header 4 "Download Hytale Server"

    # Check if server files already exist
    if [[ -f "${SERVER_WORK_DIR}/HytaleServer.jar" ]]; then
        skip "HytaleServer.jar already present — skipping download"
        return 0
    fi

    # Check for downloader binary
    if [[ ! -f "$DOWNLOADER_PATH" ]]; then
        # Look for it in common locations
        local found_path=""
        for check_path in \
            "${HYTALE_HOME}/${DOWNLOADER_BIN}" \
            "/tmp/${DOWNLOADER_BIN}" \
            "${HOME}/${DOWNLOADER_BIN}"; do
            if [[ -f "$check_path" ]]; then
                found_path="$check_path"
                break
            fi
        done

        if [[ -n "$found_path" && "$found_path" != "$DOWNLOADER_PATH" ]]; then
            info "Found downloader at ${found_path}, copying..."
            run_cmd "Copy downloader" cp "$found_path" "$DOWNLOADER_PATH"
        elif $UNATTENDED; then
            error "Downloader not found at ${DOWNLOADER_PATH}"
            fatal "Cannot download server in unattended mode without the downloader binary."
        else
            echo ""
            warn "Hytale downloader not found at: ${DOWNLOADER_PATH}"
            echo ""
            echo "  Please do one of the following:"
            echo "    1. Place the downloader at: ${DOWNLOADER_PATH}"
            echo "    2. Enter the full path to the downloader binary"
            echo ""
            local user_path
            read -rp "  Path to downloader (or press Enter to abort): " user_path
            if [[ -z "$user_path" ]]; then
                fatal "Downloader not provided. Cannot continue."
            fi
            if [[ ! -f "$user_path" ]]; then
                fatal "File not found: ${user_path}"
            fi
            run_cmd "Copy downloader" cp "$user_path" "$DOWNLOADER_PATH"
        fi
    fi

    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would run downloader (requires OAuth2 browser auth)"
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  This downloads ~3.2 GB of server files"
        return 0
    fi

    # Set permissions
    chown "${HYTALE_USER}:${HYTALE_USER}" "$DOWNLOADER_PATH"
    chmod +x "$DOWNLOADER_PATH"

    echo ""
    info "Starting Hytale server download..."
    echo ""
    echo -e "  ${C_BOLD}${C_YELLOW}INTERACTIVE STEP:${C_RESET} The downloader will display a URL and code."
    echo "  Open the URL in your browser, log in with your Hytale account,"
    echo "  and enter the authorization code. The download will start automatically."
    echo ""
    echo "  Download size: ~3.2 GB"
    echo ""

    if ! prompt_yes_no "Ready to start the download?" "y"; then
        warn "Download skipped by user. You can re-run this script later."
        return 0
    fi

    # Run downloader as hytale-server user
    sudo -u "$HYTALE_USER" bash -c "cd '${HYTALE_HOME}' && './${DOWNLOADER_BIN}'"

    # Verify download
    if [[ -f "${SERVER_WORK_DIR}/HytaleServer.jar" ]]; then
        ok "Server downloaded successfully"
    else
        fatal "Download completed but HytaleServer.jar not found at ${SERVER_WORK_DIR}/"
    fi

    # Make start.sh executable
    if [[ -f "${SERVER_DIR}/start.sh" ]]; then
        chmod +x "${SERVER_DIR}/start.sh"
        ok "start.sh made executable"
    fi
}

# ---------------------------------------------------------------------------
# Phase 5: JVM Tuning
# ---------------------------------------------------------------------------
phase_jvm_tuning() {
    phase_header 5 "JVM Tuning"

    local jvm_file="${SERVER_DIR}/jvm.options"

    # Detect RAM
    local total_ram_gb
    total_ram_gb=$(detect_ram_gb)
    if (( total_ram_gb < 4 )); then
        warn "System has only ${total_ram_gb} GB RAM (minimum recommended: 4 GB)"
        warn "JVM will be configured with minimum values — expect limited capacity"
        # Floor to 4 for the calculation, but min bounds below will keep it safe
    fi
    if (( total_ram_gb < 1 )); then
        total_ram_gb=4
        warn "Could not detect RAM reliably, assuming ${total_ram_gb} GB"
    else
        info "Detected system RAM: ${total_ram_gb} GB"
    fi

    # Calculate heap sizes
    # Reserve 2GB for OS, Xms = 80% of remaining, Xmx = remaining
    local available_gb=$(( total_ram_gb - 2 ))
    (( available_gb < 2 )) && available_gb=2

    local xmx_gb=$available_gb
    local xms_gb=$(( available_gb * 80 / 100 ))

    # Enforce min/max bounds
    (( xms_gb < 2 )) && xms_gb=2
    (( xmx_gb < 3 )) && xmx_gb=3
    (( xms_gb > 22 )) && xms_gb=22
    (( xmx_gb > 26 )) && xmx_gb=26

    # Ensure xms <= xmx
    (( xms_gb > xmx_gb )) && xms_gb=$xmx_gb

    info "Calculated JVM heap: -Xms${xms_gb}G / -Xmx${xmx_gb}G"

    # Let user adjust in interactive mode (skip in dry-run and unattended)
    if ! $UNATTENDED && ! $DRY_RUN; then
        echo ""
        echo "  Memory allocation (${total_ram_gb} GB total, ${available_gb} GB available for JVM):"
        echo "    Minimum heap (-Xms): ${xms_gb}G"
        echo "    Maximum heap (-Xmx): ${xmx_gb}G"
        echo ""
        if prompt_yes_no "Use these values?" "y"; then
            : # keep calculated values
        else
            local new_xms new_xmx
            new_xms=$(prompt_value "Minimum heap in GB (-Xms)" "$xms_gb")
            new_xmx=$(prompt_value "Maximum heap in GB (-Xmx)" "$xmx_gb")
            # Validate: ensure they're integers
            if [[ "$new_xms" =~ ^[0-9]+$ ]] && [[ "$new_xmx" =~ ^[0-9]+$ ]]; then
                xms_gb=$new_xms
                xmx_gb=$new_xmx
            else
                warn "Invalid input, using calculated values"
            fi
        fi
    fi

    # Check if jvm.options already exists with same values
    if [[ -f "$jvm_file" ]] && ! $DRY_RUN; then
        if grep -q "^\-Xms${xms_gb}G" "$jvm_file" && grep -q "^\-Xmx${xmx_gb}G" "$jvm_file"; then
            skip "jvm.options already configured with -Xms${xms_gb}G / -Xmx${xmx_gb}G"
            return 0
        else
            info "Updating jvm.options with new heap values..."
        fi
    fi

    # Write jvm.options
    write_file "$jvm_file" <<EOF
# Hytale Server JVM Options
# Memory: Reserve ~2GB for OS/overhead, allocate rest to JVM
-Xms${xms_gb}G
-Xmx${xmx_gb}G

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
EOF

    # Set ownership
    if ! $DRY_RUN; then
        chown "${HYTALE_USER}:${HYTALE_USER}" "$jvm_file"
    fi

    ok "jvm.options written: -Xms${xms_gb}G / -Xmx${xmx_gb}G (G1GC)"
}

# ---------------------------------------------------------------------------
# Phase 6: Server Configuration
# ---------------------------------------------------------------------------
phase_server_config() {
    phase_header 6 "Server Configuration"

    local config_file="${SERVER_WORK_DIR}/config.json"
    local whitelist_file="${SERVER_WORK_DIR}/whitelist.json"

    # Ensure Server/ directory exists
    if ! $DRY_RUN && [[ ! -d "$SERVER_WORK_DIR" ]]; then
        mkdir -p "$SERVER_WORK_DIR"
        chown "${HYTALE_USER}:${HYTALE_USER}" "$SERVER_WORK_DIR"
    fi

    # Collect configuration values
    local total_ram_gb
    total_ram_gb=$(detect_ram_gb)
    (( total_ram_gb < 4 )) && total_ram_gb=4

    # Scale defaults to hardware: ~10 players per 4GB available
    local available_gb=$(( total_ram_gb - 2 ))
    (( available_gb < 2 )) && available_gb=2
    local default_players=$(( available_gb * 10 / 4 ))
    (( default_players < 5 )) && default_players=5
    (( default_players > 100 )) && default_players=100

    # Scale view radius: lower for less RAM
    local default_view_radius=16
    (( available_gb >= 12 )) && default_view_radius=24
    (( available_gb >= 20 )) && default_view_radius=32

    local server_name max_players max_view_radius password game_mode

    if $UNATTENDED || $DRY_RUN; then
        server_name="Hytale Server"
        max_players=$default_players
        max_view_radius=$default_view_radius
        password=""
        game_mode="Adventure"
        if $DRY_RUN; then
            info "Would use defaults: ${default_players} players, view radius ${default_view_radius}, Adventure mode"
        fi
    else
        echo ""
        echo "  Configure your Hytale server (press Enter for defaults):"
        echo ""
        server_name=$(prompt_value "Server name" "Hytale Server")
        max_players=$(prompt_value "Max players" "$default_players")
        max_view_radius=$(prompt_value "Max view radius (8-32)" "$default_view_radius")
        password=$(prompt_value "Server password (empty = none)" "")
        game_mode=$(prompt_value "Default game mode (Adventure/Creative)" "Adventure")
    fi

    # Validate numeric inputs
    [[ "$max_players" =~ ^[0-9]+$ ]] || max_players=$default_players
    [[ "$max_view_radius" =~ ^[0-9]+$ ]] || max_view_radius=$default_view_radius

    # Escape string values for safe JSON embedding
    local safe_server_name safe_password safe_game_mode
    safe_server_name=$(json_escape "$server_name")
    safe_password=$(json_escape "$password")
    safe_game_mode=$(json_escape "$game_mode")

    # Check if config already exists and matches
    if [[ -f "$config_file" ]] && ! $DRY_RUN; then
        info "config.json already exists, overwriting with new values..."
    fi

    # Write config.json (omit AuthCredentialStore — server auto-creates it)
    write_file "$config_file" <<EOF
{
  "Version": 4,
  "ServerName": "${safe_server_name}",
  "MOTD": "",
  "Password": "${safe_password}",
  "MaxPlayers": ${max_players},
  "MaxViewRadius": ${max_view_radius},
  "Defaults": {
    "World": "default",
    "GameMode": "${safe_game_mode}"
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
EOF
    ok "config.json written (${max_players} players, view radius ${max_view_radius})"

    # Write whitelist.json
    if [[ -f "$whitelist_file" ]] && ! $DRY_RUN; then
        skip "whitelist.json already exists"
    else
        write_file "$whitelist_file" <<'EOF'
{"enabled": true, "list": []}
EOF
        ok "whitelist.json written (whitelist enabled)"
    fi

    # Set ownership
    if ! $DRY_RUN; then
        chown "${HYTALE_USER}:${HYTALE_USER}" "$config_file"
        [[ -f "$whitelist_file" ]] && chown "${HYTALE_USER}:${HYTALE_USER}" "$whitelist_file"
    fi
}

# ---------------------------------------------------------------------------
# Phase 7: Firewall (UFW)
# ---------------------------------------------------------------------------
phase_firewall() {
    phase_header 7 "Firewall (UFW)"

    # Install UFW if missing
    if ! is_pkg_installed "ufw"; then
        info "Installing UFW..."
        run_cmd "Install ufw" apt-get install -y -qq ufw
        ok "UFW installed"
    else
        skip "UFW already installed"
    fi

    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would configure UFW:"
        echo -e "         - Default: deny incoming, allow outgoing"
        echo -e "         - Allow SSH (${SSH_PORT}/tcp)"
        echo -e "         - Allow Hytale (${HYTALE_PORT}/udp)"
        echo -e "         - Enable firewall"
        return 0
    fi

    # Set defaults
    run_cmd "UFW default deny incoming" ufw default deny incoming
    run_cmd "UFW default allow outgoing" ufw default allow outgoing

    # Allow SSH FIRST (prevents lockout)
    if ufw status | grep -q "${SSH_PORT}/tcp"; then
        skip "SSH port already allowed"
    else
        run_cmd "Allow SSH" ufw allow "${SSH_PORT}/tcp" comment 'SSH'
        ok "SSH port ${SSH_PORT}/tcp allowed"
    fi

    # Allow Hytale
    if ufw status | grep -q "${HYTALE_PORT}/udp"; then
        skip "Hytale port already allowed"
    else
        run_cmd "Allow Hytale" ufw allow "${HYTALE_PORT}/udp" comment 'Hytale Server'
        ok "Hytale port ${HYTALE_PORT}/udp allowed"
    fi

    # Enable UFW
    if ufw status | grep -q "Status: active"; then
        skip "UFW already active"
    else
        info "Enabling UFW..."
        run_cmd "Enable UFW" ufw --force enable
        ok "UFW enabled"
    fi
}

# ---------------------------------------------------------------------------
# Phase 8: Systemd Service
# ---------------------------------------------------------------------------
phase_systemd() {
    phase_header 8 "Systemd Service"

    local service_content
    read -r -d '' service_content <<'SERVICEEOF' || true
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
SERVICEEOF

    # Check if service file already exists and matches
    if [[ -f "$SYSTEMD_SERVICE" ]] && ! $DRY_RUN; then
        local existing
        existing=$(cat "$SYSTEMD_SERVICE")
        if [[ "$existing" == "$service_content" ]]; then
            skip "Systemd service already configured"
            # Ensure it's enabled
            if ! systemctl is-enabled hytale-server &>/dev/null; then
                run_cmd "Enable service" systemctl enable hytale-server
                ok "Service enabled for auto-start"
            else
                skip "Service already enabled"
            fi
            return 0
        else
            info "Updating systemd service file..."
        fi
    fi

    # Write service file
    write_file "$SYSTEMD_SERVICE" <<'EOF'
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
EOF

    ok "Service file written: ${SYSTEMD_SERVICE}"

    # Reload and enable (but do NOT start — Phase 9 handles first run)
    run_cmd "Daemon reload" systemctl daemon-reload
    run_cmd "Enable service" systemctl enable hytale-server
    ok "Service enabled (will auto-start on boot)"
    info "Service NOT started yet — first run happens in Phase 9"
}

# ---------------------------------------------------------------------------
# Phase 9: First Run & Auth
# ---------------------------------------------------------------------------
phase_first_run() {
    phase_header 9 "First Run & Auth"

    local auth_file="${SERVER_WORK_DIR}/auth.enc"

    # Check if already authenticated
    if [[ -f "$auth_file" ]]; then
        skip "auth.enc already exists — server is authenticated"
        if $DRY_RUN; then
            echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would start server via systemd"
        elif systemctl is-active hytale-server &>/dev/null; then
            skip "Server already running"
        else
            info "Starting server via systemd..."
            run_cmd "Start server" systemctl start hytale-server
            ok "Server started via systemd"
        fi
        return 0
    fi

    # Can't do this unattended
    if $UNATTENDED; then
        echo ""
        warn "Server authentication requires interactive browser-based OAuth2."
        warn "Skipping first run in unattended mode."
        echo ""
        echo "  To authenticate manually, run:"
        echo ""
        echo "    sudo -u ${HYTALE_USER} bash -c '"
        echo "        cd ${SERVER_WORK_DIR}"
        echo "        java @../jvm.options -jar HytaleServer.jar --assets ../Assets.zip"
        echo "    '"
        echo ""
        echo "  Then type: /auth login"
        echo "  Follow the browser prompts, then type: /stop"
        echo "  Finally: sudo systemctl start hytale-server"
        echo ""
        return 0
    fi

    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would run server interactively for /auth login"
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  This requires browser-based OAuth2 authentication"
        return 0
    fi

    # Interactive first run
    echo ""
    echo -e "  ${C_BOLD}${C_YELLOW}INTERACTIVE STEP: Server Authentication${C_RESET}"
    echo ""
    echo "  The server will start interactively. Once you see:"
    echo "    [ServerAuthManager] No server tokens configured. Use /auth login..."
    echo ""
    echo "  Type:  /auth login"
    echo ""
    echo "  A URL and code will appear. Open the URL in your browser,"
    echo "  log in with your Hytale account, and enter the code."
    echo ""
    echo "  Once authenticated, type:  /stop"
    echo ""

    if ! prompt_yes_no "Ready to start the server for authentication?" "y"; then
        warn "First run skipped. You'll need to authenticate manually before the server can accept players."
        return 0
    fi

    echo ""
    info "Starting server... (this may take a moment)"
    echo ""

    # Run the server interactively as hytale-server user
    sudo -u "$HYTALE_USER" bash -c "cd '${SERVER_WORK_DIR}' && java @../jvm.options -jar HytaleServer.jar --assets ../Assets.zip"

    echo ""

    # Verify auth was created
    if [[ -f "$auth_file" ]]; then
        ok "Authentication successful — auth.enc created"
        echo ""
        info "Starting server via systemd..."
        run_cmd "Start server" systemctl start hytale-server
        ok "Server started"
    else
        warn "auth.enc not found — authentication may not have completed"
        warn "You can re-run this script or authenticate manually (see tutorial)"
    fi
}

# ---------------------------------------------------------------------------
# Phase 10: Summary
# ---------------------------------------------------------------------------
phase_summary() {
    phase_header 10 "Summary"

    local local_ip public_ip
    local_ip=$(get_local_ip)
    public_ip=$(get_public_ip)

    echo ""
    echo -e "${C_BOLD}${C_GREEN}"
    cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║            Hytale Server Setup Complete!                   ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
    echo -e "${C_RESET}"

    echo -e "  ${C_BOLD}Connection Info${C_RESET}"
    echo "  ──────────────────────────────────────"
    echo "  Local IP:    ${local_ip}"
    echo "  Public IP:   ${public_ip}"
    echo "  Port:        ${HYTALE_PORT}/UDP"
    echo ""
    echo "  LAN connect: ${local_ip}:${HYTALE_PORT}"
    echo "  WAN connect: ${public_ip}:${HYTALE_PORT}"
    echo ""

    if [[ "$public_ip" != "unknown" ]] && [[ "$local_ip" != "unknown" ]]; then
        echo "  If hosting from home, set up port forwarding:"
        echo "    Protocol: UDP | External: ${HYTALE_PORT} | Internal: ${local_ip}:${HYTALE_PORT}"
        echo ""
    fi

    echo -e "  ${C_BOLD}Management Commands${C_RESET}"
    echo "  ──────────────────────────────────────"
    echo "  Start:       sudo systemctl start hytale-server"
    echo "  Stop:        sudo systemctl stop hytale-server"
    echo "  Restart:     sudo systemctl restart hytale-server"
    echo "  Status:      sudo systemctl status hytale-server"
    echo "  Live logs:   sudo journalctl -u hytale-server -f"
    echo "  Last 100:    sudo journalctl -u hytale-server -n 100"
    echo ""

    echo -e "  ${C_BOLD}Important File Paths${C_RESET}"
    echo "  ──────────────────────────────────────"
    echo "  Config:      ${SERVER_WORK_DIR}/config.json"
    echo "  Whitelist:   ${SERVER_WORK_DIR}/whitelist.json"
    echo "  JVM options: ${SERVER_DIR}/jvm.options"
    echo "  Start script:${SERVER_DIR}/start.sh"
    echo "  Service:     ${SYSTEMD_SERVICE}"
    echo "  Logs:        ${SERVER_WORK_DIR}/logs/"
    echo "  World data:  ${SERVER_WORK_DIR}/universe/"
    echo "  Backups:     ${SERVER_WORK_DIR}/backups/  (built-in)"
    echo "               ${HYTALE_HOME}/backups/              (toolkit)"
    echo "  Auth creds:  ${SERVER_WORK_DIR}/auth.enc"
    echo "  Setup log:   ${LOG_FILE}"
    echo ""

    echo -e "  ${C_BOLD}Update & Backup${C_RESET}"
    echo "  ──────────────────────────────────────"
    echo "  Update:      sudo bash ${SCRIPT_DIR}/hytale-update.sh"
    echo "  Backup:      sudo bash ${SCRIPT_DIR}/hytale-backup.sh"
    echo "  Verify:      sudo bash ${SCRIPT_DIR}/hytale-setup.sh --verify"
    echo ""

    # Save plain-text install summary to file
    write_file "${HYTALE_HOME}/INSTALL_SUMMARY.txt" <<SUMEOF
Hytale Server — Install Summary
Generated: $(date)
================================================

Connection Info
  Local IP:    ${local_ip}
  Public IP:   ${public_ip}
  Port:        ${HYTALE_PORT}/UDP
  LAN connect: ${local_ip}:${HYTALE_PORT}
  WAN connect: ${public_ip}:${HYTALE_PORT}

Management Commands
  Start:       sudo systemctl start hytale-server
  Stop:        sudo systemctl stop hytale-server
  Restart:     sudo systemctl restart hytale-server
  Status:      sudo systemctl status hytale-server
  Live logs:   sudo journalctl -u hytale-server -f
  Last 100:    sudo journalctl -u hytale-server -n 100

Important File Paths
  Config:      ${SERVER_WORK_DIR}/config.json
  Whitelist:   ${SERVER_WORK_DIR}/whitelist.json
  JVM options: ${SERVER_DIR}/jvm.options
  Start script:${SERVER_DIR}/start.sh
  Service:     ${SYSTEMD_SERVICE}
  Logs:        ${SERVER_WORK_DIR}/logs/
  World data:  ${SERVER_WORK_DIR}/universe/
  Backups:     ${SERVER_WORK_DIR}/backups/  (built-in)
               ${HYTALE_HOME}/backups/              (toolkit)
  Auth creds:  ${SERVER_WORK_DIR}/auth.enc
  Setup log:   ${LOG_FILE}

Update Server
  sudo bash ${SCRIPT_DIR}/hytale-update.sh

Backup Server
  sudo bash ${SCRIPT_DIR}/hytale-backup.sh
SUMEOF

    if ! $DRY_RUN; then
        chown "${HYTALE_USER}:${HYTALE_USER}" "${HYTALE_HOME}/INSTALL_SUMMARY.txt" 2>/dev/null || true
        ok "Install summary saved to ${HYTALE_HOME}/INSTALL_SUMMARY.txt"
    fi

    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}${C_BOLD}DRY RUN COMPLETE — no changes were made.${C_RESET}"
        echo ""
    fi

    ok "Setup complete! Happy building!"
    echo ""
}

# ---------------------------------------------------------------------------
# Verify (--verify flag)
# ---------------------------------------------------------------------------
run_verify() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}Hytale Server — Health Check${C_RESET}"
    echo -e "${C_CYAN}$(printf '%.0s─' {1..60})${C_RESET}"
    echo ""

    local errors=0

    # Check 1: Java version 25
    if cmd_exists java; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 || true)
        if echo "$java_ver" | grep -q "25\."; then
            echo -e "  ${C_GREEN}[OK]${C_RESET}    Java 25 installed"
        else
            echo -e "  ${C_RED}[ERROR]${C_RESET} Java 25 not found (got: ${java_ver})"
            (( errors++ ))
        fi
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} Java not installed"
        (( errors++ ))
    fi

    # Check 2: hytale-server user exists
    if id "$HYTALE_USER" &>/dev/null; then
        echo -e "  ${C_GREEN}[OK]${C_RESET}    User '${HYTALE_USER}' exists"
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} User '${HYTALE_USER}' does not exist"
        (( errors++ ))
    fi

    # Check 3: Systemd service enabled
    if systemctl is-enabled hytale-server &>/dev/null; then
        echo -e "  ${C_GREEN}[OK]${C_RESET}    Systemd service enabled"
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} Systemd service not enabled"
        (( errors++ ))
    fi

    # Check 4: Systemd service active
    local service_active=false
    if systemctl is-active hytale-server &>/dev/null; then
        echo -e "  ${C_GREEN}[OK]${C_RESET}    Systemd service active"
        service_active=true
    else
        echo -e "  ${C_YELLOW}[WARN]${C_RESET}  Systemd service not active (may be intentionally stopped)"
    fi

    # Check 5: UFW 5520/udp allowed
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "${HYTALE_PORT}/udp"; then
        echo -e "  ${C_GREEN}[OK]${C_RESET}    UFW allows ${HYTALE_PORT}/udp"
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} UFW rule for ${HYTALE_PORT}/udp not found"
        (( errors++ ))
    fi

    # Check 6: config.json valid JSON
    local config_file="${SERVER_WORK_DIR}/config.json"
    if [[ -f "$config_file" ]]; then
        if cmd_exists python3; then
            if python3 -c "import json; json.load(open('${config_file}'))" 2>/dev/null; then
                echo -e "  ${C_GREEN}[OK]${C_RESET}    config.json is valid JSON"
            else
                echo -e "  ${C_RED}[ERROR]${C_RESET} config.json is not valid JSON"
                (( errors++ ))
            fi
        else
            echo -e "  ${C_YELLOW}[WARN]${C_RESET}  Cannot validate config.json (python3 not available)"
        fi
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} config.json not found at ${config_file}"
        (( errors++ ))
    fi

    # Check 7: auth.enc exists
    local auth_file="${SERVER_WORK_DIR}/auth.enc"
    if [[ -f "$auth_file" ]]; then
        echo -e "  ${C_GREEN}[OK]${C_RESET}    auth.enc exists"
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} auth.enc not found at ${auth_file}"
        (( errors++ ))
    fi

    # Check 8: File ownership correct
    if [[ -d "$SERVER_DIR" ]]; then
        local dir_owner
        dir_owner=$(stat -c '%U' "$SERVER_DIR" 2>/dev/null || echo "unknown")
        if [[ "$dir_owner" == "$HYTALE_USER" ]]; then
            echo -e "  ${C_GREEN}[OK]${C_RESET}    File ownership correct (${HYTALE_USER})"
        else
            echo -e "  ${C_RED}[ERROR]${C_RESET} ${SERVER_DIR} owned by '${dir_owner}', expected '${HYTALE_USER}'"
            (( errors++ ))
        fi
    else
        echo -e "  ${C_RED}[ERROR]${C_RESET} Server directory ${SERVER_DIR} does not exist"
        (( errors++ ))
    fi

    # Check 9: Port 5520 listening (only if service active)
    if $service_active; then
        if ss -ulnp 2>/dev/null | grep -q ":${HYTALE_PORT} "; then
            echo -e "  ${C_GREEN}[OK]${C_RESET}    Port ${HYTALE_PORT}/udp is listening"
        else
            echo -e "  ${C_YELLOW}[WARN]${C_RESET}  Port ${HYTALE_PORT}/udp not listening (server may still be starting)"
        fi
    fi

    echo ""
    if (( errors == 0 )); then
        echo -e "  ${C_GREEN}${C_BOLD}All checks passed.${C_RESET}"
    else
        echo -e "  ${C_RED}${C_BOLD}${errors} check(s) failed.${C_RESET}"
    fi
    echo ""

    (( errors == 0 )) && exit 0 || exit 1
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
show_banner() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}"
    cat <<'ASCIIEOF'
   ╦ ╦╦ ╦╔╦╗╔═╗╦  ╔═╗
   ╠═╣╚╦╝ ║ ╠═╣║  ║╣
   ╩ ╩ ╩  ╩ ╩ ╩╩═╝╚═╝
   Server Automated Installer
ASCIIEOF
    echo -e "${C_RESET}"
    echo "  Version ${SCRIPT_VERSION}"
    if $DRY_RUN; then
        echo -e "  Mode: ${C_YELLOW}DRY RUN${C_RESET} (no changes will be made)"
    elif $UNATTENDED; then
        echo -e "  Mode: ${C_CYAN}UNATTENDED${C_RESET} (using defaults)"
    else
        echo -e "  Mode: ${C_GREEN}INTERACTIVE${C_RESET}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Main Entrypoint
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    # --verify: run health checks and exit
    if $VERIFY; then
        run_verify
    fi

    # Initialize log file (skip in dry-run if we can't write)
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        echo "=== Hytale Server Setup — $(date) ===" >> "$LOG_FILE" 2>/dev/null || true
        log "Version: ${SCRIPT_VERSION}"
        log "Args: $*"
        log "Mode: dry_run=${DRY_RUN} unattended=${UNATTENDED}"
    fi

    show_banner

    phase_system_prep
    phase_install_java
    phase_user_setup
    phase_download_server
    phase_jvm_tuning
    phase_server_config
    phase_firewall
    phase_systemd
    phase_first_run
    phase_summary
}

main "$@"
