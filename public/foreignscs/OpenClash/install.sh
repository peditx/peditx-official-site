#!/bin/sh

# Colors and Symbols
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"

# Helper function for silent execution with checkmark
run_step() {
    local message="$1"
    local command="$2"
    
    echo -n -e "$message... "
    
    # Run command and hide output, redirect errors to temp file if needed for debugging
    if eval "$command" > /dev/null 2>&1; then
        echo -e "$CHECK"
    else
        echo -e "$CROSS"
        echo -e "${RED}Error occurred during: $message${NC}"
        exit 1
    fi
}

echo -e "\n--- OpenClash Auto Installer By PeDitX ---\n"

# 1. Detect Package Manager and Set Variables
PKG_MANAGER=""
FILE_EXT=""

if command -v opkg > /dev/null 2>&1; then
    PKG_MANAGER="opkg"
    FILE_EXT="ipk"
elif command -v apk > /dev/null 2>&1; then
    PKG_MANAGER="apk"
    FILE_EXT="apk"
else
    echo -e "${RED}Error: Neither opkg nor apk found!${NC}"
    exit 1
fi

echo -e "System detected: ${GREEN}${PKG_MANAGER}${NC} (Target: .${FILE_EXT})"

# 2. Update and Install Dependencies
if [ "$PKG_MANAGER" = "opkg" ]; then
    run_step "Updating opkg repositories" "opkg update"
    run_step "Installing dependencies (opkg)" "opkg install bash dnsmasq-full curl ca-bundle ip-full ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy luci-compat luci luci-base"
else
    run_step "Updating apk repositories" "apk update"
    run_step "Installing dependencies (apk)" "apk add bash dnsmasq-full curl ca-bundle ip-full ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy luci-compat luci luci-base"
fi

# 3. Find Latest Version URL from GitHub API
echo -n -e "Fetching latest release URL... "
# Get the JSON data
# Changed from 'releases/latest' to 'releases' to catch pre-releases/betas as well
API_URL="https://api.github.com/repos/vernesong/OpenClash/releases?per_page=1"
# Added User-Agent to avoid GitHub API blocking requests
API_RESPONSE=$(curl -s -H "User-Agent: OpenWrt" "$API_URL")

# Extract the download URL based on extension (apk or ipk)
# We use grep/sed/awk to avoid dependency on 'jq'
# IMPROVED REGEX: matches https://... up to the extension, stopping at quotes to avoid merging multiple URLs
DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep -o "https://[^\"]*luci-app-openclash[^\"]*\.${FILE_EXT}" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "$CROSS"
    echo -e "${RED}Error: Could not find a .${FILE_EXT} file in the latest release!${NC}"
    exit 1
else
    echo -e "$CHECK"
fi

# 4. Download the file
TEMP_FILE="/tmp/openclash_installer.${FILE_EXT}"
run_step "Downloading OpenClash (${FILE_EXT})" "curl -L -o '$TEMP_FILE' '$DOWNLOAD_URL'"

# 5. Install the downloaded file
if [ "$PKG_MANAGER" = "opkg" ]; then
    run_step "Installing OpenClash" "opkg install '$TEMP_FILE'"
else
    # Specific command requested for apk
    run_step "Installing OpenClash" "apk add -q --force-overwrite --clean-protected --allow-untrusted '$TEMP_FILE'"
fi

# 6. Cleanup
rm -f "$TEMP_FILE"
echo -e "\n${GREEN}Installation Complete!${NC}"
