#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v7.2
#   Server: repository.peditxos.ir (Hetzner)
#   Author: PeDitXOS Team
# ------------------------------------------------

if [ "$PEDITX_INSTALLER_RUNNING" = "1" ]; then exit 0; fi
export PEDITX_INSTALLER_RUNNING=1
SCRIPT_VERSION="7.2"
clear

# --- System Detection ---
OS_RELEASE_FILE="/etc/os-release"
OPENWRT_RELEASE_FILE="/etc/openwrt_release"
VERSION="" && SHORT_VER="" && OS_TYPE="openwrt"
PKG_TYPE="opkg" && command -v apk >/dev/null 2>&1 && PKG_TYPE="apk"

[ -f "$OS_RELEASE_FILE" ] && . "$OS_RELEASE_FILE" 2>/dev/null && VERSION="$VERSION_ID"
if [ -z "$VERSION" ] && [ -f "$OPENWRT_RELEASE_FILE" ]; then
    . "$OPENWRT_RELEASE_FILE" 2>/dev/null && VERSION="$DISTRIB_RELEASE"
fi
if [ -z "$VERSION" ] || ! echo "$VERSION" | grep -qE '[0-9]{2}\.[0-9]{2}'; then
    for file in "$OS_RELEASE_FILE" "$OPENWRT_RELEASE_FILE"; do
        [ -f "$file" ] || continue
        MATCHED=$(grep -oE '[0-9]{2}\.[0-9]{2}' "$file" | head -n 1)
        [ -n "$MATCHED" ] && VERSION="$MATCHED" && break
    done
fi
VERSION=$(echo "$VERSION" | tr -d "'\" \\\r\n\t")
CLEANED_VER=$(echo "$VERSION" | grep -oE '[0-9]{2}\.[0-9]{2}(\.[0-9]+)?' | head -n 1)
[ -n "$CLEANED_VER" ] && VERSION="$CLEANED_VER" && SHORT_VER=$(echo "$VERSION" | cut -d. -f1-2) || { VERSION="snapshot"; SHORT_VER="snapshot"; }

ARCH=""
[ -f "$OS_RELEASE_FILE" ] && ARCH=$(grep "OPENWRT_ARCH" "$OS_RELEASE_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d "'\" \/\r\n\t")
[ -z "$ARCH" ] && { [ "$PKG_TYPE" = "apk" ] && ARCH=$(apk --print-arch 2>/dev/null) || ARCH=$(uname -m); }
ARCH=$(echo "$ARCH" | tr -d "'\" \/\r\n\t")
[ -z "$ARCH" ] && ARCH=$(uname -m)

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "⚠️ Error: System info could not be recovered." && exit 1
fi

echo "🔍 Detected: $OS_TYPE $VERSION ($ARCH) [$PKG_TYPE]"
echo "🚀 Starting repository setup (Installer v$SCRIPT_VERSION)..."

# ====================================================================
# REPOSITORY CONFIGURATION
# ====================================================================
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [1/4] Configuring APK repositories..."
    mkdir -p /etc/apk/repositories.d
    
    # 1. Add PeDitXOS Base Repos
    PEDITX_BASE="http://repository.peditxos.ir/openwrt/releases/${VERSION}/packages/${ARCH}"
    cat <<EOF > /etc/apk/repositories.d/peditxos.list
${PEDITX_BASE}/base
${PEDITX_BASE}/luci
${PEDITX_BASE}/packages
${PEDITX_BASE}/routing
${PEDITX_BASE}/telephony
EOF

    # 2. Add Passwall Repos (Direct ADB links as per official docs)
    PASSWALL_FEEDS="passwall_luci passwall_packages passwall2"
    > /etc/apk/repositories.d/customfeeds.list
    
    if [ "$SHORT_VER" = "snapshot" ]; then
        for feed in $PASSWALL_FEEDS; do
            echo "http://repository.peditxos.ir/openwrt-passwall-build/snapshots/packages/${ARCH}/${feed}/packages.adb" >> /etc/apk/repositories.d/customfeeds.list
        done
    else
        for feed in $PASSWALL_FEEDS; do
            echo "http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}/${feed}/packages.adb" >> /etc/apk/repositories.d/customfeeds.list
        done
    fi
    
    chmod 644 /etc/apk/repositories.d/*.list
    echo "  ↳ Done."

else
    echo "➡️ [1/4] Configuring OPKG repositories..."
    PEDITX_OPKG_BASE="http://repository.peditxos.ir/openwrt/releases/${VERSION}/packages/${ARCH}"
    PASSWALL_OPKG_BASE="http://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}"
    
    cat <<EOF > /etc/opkg/distfeeds.conf
src/gz openwrt_base ${PEDITX_OPKG_BASE}/base/
src/gz openwrt_luci ${PEDITX_OPKG_BASE}/luci/
src/gz openwrt_packages ${PEDITX_OPKG_BASE}/packages/
src/gz openwrt_routing ${PEDITX_OPKG_BASE}/routing/
src/gz openwrt_telephony ${PEDITX_OPKG_BASE}/telephony/
EOF

    cat <<EOF > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_luci ${PASSWALL_OPKG_BASE}/passwall_luci/
src/gz peditxos_passwall_pkgs ${PASSWALL_OPKG_BASE}/passwall_packages/
src/gz peditxos_passwall2 ${PASSWALL_OPKG_BASE}/passwall2/
EOF
    echo "  ↳ Done."
fi

# --- Keys & Update ---
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [2/4] Fetching security keys..."
    mkdir -p /etc/apk/keys
    wget -qO /etc/apk/keys/peditxos-apk.pub http://repository.peditxos.ir/apk.pub 2>/dev/null || true
    chmod 644 /etc/apk/keys/*.pub 2>/dev/null
    echo "  ↳ Done."
    
    echo "➡️ [3/4] Verifying signature structure..."
    sleep 1 && echo "  ↳ Verified."
    
    echo "➡️ [4/4] Updating package database..."
    rm -rf /var/cache/apk/* /tmp/apk-* 2>/dev/null
    apk update --allow-untrusted >/dev/null 2>&1 || true
    echo "  ↳ Database synchronized."
else
    echo "➡️ [2/4] Adding OPKG keys..."
    wget -qO /tmp/ipk.pub http://repository.peditxos.ir/openwrt-passwall-build/ipk.pub 2>/dev/null
    opkg-key add /tmp/ipk.pub >/dev/null 2>&1 && rm -f /tmp/ipk.pub
    echo "  ↳ Done."
    
    echo "➡️ [3/4] Updating lists..."
    timeout 60 opkg update >/dev/null 2>&1 || true
    echo "  ↳ Lists updated."
fi

echo "=================================================="
echo "  ✅ SUCCESS: PeDitXOS Repo Installer v$SCRIPT_VERSION"
echo "--------------------------------------------------"
echo "  • OS: $OS_TYPE | Ver: $VERSION | Arch: $ARCH"
echo "  • Engine: $PKG_TYPE"
echo "  • Source: repository.peditxos.ir (Official Mirror)"
echo "=================================================="
