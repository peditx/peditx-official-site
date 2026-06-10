cat << 'EOF' > /tmp/install.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  PeDitXOS Repository Smart Installer v2.9   "
echo "  Server: repository.peditxos.ir (Hetzner)     "
echo "------------------------------------------------"

# 1. Auto-Detect System Info
OS_TYPE=$(grep -q "ImmortalWrt" /etc/os-release && echo "immortalwrt" || echo "openwrt")
VERSION=$(grep "VERSION_ID=" /etc/os-release | awk -F '"' '{print $2}')
SHORT_VER=$(echo $VERSION | awk -F. '{print $1"."$2}')
ARCH=$(opkg info kernel | grep Architecture | awk '{print $2}')

echo "🔍 Detected: $OS_TYPE $VERSION ($ARCH)"

# 2. Rebuild Official Feeds (Safe Overwrite)
cat <<FEEDS > /etc/opkg/distfeeds.conf
src/gz ${OS_TYPE}_base http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/base
src/gz ${OS_TYPE}_luci http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/luci
src/gz ${OS_TYPE}_packages http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/packages
src/gz ${OS_TYPE}_routing http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/routing
src/gz ${OS_TYPE}_telephony http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/telephony
FEEDS

# 3. Rebuild Custom Feeds (Passwall)
cat <<CUSTOM > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_pkgs http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_packages
src/gz peditxos_passwall_luci http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall_luci
src/gz peditxos_passwall2 http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/passwall2
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
echo "  ✅ SUCCESS: PeDitXOS Repo 2.9 Installed!   "
echo "  Type: $PKG_TYPE | OS: $OS_TYPE $SHORT_VER    "
echo "------------------------------------------------"
EOF

sh /tmp/install.sh && rm /tmp/install.sh
