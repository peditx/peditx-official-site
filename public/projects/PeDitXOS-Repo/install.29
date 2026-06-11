#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v2.9
#   Server: repository.peditxos.ir (Hetzner)
# ------------------------------------------------

# 1. Reliable System Info Detection
OS_TYPE=$(grep -q "ImmortalWrt" /etc/os-release && echo "immortalwrt" || echo "openwrt")
VERSION=$(grep "VERSION_ID=" /etc/os-release | cut -d'"' -f2)
[ -z "$VERSION" ] && VERSION=$(grep "VERSION=" /etc/os-release | cut -d'"' -f2 | awk '{print $1}')
SHORT_VER=$(echo $VERSION | awk -F. '{print $1"."$2}')
ARCH=$(opkg info kernel | grep Architecture | awk '{print $2}')

# Fallback: If version is still empty, default to 'snapshot' to prevent aborting
if [ -z "$VERSION" ]; then
    echo "⚠️ Warning: Could not detect firmware version. Falling back to 'snapshot'."
    VERSION="snapshot"
    SHORT_VER="snapshot"
fi

echo "🔍 Detected: $OS_TYPE $VERSION ($ARCH)"

# 2. Rebuild Official Feeds
cat <<EOF > /etc/opkg/distfeeds.conf
src/gz ${OS_TYPE}_base http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/base/
src/gz ${OS_TYPE}_luci http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/luci/
src/gz ${OS_TYPE}_packages http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/packages/
src/gz ${OS_TYPE}_routing http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/routing/
src/gz ${OS_TYPE}_telephony http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/telephony/
EOF

# 3. Rebuild Custom Feeds (Passwall)
cat <<EOF > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_pkgs http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_packages/
src/gz peditxos_passwall_luci http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_luci/
src/gz peditxos_passwall2 http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall2/
EOF

# 4. Detect Package Manager & Add Key
if command -v apk >/dev/null 2>&1; then
    PKG_TYPE="apk"
    echo "⬇️ Downloading APK key..."
    wget -qO /etc/apk/keys/apk.pub http://repository.peditxos.ir/openwrt-passwall-build/apk.pub
else
    PKG_TYPE="ipk"
    echo "⬇️ Downloading IPK key..."
    wget -qO /tmp/ipk.pub http://repository.peditxos.ir/openwrt-passwall-build/ipk.pub
    opkg-key add /tmp/ipk.pub 2>/dev/null
fi

# 5. Clear Cache & Update
echo "🔄 Updating repositories..."
rm -f /var/opkg-lists/*
if [ "$PKG_TYPE" = "apk" ]; then
    apk update --allow-untrusted 2>/dev/null || true
else
    timeout 60 opkg update 2>/dev/null || true
fi

echo "------------------------------------------------"
echo "  ✅ SUCCESS: PeDitXOS Repo 2.9 Installed!"
echo "  Type: $PKG_TYPE | OS: $OS_TYPE $VERSION"
echo "------------------------------------------------"
