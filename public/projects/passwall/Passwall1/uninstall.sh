#!/bin/sh

# PeDitXOS Utility - Uninstall Passwall 1
# This script removes ONLY Passwall 1 (Classic) app and its specific rules.

echo "Uninstalling Passwall 1..."

{
    # 1. Stop and disable the service
    /etc/init.d/passwall stop > /dev/null 2>&1
    /etc/init.d/passwall disable > /dev/null 2>&1

    # 2. Remove the packages (App and translations)
    opkg remove luci-app-passwall --force-depends > /dev/null 2>&1
    opkg remove luci-i18n-passwall-en-us > /dev/null 2>&1

    # 3. Delete the configuration rules
    rm -f /etc/config/passwall
    
    # 4. Commit changes and reload
    uci commit
    /sbin/reload_config
} > /dev/null 2>&1

echo "Passwall 1 and its rules have been removed successfully."
