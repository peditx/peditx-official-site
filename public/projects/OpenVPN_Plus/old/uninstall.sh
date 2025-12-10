#!/bin/sh

# =======================================================
# Uninstall Script for OpenVPN + SOCKS5 Setup
# =======================================================

echo ">>> [1/3] Removing Passwall/Passwall2 Node configuration..."

# Remove from Passwall2 if exists
if uci show passwall2.ovpnnode >/dev/null 2>&1; then
    {
        uci delete passwall2.ovpnnode
        uci commit passwall2
    } >/dev/null 2>&1
    echo "✔ Removed 'OpenVPN' node from Passwall2."
fi

# Remove from Passwall if exists
if uci show passwall.ovpnnode >/dev/null 2>&1; then
    {
        uci delete passwall.ovpnnode
        uci commit passwall
    } >/dev/null 2>&1
    echo "✔ Removed 'OpenVPN' node from Passwall."
fi

echo ">>> [2/3] Stopping and Removing Microsocks configuration..."

# Stop service and delete config
{
    /etc/init.d/microsocks stop
    /etc/init.d/microsocks disable
    uci delete microsocks
    uci commit microsocks
} >/dev/null 2>&1
echo "✔ Microsocks configuration removed."

echo ">>> [3/3] Removing installed packages..."
# Removing specific packages installed by the setup script
# We keep 'curl', 'wget-ssl', 'resolveip' as they are common dependencies
PACKAGES="microsocks luci-app-openvpn openvpn-openssl"

if opkg remove $PACKAGES >/dev/null 2>&1; then
    echo "✔ Packages ($PACKAGES) removed successfully."
else
    # Sometimes packages are already removed or dependent on others
    echo "! Note: Some packages might have already been removed or were not found."
fi

echo ">>> Uninstall Complete.  Made by PeDitX"
