#!/bin/sh

# PeDitXOS Utility - Uninstall Passwall 2
# This script removes ONLY Passwall 2 app and its specific rules.

echo "Uninstalling Passwall 2..."

{
    # 1. Stop and disable the service
    /etc/init.d/passwall2 stop > /dev/null 2>&1
    /etc/init.d/passwall2 disable > /dev/null 2>&1

    # 2. Remove the packages (App and translations)
    opkg remove luci-app-passwall2 --force-depends > /dev/null 2>&1
    opkg remove luci-i18n-passwall2-en-us > /dev/null 2>&1
    opkg remove luci-i18n-passwall2-fa-ir > /dev/null 2>&1

    # 3. Delete the configuration rules
    rm -f /etc/config/passwall2
    
    # 4. Commit changes and reload
    uci commit
    /sbin/reload_config
} > /dev/null 2>&1

echo "Passwall 2 and its rules have been removed successfully."
