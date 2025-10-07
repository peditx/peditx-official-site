#!/bin/sh

# Argon Theme - Uninstaller Script
# This script will remove the luci-theme-argon package and revert to the default theme.
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
log_info "Starting the Argon Theme uninstaller..."

# 1. Remove the argon theme package
log_info "Removing 'luci-theme-argon' package..."
opkg remove luci-theme-argon >/dev/null 2>&1 || true
log_success "Package removed successfully."

# 2. Revert to the system's default theme
log_info "Reverting to the system's default theme..."
uci unset luci.main.mediaurlbase
uci commit luci
log_success "System default theme restored."

# 3. Clean up temporary installation files (just in case)
log_info "Cleaning up any leftover temporary files..."
rm -rf "/tmp/argon_installer"

# 4. Clear LuCI cache to apply changes
log_info "Clearing LuCI cache..."
rm -f /tmp/luci-indexcache

echo ""
log_success "Argon theme has been completely uninstalled."
log_info "Please hard-refresh your browser (Ctrl+Shift+R) or log out and log back in."

exit 0

