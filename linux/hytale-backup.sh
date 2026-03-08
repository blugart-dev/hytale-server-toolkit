#!/usr/bin/env bash
# =============================================================================
# Hytale Dedicated Server — Backup Script
# =============================================================================
# Creates timestamped tar.gz backups of server data with automatic rotation.
#
# Usage:
#   sudo bash hytale-backup.sh [OPTIONS]
#
# Options:
#   --dry-run       Print what would happen without making changes
#   --keep N        Number of backups to retain (default: 7)
#   --backup-dir D  Directory for backups (default: /opt/hytale/backups/)
#   --help          Show help message
#   --version       Show version
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
readonly SERVER_WORK_DIR="${SERVER_DIR}/Server"

# Mutable globals
DRY_RUN=false
KEEP_COUNT=7
BACKUP_DIR="${HYTALE_HOME}/backups"

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
Hytale Dedicated Server — Backup Script

Usage:
  sudo bash hytale-backup.sh [OPTIONS]

Options:
  --dry-run       Print what would happen without making changes
  --keep N        Number of backups to retain (default: 7)
  --backup-dir D  Directory for backups (default: /opt/hytale/backups/)
  --help          Show this help message
  --version       Show version

What gets backed up:
  - Server/universe/           (world data)
  - Server/config.json         (server configuration)
  - Server/whitelist.json      (whitelist)
  - Server/permissions.json    (permissions)
  - Server/bans.json           (ban list)
  - Server/auth.enc            (authentication credentials)
  - jvm.options                (JVM configuration)

Backups are safe to run while the server is running (hot backup).

Examples:
  sudo bash hytale-backup.sh               # Create backup with defaults
  sudo bash hytale-backup.sh --dry-run     # Preview without changes
  sudo bash hytale-backup.sh --keep 3      # Keep only 3 most recent backups
HELPEOF
    exit 0
}

show_version() {
    echo "hytale-backup.sh version ${SCRIPT_VERSION}"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)    DRY_RUN=true ;;
            --keep)
                shift
                if [[ $# -eq 0 ]] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
                    fatal "--keep requires a numeric argument"
                fi
                KEEP_COUNT="$1"
                ;;
            --backup-dir)
                shift
                if [[ $# -eq 0 ]]; then
                    fatal "--backup-dir requires a directory path"
                fi
                BACKUP_DIR="$1"
                ;;
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
# Backup Functions
# ---------------------------------------------------------------------------
create_backup() {
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="${BACKUP_DIR}/hytale-backup-${timestamp}.tar.gz"

    # Ensure backup directory exists
    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would create directory: ${BACKUP_DIR}"
    else
        mkdir -p "$BACKUP_DIR"
    fi

    # Build list of files/dirs to include (skip missing optional files gracefully)
    local tar_args=()

    # Files from Server/ working directory
    local server_files=("universe" "config.json" "whitelist.json" "permissions.json" "bans.json" "auth.enc")
    local included_server=()
    for f in "${server_files[@]}"; do
        if [[ -e "${SERVER_WORK_DIR}/${f}" ]]; then
            included_server+=("${f}")
        else
            warn "Skipping missing file: Server/${f}"
        fi
    done

    # jvm.options is one level up (in server/ not server/Server/)
    local include_jvm=false
    if [[ -f "${SERVER_DIR}/jvm.options" ]]; then
        include_jvm=true
    else
        warn "Skipping missing file: jvm.options"
    fi

    if [[ ${#included_server[@]} -eq 0 ]] && ! $include_jvm; then
        fatal "No files found to back up. Is the server installed at ${SERVER_DIR}?"
    fi

    # Build tar command
    tar_args=(-czf "$backup_file")

    # Add Server/ files
    if [[ ${#included_server[@]} -gt 0 ]]; then
        tar_args+=(-C "$SERVER_WORK_DIR" "${included_server[@]}")
    fi

    # Add jvm.options from parent directory
    if $include_jvm; then
        tar_args+=(-C "$SERVER_DIR" "jvm.options")
    fi

    if $DRY_RUN; then
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would create: ${backup_file}"
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  tar ${tar_args[*]}"
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Files from Server/: ${included_server[*]}"
        $include_jvm && echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Also: jvm.options"
        return 0
    fi

    info "Creating backup..."
    tar "${tar_args[@]}"

    # Set ownership
    chown "${HYTALE_USER}:${HYTALE_USER}" "$backup_file"

    local backup_size
    backup_size=$(du -h "$backup_file" | cut -f1)
    ok "Backup created: ${backup_file} (${backup_size})"
}

rotate_backups() {
    if $DRY_RUN; then
        local count
        count=$(find "$BACKUP_DIR" -maxdepth 1 -name "hytale-backup-*.tar.gz" 2>/dev/null | wc -l)
        echo -e "  ${C_YELLOW}[DRY]${C_RESET}  Would rotate backups (keep ${KEEP_COUNT}, currently ${count})"
        return 0
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi

    # List backups sorted by time (newest first), delete beyond keep count
    local backups
    mapfile -t backups < <(ls -t "${BACKUP_DIR}"/hytale-backup-*.tar.gz 2>/dev/null)

    local total=${#backups[@]}
    if (( total <= KEEP_COUNT )); then
        info "Backup rotation: ${total} backups, keeping all (limit: ${KEEP_COUNT})"
        return 0
    fi

    local to_delete=$(( total - KEEP_COUNT ))
    info "Rotating backups: removing ${to_delete} old backup(s) (keeping ${KEEP_COUNT})"

    local i
    for (( i = KEEP_COUNT; i < total; i++ )); do
        rm -f "${backups[$i]}"
        info "Removed: $(basename "${backups[$i]}")"
    done

    ok "Backup rotation complete"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    echo ""
    echo -e "${C_BOLD}${C_CYAN}Hytale Server — Backup${C_RESET}"
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

    create_backup
    rotate_backups

    echo ""
    ok "Backup complete!"
    echo ""
}

main "$@"
