#!/bin/sh

# PeDitXOS Unified Setup Utility - Professional Version
# Optimized: Modern OpenWrt (25.12+) Package Management

DEBUG_LOG="/tmp/peditx_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "           PeDitXOS Setup Utility Starting          "
echo "----------------------------------------------------"

# --- 1. Detect Package Manager ---
if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
else
    echo "ERROR: No supported package manager found."
    exit 1
fi

# --- 2. Package Installation ---
echo -n "2. Installing requirements via $PKG_MGR... "
{
    # List of required packages for full functionality
    PKGS="luci-app-passwall2 wget-ssl unzip ca-bundle dnsmasq-full xray-core kmod-nft-socket kmod-nft-tproxy kmod-inet-diag kernel kmod-netlink-diag kmod-tun luci-lib-ipkg v2ray-geosite-ir"
    
    if [ "$PKG_MGR" = "opkg" ]; then
        opkg update
        opkg install $PKGS
    else
        # In new OpenWrt versions using apk, we ensure all dependencies are resolved
        apk update
        apk add $PKGS
    fi
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 3. UI and Core File Deployment ---
echo -n "3. Deploying PeDitX UI & Core Files... "
{
    cd /tmp
    # Updated to GitHub source
    wget -q -O hard.zip https://github.com/PeDitXOS/PeDitXOS-passwall2/raw/main/files/hard.zip
    if [ -f "hard.zip" ]; then
        unzip -o hard.zip -d /
        rm hard.zip
    fi
    cd
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 4. Finalizing ---
echo "----------------------------------------------------"
echo "  Setup Finished Successfully. Made By : PeDitX     "
echo "----------------------------------------------------"
