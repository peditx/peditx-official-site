#!/bin/sh
# PeDitXOS - Uninstall All Tools
echo "Uninstalling all PeDitXOS related packages..."
if command -v apk >/dev/null 2>&1; then
    apk remove luci-app-passwall luci-app-passwall2 luci-app-torplus luci-app-sshplus luci-app-aircast luci-app-dns-changer
elif command -v opkg >/dev/null 2>&1; then
    opkg remove luci-app-passwall luci-app-passwall2 luci-app-torplus luci-app-sshplus luci-app-aircast luci-app-dns-changer
fi
echo "Uninstallation complete."
