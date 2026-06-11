#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v3.4
#   Server: repository.peditxos.ir (Hetzner)
# ------------------------------------------------

# 1. Reliable System Info Detection
OS_RELEASE_FILE="/etc/os-release"
OPENWRT_RELEASE_FILE="/etc/openwrt_release"

# Detect OS Type (openwrt or immortalwrt)
if [ -f "$OS_RELEASE_FILE" ]; then
    OS_TYPE=$(grep -q "ImmortalWrt" "$OS_RELEASE_FILE" && echo "immortalwrt" || echo "openwrt")
else
    OS_TYPE="openwrt"
fi

# Extract precise VERSION using a bulletproof parser
# This handles both single/double quotes and respects file priority
VERSION=$(cat "$OPENWRT_RELEASE_FILE" "$OS_RELEASE_FILE" 2>/dev/null | grep -E '^(VERSION_ID|DISTRIB_RELEASE)=' | head -n 1 | cut -d'=' -f2 | tr -d "'\" \\")

# Normalize to snapshot if version is missing or development build
if [ -z "$VERSION" ] || echo "$VERSION" | grep -qi "SNAPSHOT"; then
    VERSION="snapshot"
    SHORT_VER="snapshot"
else
    # Extract major.minor (e.g., 23.05.3 -> 23.05)
    SHORT_VER=$(echo "$VERSION" | cut -d. -f1-2)
fi

# Final safety check for SHORT_VER
if [ -z "$SHORT_VER" ]; then
    SHORT_VER="snapshot"
fi

# Detect Architecture reliably (excluding virtual 'all' package arch)
ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | grep -v 'all' | head -n 1)
if [ -z "$ARCH" ]; then
    ARCH=$(opkg info kernel 2>/dev/null | grep Architecture | awk '{print $2}')
fi

# Abort if critical information is completely missing
if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "⚠️ Error: Critical system info missing. (OS: $OS_TYPE, VER: $VERSION, ARCH: $ARCH)"
    exit 1
fi

echo "🔍 Detected: $OS_TYPE version $VERSION (Short: $SHORT_VER) | Arch: $ARCH"

# 2. Rebuild Official Feeds (Using $VERSION for proxy-compatibility)
cat <<EOF > /etc/opkg/distfeeds.conf
src/gz ${OS_TYPE}_base http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/base/
src/gz ${OS_TYPE}_luci http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/luci/
src/gz ${OS_TYPE}_packages http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/packages/
src/gz ${OS_TYPE}_routing http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/routing/
src/gz ${OS_TYPE}_telephony http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/telephony/
EOF

# 3. Rebuild Custom Feeds (Passwall - Using $SHORT_VER)
cat <<EOF > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_pkgs http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_packages/
src/gz peditxos_passwall_luci http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_luci/
src/gz peditxos_passwall2 http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall2/
EOF

# 4. Detect Package Manager & Add Signature Key
if command -v apk >/dev/null 2>&1; then
    PKG_TYPE="apk"
    echo "⬇️ Downloading APK public key..."
    wget -qO /etc/apk/keys/apk.pub http://repository.peditxos.ir/openwrt-passwall-build/apk.pub
else
    PKG_TYPE="ipk"
    echo "⬇️ Downloading IPK public key..."
    wget -qO /tmp/ipk.pub http://repository.peditxos.ir/openwrt-passwall-build/ipk.pub
    opkg-key add /tmp/ipk.pub 2>/dev/null
    rm -f /tmp/ipk.pub
fi

# 5. Clear Opkg/Apk Cache & Update Repositories
echo "🔄 Updating repositories..."
rm -f /var/opkg-lists/*
if [ "$PKG_TYPE" = "apk" ]; then
    apk update --allow-untrusted 2>/dev/null || true
else
    timeout 60 opkg update 2>/dev/null || true
fi

echo "------------------------------------------------"
echo "  ✅ SUCCESS: PeDitXOS Repo v3.4 Installed!"
echo "  Type: $PKG_TYPE | OS: $OS_TYPE $VERSION | Arch: $ARCH"
echo "------------------------------------------------"
