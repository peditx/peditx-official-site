#!/bin/sh
#
# Usage:
#   wget -O - https://your-url-to-this-script.com/install_argon.sh | sh
#

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
REPO="jerrykuku/luci-theme-argon"
TMP_DIR="/tmp/argon_installer"

# --- Colors for output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() {
    printf "${BLUE}[i] %s${NC}\n" "$1"
}

log_success() {
    printf "${GREEN}[✓] %s${NC}\n" "$1"
}

log_error() {
    printf "${RED}[✗] %s${NC}\n" "$1" >&2
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
}

# Register the cleanup function to be called on script exit, error, or interrupt
trap cleanup EXIT HUP INT QUIT TERM

# --- Main Script ---

# Create a temporary directory for downloads
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# --- Connectivity Checks ---
log_info "Testing DNS resolution by pinging github.com..."
if ! ping -c 1 github.com >/dev/null 2>&1; then
    log_error "DNS test failed. Cannot resolve github.com."
    log_error "Please check your router's DNS settings (e.g., in Network -> Interfaces -> WAN)."
    exit 1
fi
log_success "DNS resolution is working."

# --- Version Detection ---
log_info "Detecting OpenWrt version..."
VERSION_ID=$(grep -oE '^[0-9]+\.[0-9]+' /etc/openwrt_release 2>/dev/null | head -n 1)
[ -z "$VERSION_ID" ] && VERSION_ID=$(grep -oE 'VERSION_ID="([0-9]+\.[0-9]+)"' /etc/os-release 2>/dev/null | sed -E 's/.*"([0-9]+\.[0-9]+)".*/\1/')
[ -z "$VERSION_ID" ] && VERSION_ID="23.05" && log_info "Could not detect version, falling back to ${VERSION_ID}."

VERSION_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
if [ "$VERSION_MAJOR" -lt 21 ]; then
    FALLBACK_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v1.8.4/luci-theme-argon_1.8.4-20230302_all.ipk"
else
    FALLBACK_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.3.2/luci-theme-argon_2.3.2-r20250207_all.ipk"
fi

log_info "Detected OpenWrt version: ${VERSION_ID}"

# --- Installation ---
log_info "Removing old Argon theme if it exists..."
opkg remove luci-theme-argon >/dev/null 2>&1 || true

# **FIXED**: Instead of checking '/latest', fetch all releases and find the newest valid .ipk file.
# This makes the script resilient to faulty or .apk-only releases.
log_info "Searching all releases for the latest valid .ipk package..."
DL_URL=$(wget -qO- --no-check-certificate "https://api.github.com/repos/$REPO/releases" | \
    grep -o '"browser_download_url": *"[^"]*\.ipk"' | \
    head -n 1 | \
    sed 's/.*"browser_download_url": *"//;s/"$//')

# If the smart search fails for any reason (e.g., repo has no .ipk files), use the hardcoded fallback URL.
if [ -z "$DL_URL" ]; then
    log_info "Could not automatically find a valid .ipk package. Reverting to a known stable version."
    DL_URL="$FALLBACK_URL"
fi

FILE_NAME=$(basename "$DL_URL")
log_info "Downloading: ${FILE_NAME}"

# Add --no-check-certificate to the main download command
if ! wget -q --no-check-certificate "$DL_URL" -O "$FILE_NAME"; then
    log_error "Download failed. Please check your router's internet connection."
    log_error "To see a detailed error, run this command manually on your router:"
    log_error "wget --no-check-certificate '$DL_URL'"
    exit 1
fi

if [ ! -s "$FILE_NAME" ]; then
    log_error "Download succeeded but the file is empty. This might be a temporary issue with GitHub."
    exit 1
fi

log_info "Installing ${FILE_NAME}..."
opkg install "$FILE_NAME"

log_success "luci-theme-argon installed successfully!"
log_info "You can now select the Argon theme in the LuCI web interface:"
log_info "System → System → Language and Style"

