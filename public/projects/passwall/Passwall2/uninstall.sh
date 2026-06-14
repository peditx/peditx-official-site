#!/bin/sh

# PeDitXOS Utility - Uninstall Passwall 2
# Optimized: Auto-Detect Package Manager (Supports opkg & apk)

echo "Uninstalling Passwall 2..."

# --- 1. Detect Package Manager ---
if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    REMOVE_CMD="opkg remove --force-depends"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    REMOVE_CMD="apk del"
else
    echo "ERROR: No supported package manager found."
    exit 1
fi

# --- 2. Remove Passwall & Cleanup ---
{
    # 1. Stop and disable the service if it exists
    if [ -f "/etc/init.d/passwall2" ]; then
        /etc/init.d/passwall2 stop
        /etc/init.d/passwall2 disable
    fi

    # 2. Remove the packages based on detected manager
    $REMOVE_CMD luci-app-passwall2
    $REMOVE_CMD luci-i18n-passwall2-en-us
    $REMOVE_CMD luci-i18n-passwall2-fa-ir

    # 3. Delete the configuration files
    rm -f /etc/config/passwall2
    
    # 4. Cleanup UI files (if any were deployed by hard.zip)
    # Removing common paths associated with PeDitX UI
    rm -rf /usr/lib/lua/luci/controller/passwall2
    rm -rf /usr/lib/lua/luci/view/passwall2

    # 5. Commit changes and reload
    uci commit
    /sbin/reload_config
} > /dev/null 2>&1

echo "Passwall 2 and its rules have been removed successfully."
