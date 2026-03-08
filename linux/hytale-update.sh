#!/usr/bin/env bash
# =============================================================================
# Hytale Dedicated Server — Update Script
# =============================================================================
# Stops the server, optionally backs up, runs the downloader, and restarts.
#
# Usage:
#   sudo bash hytale-update.sh [OPTIONS]
#
# Options:
#   --dry-run       Print what would happen without making changes
#   --no-backup     Skip pre-update backup
#   --help          Show help message
#   --version       Show version
#
# Note: The downloader may prompt for OAuth2 re-authentication if the
#       session has expired. Have a browser ready.
#
# See: /opt/hytale/INSTALL_SUMMARY.txt for server details.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & Globals
# ---------------------------------------------------------------------------
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly HYTALE_USER="hytale-server"
readonly HYTALE_HOME="/opt/hytale"
readonly SERVER_DIR="${HYTALE_HOME}/server"
readonly DOWNLOADER_BIN="hytale-downloader-linux-amd64"
readonly DOWNLOADER_PATH="${HYTALE_HOME}/${DOWNLOADER_BIN}"
readonly BACKUP_SCRIPT="${SCRIPT_DIR}/hytale-backup.sh"

# Mutable globals
DRY_RUN=false
DO_BACKUP=true
WAS_RUNNING=false

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

info() {
    echo -e "  ${C_BLUE}[INFO]${C_RESET} $*"
}

ok() {
    echo -e "  ${C_GREEN}[OK]${C_RESET}   $*"
}

warn() {
    echo -e "  ${C_YELLOW}[WARN]${C_RESET} $*"
}

error() {
    echo -e "  ${C_RED}[ERROR]${C_RESET} $*" >&2
}

fatal() {
    error "$@"
    exit 1
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
show_help() {
    cat <<'HELPEOF'
Hytale Dedicated Server — Update Script

Usage:
  sudo bash hytale-update.sh [OPTIONS]

Options:
  --dry-run       Print what would happen without making changes
  --no-backup     Skip pre-update backup
  --help          Show this help message
  --version       Show version

Steps performed:
  1. Stop server (if running)
  2. Create backup (unless --no-backup)
  3. Run the Hytale downloader to fetch updates
  4. Start server

Note: The downloader may prompt for OAuth2 re-authentication if the
      session has expired. Have a browser ready when running this script.

Examples:
  sudo bash hytale-update.sh               # Full update with backup
  sudo bash hytale-update.sh --dry-run     # Preview without changes
  sudo bash hytale-update.sh --no-backup   # Update without backup
HELPEOF
    exit 0
}

show_version() {
    echo "hytale-update.sh version ${SCRIPT_VERSION}"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)    DRY_RUN=true ;;
            --no-backup)  DO_BACKUP=false ;;
            --help|-h)    show_help ;;
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
# Update Functions
# ---------------------------------------------------------------------------
check_downloader() {
    if [[ ! -f "$DOWNLOADER_PATH" ]]; then
        fatal "Downloader not found at ${DOWNLOADER_PATH}"
    fi
    if [[ ! -x "$DOWNLOADER_PATH" ]]; then
        if $DRY_RUN; then
            echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would make downloader executable"
        else
            chmod +x "$DOWNLOADER_PATH"
        fi
    fi
    ok "Downloader found: ${DOWNLOADER_PATH}"
}

stop_server() {
    if systemctl is-active hytale-server &>/dev/null; then
        WAS_RUNNING=true
        if $DRY_RUN; then
            echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would stop hytale-server"
        else
            info "Stopping hytale-server..."
            systemctl stop hytale-server
            ok "Server stopped"
        fi
    else
        info "Server is not running"
    fi
}

run_backup() {
    if ! $DO_BACKUP; then
        info "Backup skipped (--no-backup)"
        return 0
    fi

    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        warn "Backup script not found at ${BACKUP_SCRIPT} — skipping backup"
        return 0
    fi

    info "Running pre-update backup..."
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would run: bash ${BACKUP_SCRIPT}"
    else
        bash "$BACKUP_SCRIPT"
    fi
    ok "Pre-update backup complete"
}

run_downloader() {
    info "Running Hytale downloader..."
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would run: sudo -u ${HYTALE_USER} bash -c 'cd ${HYTALE_HOME} && ./${DOWNLOADER_BIN}'"
        return 0
    fi

    sudo -u "$HYTALE_USER" bash -c "cd '${HYTALE_HOME}' && './${DOWNLOADER_BIN}'"
    ok "Downloader finished"
}

start_server() {
    info "Starting hytale-server..."
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would start hytale-server"
        return 0
    fi

    systemctl start hytale-server

    # Brief wait then verify
    sleep 2
    if systemctl is-active hytale-server &>/dev/null; then
        ok "Server started successfully"
    else
        warn "Server may not have started — check: sudo systemctl status hytale-server"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    echo ""
    echo -e "${C_BOLD}${C_CYAN}Hytale Server — Update${C_RESET}"
    if $DRY_RUN; then
        echo -e "  Mode: ${C_YELLOW}DRY RUN${C_RESET}"
    fi
    echo ""

    # Verify root
    if [[ $EUID -ne 0 ]]; then
        if $DRY_RUN; then
            warn "Not running as root — dry-run will still show actions"
        else
            fatal "This script must be run as root (use sudo)."
        fi
    fi

    check_downloader
    stop_server
    run_backup
    run_downloader
    start_server

    echo ""
    ok "Update complete!"
    echo ""
}

main "$@"
