#!/bin/sh

# Colors and Symbols
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"

# Helper function for silent execution
run_step() {
    local message="$1"
    local command="$2"
    
    echo -n -e "$message... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "$CHECK"
    else
        # Even if it fails (e.g., package not installed), we don't want to break the script logic,
        # but showing a cross lets the user know it wasn't there or couldn't be removed.
        echo -e "$CROSS" 
        # Optional: Uncomment below to debug
        # echo -e "${RED}Error occurred or package not found.${NC}"
    fi
}

echo -e "\n--- OpenClash Safe Uninstaller By PeDitX---\n"

# 1. Detect Package Manager
PKG_MANAGER=""

if command -v opkg > /dev/null 2>&1; then
    PKG_MANAGER="opkg"
elif command -v apk > /dev/null 2>&1; then
    PKG_MANAGER="apk"
else
    echo -e "${RED}Error: Neither opkg nor apk found!${NC}"
    exit 1
fi

echo -e "System detected: ${GREEN}${PKG_MANAGER}${NC}"

# 2. Safe Removal (Package Only)
# We only remove 'luci-app-openclash'. 
# We do NOT use autoremove options to protect shared dependencies like dnsmasq-full, curl, etc.

if [ "$PKG_MANAGER" = "opkg" ]; then
    # opkg remove by default only removes the target package, leaving dependencies intact.
    run_step "Removing OpenClash Package (opkg)" "opkg remove luci-app-openclash"
else
    # apk del removes the package. We don't use 'purge' on dependencies.
    run_step "Removing OpenClash Package (apk)" "apk del luci-app-openclash"
fi

# 3. Optional: Clean up config directory (Commented out by default for safety)
# If you want to delete all settings/configs too, uncomment the lines below:
# echo -n -e "Removing config files (/etc/openclash)... "
# rm -rf /etc/openclash > /dev/null 2>&1
# echo -e "$CHECK"

echo -e "\n${GREEN}Uninstallation Complete! Shared dependencies were kept intact.${NC}"
