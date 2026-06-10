#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v2.9
#   Server: repository.peditxos.ir (Hetzner)
# ------------------------------------------------

# 1. Auto-Detect System Info
OS_TYPE=$(grep -q "ImmortalWrt" /etc/os-release && echo "immortalwrt" || echo "openwrt")
VERSION=$(grep "VERSION_ID=" /etc/os-release | awk -F '"' '{print $2}')
SHORT_VER=$(echo $VERSION | awk -F. '{print $1"."$2}')
ARCH=$(opkg info kernel | grep Architecture | awk '{print $2}')

echo "🔍 Detected: $OS_TYPE $VERSION ($ARCH)"

# 2. Rebuild Official Feeds (Safe Overwrite)
BASE_URL="http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}"

cat <<FEEDS > /etc/opkg/distfeeds.conf
src/gz ${OS_TYPE}_base ${BASE_URL}/base/
src/gz ${OS_TYPE}_luci ${BASE_URL}/luci/
src/gz ${OS_TYPE}_packages ${BASE_URL}/packages/
src/gz ${OS_TYPE}_routing ${BASE_URL}/routing/
src/gz ${OS_TYPE}_telephony ${BASE_URL}/telephony/
FEEDS

# 3. Rebuild Custom Feeds (Passwall)
PASS_URL="http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}"

cat <<CUSTOM > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_pkgs ${PASS_URL}/passwall_packages/
src/gz peditxos_passwall_luci ${PASS_URL}/passwall_luci/
src/gz peditxos_passwall2 ${PASS_URL}/passwall2/
CUSTOM

# 4. Detect Package Manager & Add Key
if command -v apk >/dev/null 2>&1; then
    PKG_TYPE="apk"
    KEY_NAME="apk.pub"
    echo "⬇️ Downloading APK key..."
    wget -qO /etc/apk/keys/$KEY_NAME http://repository.peditxos.ir/openwrt-passwall-build/$KEY_NAME
else
    PKG_TYPE="ipk"
    KEY_NAME="ipk.pub"
    echo "⬇️ Downloading IPK key..."
    wget -qO /tmp/$KEY_NAME http://repository.peditxos.ir/openwrt-passwall-build/$KEY_NAME
    opkg-key add /tmp/$KEY_NAME 2>/dev/null
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
echo "  ✅ SUCCESS: PeDitXOS Repo 2.9 Installed!    "
echo "  Type: $PKG_TYPE | OS: $OS_TYPE $SHORT_VER    "
echo "------------------------------------------------"
