#!/bin/sh

# Aurora Theme - Uninstaller Script
# This script will remove the luci-theme-aurora package and revert to the default theme.
set -e

# --- Colors for output ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() {
    printf "${BLUE}[i] %s${NC}\n" "$1"
}

log_success() {
    printf "${GREEN}[✓] %s${NC}\n" "$1"
}

# --- Main Uninstall Logic ---
log_info "Starting the Aurora Theme uninstaller..."

# 1. Remove the aurora theme package
log_info "Removing 'luci-theme-aurora' package..."
opkg remove luci-theme-aurora >/dev/null 2>&1 || true
log_success "Package removed successfully."

# 2. Revert to the system's default theme
log_info "Reverting to the system's default theme..."
uci unset luci.main.mediaurlbase
uci commit luci
log_success "System default theme restored."

# 3. Clean up temporary installation files
log_info "Cleaning up any leftover temporary files..."
rm -rf "/tmp/aurora"

# 4. Clear LuCI cache to apply changes
log_info "Clearing LuCI cache..."
rm -f /tmp/luci-indexcache

echo ""
log_success "Aurora theme has been completely uninstalled."
log_info "Please hard-refresh your browser (Ctrl+Shift+R) or log out and log back in."

exit 0
